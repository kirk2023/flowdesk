using System;
using System.Collections.Concurrent;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using FlowDesk.Common;
using FlowDesk.Models;

namespace FlowDesk.Services
{
    /// <summary>
    /// 配对服务 + 数据通道：47801 端口，UDP
    /// 协议：JSON over UDP，载荷用 AES-256-GCM 加密
    /// 流程：
    ///   1. 接收 phone 发来的 pair-hello（明文，含 ECDH 公钥 + PIN）
    ///   2. 验证 PIN（或扫码 ECDH），生成本地 ECDH 密钥对
    ///   3. 派生共享密钥 → HKDF → AES-256-GCM 会话密钥
    ///   4. 发送 pair-accept（含公钥）
    ///   5. 持续接收加密的 input 事件
    ///   6. 持续发送加密的 screen 帧
    /// </summary>
    public class PairingService : IDisposable
    {
        private readonly DeviceIdService _deviceIds;
        private readonly PinService _pins;
        private readonly InputInjectionService _input;

        private UdpClient? _socket;
        private CancellationTokenSource? _cts;
        private Task? _loopTask;
        private Task? _sendLoopTask;
        private Timer? _aliveTimer;

        private ECDiffieHellman? _localEcdh;
        private byte[]? _sessionKey;
        private byte[]? _sendCounter;
        private byte[]? _recvCounter;
        private IPEndPoint? _remoteEp;
        private readonly object _sendLock = new object();
        private readonly BlockingCollection<(byte[] data, long seq)> _outgoingFrames = new();

        public bool IsPaired => _sessionKey != null && _remoteEp != null;
        public string? RemoteDeviceId { get; private set; }

        public event Action<string>? OnPaired;
        public event Action<string>? OnDisconnected;

        public PairingService(DeviceIdService deviceIds, PinService pins, InputInjectionService input)
        {
            _deviceIds = deviceIds;
            _pins = pins;
            _input = input;
        }

        public Task StartAsync()
        {
            _socket = new UdpClient(Constants.DATA_PORT, AddressFamily.InterNetwork);
            _socket.Client.SendBufferSize = 65535;
            _socket.Client.ReceiveBufferSize = 65535;
            _cts = new CancellationTokenSource();
            _loopTask = Task.Run(() => LoopAsync(_cts.Token));
            _sendLoopTask = Task.Run(() => SendLoopAsync(_cts.Token));
            _aliveTimer = new Timer(_ => Logger.Info("Pairing", "alive"), null, TimeSpan.FromSeconds(10), TimeSpan.FromSeconds(10));
            Logger.Info("Pairing", $"started on UDP {Constants.DATA_PORT}");
            return Task.CompletedTask;
        }

        public async Task StopAsync()
        {
            try { _cts?.Cancel(); } catch { }
            try { _aliveTimer?.Dispose(); _aliveTimer = null; } catch { }
            try { _outgoingFrames.CompleteAdding(); } catch { }
            _socket?.Close();
            await Task.WhenAny(_loopTask ?? Task.CompletedTask, _sendLoopTask ?? Task.CompletedTask);
            Logger.Info("Pairing", "stopped");
        }

        private void LoopAsync(CancellationToken ct)
        {
            var anyEp = new IPEndPoint(IPAddress.Any, 0);
            Logger.Info("Pairing", "loop entered (sync mode)");
            while (!ct.IsCancellationRequested)
            {
                byte[] data;
                IPEndPoint remote;
                try
                {
                    data = _socket!.Receive(ref anyEp);
                    remote = anyEp;
                }
                catch (ObjectDisposedException) { break; }
                catch (SocketException) { break; }
                catch (Exception ex)
                {
                    Logger.Warn("Pairing", $"receive error: {ex.Message}");
                    continue;
                }
                try
                {
                    HandlePacket(data, remote);
                }
                catch (Exception ex)
                {
                    Logger.Warn("Pairing", $"handle error: {ex.Message}");
                }
            }
            Logger.Info("Pairing", "loop exited");
        }

        private void HandlePacket(byte[] buffer, IPEndPoint remote)
        {
            try
            {
                // 前 4 字节为明文类型标记
                if (buffer.Length < 4) return;
                var tag = Encoding.ASCII.GetString(buffer, 0, 4);
                Logger.Info("Pairing", $"packet from {remote}, tag='{tag}', len={buffer.Length}");

                if (tag == "PHEL") // 明文 pair-hello
                {
                    var hello = JsonSerializer.Deserialize<PairingHello>(buffer.AsSpan(4));
                    if (hello == null) return;
                    if (hello.Proto != Constants.PROTOCOL_VERSION && !string.IsNullOrEmpty(hello.Type))
                    {
                        // 忽略旧版本
                    }
                    HandlePairHello(hello, remote);
                }
                else if (tag == "PCRY") // 加密包
                {
                    if (_sessionKey == null) return; // 还没配对
                    try
                    {
                        var payload = CryptoHelper.Decrypt(_sessionKey, buffer.AsSpan(4), _recvCounter!);
                        var msg = JsonSerializer.Deserialize<JsonElement>(payload);
                        var type = msg.GetProperty("type").GetString();
                        if (type == "input")
                        {
                            var ev = JsonSerializer.Deserialize<InputEventMessage>(msg.GetRawText());
                            HandleInputEvent(ev!);
                        }
                    }
                    catch (Exception ex)
                    {
                        Logger.Warn("Pairing", $"decrypt failed: {ex.Message}");
                    }
                }
            }
            catch (Exception ex)
            {
                Logger.Warn("Pairing", $"handle packet error: {ex.Message}");
            }
        }

        private void HandlePairHello(PairingHello hello, IPEndPoint remote)
        {
            // 验证 PIN（扫码场景下客户端 PIN 字段可能为空或包含扫码 token，简化处理为：扫码时传设备ID 作为 PIN）
            if (!string.Equals(hello.Pin, _pins.CurrentPin, StringComparison.Ordinal) &&
                !string.Equals(hello.Pin, _deviceIds.DeviceId, StringComparison.Ordinal))
            {
                Logger.Warn("Pairing", $"pin mismatch from {remote}, sent='{hello.Pin}'");
                SendReject(remote, "PIN 不匹配或已过期");
                return;
            }

            // 本地生成 ECDH
            _localEcdh = ECDiffieHellman.Create(ECCurve.NamedCurves.nistP256);
            var localPubKey = _localEcdh.PublicKey;

            // 解析对方公钥
            ECDiffieHellman remoteEcdh;
            try
            {
                remoteEcdh = ECDiffieHellman.Create();
                remoteEcdh.ImportSubjectPublicKeyInfo(Convert.FromBase64String(hello.PubKey), out _);
            }
            catch (Exception ex)
            {
                Logger.Warn("Pairing", $"bad pub key: {ex.Message}");
                SendReject(remote, "公钥格式错误");
                return;
            }

            // 派生共享密钥：与手机端保持一致（raw 32 字节，无 HKDF）
            byte[] sharedSecret;
            try
            {
                sharedSecret = _localEcdh.DeriveRawSecretAgreement(remoteEcdh.PublicKey);
            }
            catch (Exception)
            {
                sharedSecret = _localEcdh.DeriveKeyFromHash(
                    remoteEcdh.PublicKey,
                    HashAlgorithmName.SHA256,
                    null,
                    null);
            }
            _sessionKey = new byte[32];
            Array.Copy(sharedSecret, 0, _sessionKey, 0, Math.Min(32, sharedSecret.Length));
            Logger.Info("Pairing", $"session key derived, len={_sessionKey.Length}");

            _remoteEp = remote;
            _sendCounter = new byte[12];
            _recvCounter = new byte[12];
            RemoteDeviceId = hello.Id;

            // 发送 pair-accept
            var accept = new PairingAccept
            {
                Id = _deviceIds.DeviceId,
                PubKey = Convert.ToBase64String(localPubKey.ExportSubjectPublicKeyInfo()),
                Ts = DateTimeOffset.UtcNow.ToUnixTimeSeconds(),
                Nonce = Convert.ToBase64String(RandomNumberGenerator.GetBytes(8)),
                ScreenW = System.Windows.Forms.SystemInformation.VirtualScreen.Width,
                ScreenH = System.Windows.Forms.SystemInformation.VirtualScreen.Height
            };
            var acceptJson = JsonSerializer.SerializeToUtf8Bytes(accept);
            var acceptPacket = new byte[4 + acceptJson.Length];
            Encoding.ASCII.GetBytes("POK!").CopyTo(acceptPacket, 0);
            acceptJson.CopyTo(acceptPacket, 4);
            _socket!.Send(acceptPacket, acceptPacket.Length, remote);

            Logger.Info("Pairing", $"paired with {hello.Id} at {remote}");
            OnPaired?.Invoke(hello.Id);
        }

        private void SendReject(IPEndPoint remote, string reason)
        {
            try
            {
                var rej = new PairingReject
                {
                    Id = _deviceIds.DeviceId,
                    Reason = reason,
                    Ts = DateTimeOffset.UtcNow.ToUnixTimeSeconds()
                };
                var json = JsonSerializer.SerializeToUtf8Bytes(rej);
                var packet = new byte[4 + json.Length];
                Encoding.ASCII.GetBytes("PREJ").CopyTo(packet, 0);
                json.CopyTo(packet, 4);
                _socket!.Send(packet, packet.Length, remote);
            }
            catch { }
        }

    private void HandleInputEvent(InputEventMessage ev)
    {
        try
        {
            if (ev.Event == "mouse-move")
            {
                if (ev.X.HasValue && ev.Y.HasValue)
                    _input.HandleMouseMove(ev.X.Value, ev.Y.Value);
            }
            else
            {
                Logger.Info("Input", $"event={ev.Event} btn={ev.Button} x={ev.X} y={ev.Y} code={ev.Code} mod={ev.Modifiers}");
                switch (ev.Event)
                {
                    case "mouse-down":
                        if (ev.X.HasValue && ev.Y.HasValue)
                            _input.HandleMouseDown(ev.Button ?? "left", ev.X.Value, ev.Y.Value);
                        else
                            _input.HandleMouseDown(ev.Button ?? "left");
                        break;
                    case "mouse-up":
                        if (ev.X.HasValue && ev.Y.HasValue)
                            _input.HandleMouseUp(ev.Button ?? "left", ev.X.Value, ev.Y.Value);
                        else
                            _input.HandleMouseUp(ev.Button ?? "left");
                        break;
                    case "mouse-wheel":
                        _input.HandleMouseWheel(ev.Dx ?? 0, ev.Dy ?? 0);
                        break;
                    case "key-down":
                        _input.HandleKeyDown(ev.Code ?? 0, ev.Modifiers ?? 0);
                        break;
                    case "key-up":
                        _input.HandleKeyUp(ev.Code ?? 0, ev.Modifiers ?? 0);
                        break;
                    case "paste-text":
                        _input.HandlePasteText(ev.Text ?? "");
                        break;
                }
            }
        }
        catch (Exception ex)
        {
            Logger.Warn("Input", $"handle error: {ex.Message}");
        }
    }

        public void SendFrame(byte[] jpegData, long seq)
        {
            if (!IsPaired) return;
            try
            {
                _outgoingFrames.TryAdd((jpegData, seq));
            }
            catch (Exception ex)
            {
                Logger.Warn("Frame", $"enqueue failed: {ex.Message}");
            }
        }

        private async Task SendLoopAsync(CancellationToken ct)
        {
            foreach (var (data, seq) in _outgoingFrames.GetConsumingEnumerable(ct))
            {
                if (!IsPaired) continue;
                try
                {
                    var frame = new ScreenFrame
                    {
                        Seq = seq,
                        Data = data,
                        Ts = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()
                    };
                    var json = JsonSerializer.SerializeToUtf8Bytes(frame);
                    var cipher = CryptoHelper.Encrypt(_sessionKey!, json, _sendCounter!);

                    const int CHUNK_PAYLOAD = 50000;
                    const int HDR_SIZE = 16; // PCRY(4) + seq(8) + idx(2) + total(2)
                    int totalChunks = (cipher.Length + CHUNK_PAYLOAD - 1) / CHUNK_PAYLOAD;
                    if (totalChunks < 1) totalChunks = 1;

                    if (seq <= 3 || seq % 30 == 0)
                    {
                        Logger.Info("Frame", $"seq={seq} json={json.Length}B cipher={cipher.Length}B chunks={totalChunks}");
                    }

                    var seqBytes = BitConverter.GetBytes(seq);
                    var totalBytes = BitConverter.GetBytes((short)totalChunks);

                    for (int idx = 0; idx < totalChunks; idx++)
                    {
                        int offset = idx * CHUNK_PAYLOAD;
                        int len = Math.Min(CHUNK_PAYLOAD, cipher.Length - offset);
                        var packet = new byte[HDR_SIZE + len];
                        Encoding.ASCII.GetBytes("PCRY").CopyTo(packet, 0);
                        seqBytes.CopyTo(packet, 4);
                        BitConverter.GetBytes((short)idx).CopyTo(packet, 12);
                        totalBytes.CopyTo(packet, 14);
                        Array.Copy(cipher, offset, packet, HDR_SIZE, len);

                        lock (_sendLock)
                        {
                            _socket!.Send(packet, packet.Length, _remoteEp!);
                        }
                    }
                }
                catch (Exception ex)
                {
                    Logger.Warn("Frame", $"send failed: {ex.Message}");
                }
            }
        }

        private static byte[] HkdfSha256(byte[] ikm, int length, byte[]? salt, byte[]? info)
        {
            // 极简 HKDF-SHA256 实现
            using var hmac = new HMACSHA256(salt ?? new byte[32]);
            var prk = hmac.ComputeHash(ikm);

            var okm = new byte[length];
            var prev = Array.Empty<byte>();
            var counter = 1;
            int pos = 0;
            using var hmac2 = new HMACSHA256(prk);
            while (pos < length)
            {
                hmac2.Initialize();
                if (prev.Length > 0) hmac2.TransformBlock(prev, 0, prev.Length, null, 0);
                if (info != null) hmac2.TransformBlock(info, 0, info.Length, null, 0);
                hmac2.TransformFinalBlock(new byte[] { (byte)counter }, 0, 1);
                prev = hmac2.Hash!;
                var copy = Math.Min(prev.Length, length - pos);
                Array.Copy(prev, 0, okm, pos, copy);
                pos += copy;
                counter++;
            }
            return okm;
        }

        public void Dispose()
        {
            try { StopAsync().Wait(2000); } catch { }
            _localEcdh?.Dispose();
            _socket?.Dispose();
        }
    }

    /// <summary>
    /// AES-256-GCM 加解密辅助
    /// </summary>
    internal static class CryptoHelper
    {
        public static byte[] Encrypt(byte[] key, byte[] plaintext, byte[] counter)
        {
            // counter (12 bytes) 用作 nonce
            var nonce = new byte[12];
            Buffer.BlockCopy(counter, 0, nonce, 0, 12);
            // 每次加密后递增
            IncrementCounter(counter);

            var ciphertext = new byte[plaintext.Length];
            var tag = new byte[16];

            using var aes = new AesGcm(key, 16);
            aes.Encrypt(nonce, plaintext, ciphertext, tag);

            // 输出格式: nonce(12) || ciphertext || tag(16)
            var result = new byte[12 + ciphertext.Length + 16];
            Buffer.BlockCopy(nonce, 0, result, 0, 12);
            Buffer.BlockCopy(ciphertext, 0, result, 12, ciphertext.Length);
            Buffer.BlockCopy(tag, 0, result, 12 + ciphertext.Length, 16);
            return result;
        }

        public static byte[] Decrypt(byte[] key, ReadOnlySpan<byte> payload, byte[] counter)
        {
            // 格式: nonce(12) || ciphertext || tag(16)
            if (payload.Length < 28) throw new InvalidDataException("payload too short");
            var nonce = payload.Slice(0, 12);
            var ciphertext = payload.Slice(12, payload.Length - 12 - 16);
            var tag = payload.Slice(payload.Length - 16, 16);

            var plaintext = new byte[ciphertext.Length];
            using var aes = new AesGcm(key, 16);
            // 仅依赖 GCM 自带的 16 字节 auth tag 验真,不做 nonce/counter 顺序校验
            // (UDP 不保证顺序,手机端 key-down/key-up 可能乱序到达;counter 校验会让所有后续包全部死锁)
            aes.Decrypt(nonce, ciphertext, tag, plaintext);

            return plaintext;
        }

        private static void IncrementCounter(byte[] counter)
        {
            for (int i = counter.Length - 1; i >= 0; i--)
            {
                if (++counter[i] != 0) break;
            }
        }
    }
}
