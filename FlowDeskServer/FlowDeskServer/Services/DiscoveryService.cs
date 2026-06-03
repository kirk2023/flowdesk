using System;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using FlowDesk.Common;
using FlowDesk.Models;

namespace FlowDesk.Services
{
    /// <summary>
    /// UDP 设备发现：周期性向局域网广播 iam，响应 whoami
    /// 端口 47800
    /// </summary>
    public class DiscoveryService : IDisposable
    {
        private readonly DeviceIdService _deviceIds;
        private UdpClient? _socket;
        private CancellationTokenSource? _cts;
        private Task? _loopTask;

        public DiscoveryService(DeviceIdService deviceIds)
        {
            _deviceIds = deviceIds;
        }

        public Task StartAsync()
        {
            _socket = new UdpClient(Constants.DISCOVERY_PORT, AddressFamily.InterNetwork);
            _socket.EnableBroadcast = true;
            _cts = new CancellationTokenSource();
            _loopTask = Task.Run(() => LoopAsync(_cts.Token));
            Logger.Info("Discovery", $"started on UDP {Constants.DISCOVERY_PORT}");
            return Task.CompletedTask;
        }

        public void Stop()
        {
            try { _cts?.Cancel(); } catch { }
            try { _socket?.Close(); } catch { }
            _socket = null;
            Logger.Info("Discovery", "stopped");
        }

        private async Task LoopAsync(CancellationToken ct)
        {
            // 启动后立刻广播一次
            BroadcastIam();
            var lastBroadcast = DateTimeOffset.UtcNow;

            while (!ct.IsCancellationRequested)
            {
                try
                {
                    // 接收
                    var receiveTask = _socket!.ReceiveAsync();
                    var timeoutTask = Task.Delay(500, ct);
                    var done = await Task.WhenAny(receiveTask, timeoutTask);
                    if (done == receiveTask)
                    {
                        var result = await receiveTask;
                        HandlePacket(result.Buffer, result.RemoteEndPoint);
                    }

                    // 每 2 秒广播一次
                    if ((DateTimeOffset.UtcNow - lastBroadcast).TotalSeconds >= 2)
                    {
                        BroadcastIam();
                        lastBroadcast = DateTimeOffset.UtcNow;
                    }
                }
                catch (OperationCanceledException) { break; }
                catch (Exception ex)
                {
                    Logger.Warn("Discovery", $"loop error: {ex.Message}");
                }
            }
        }

        private void BroadcastIam()
        {
            try
            {
                var beacon = new DiscoveryBeacon
                {
                    Type = "iam",
                    Id = _deviceIds.DeviceId,
                    Alias = _deviceIds.Alias,
                    Port = Constants.DATA_PORT,
                    Proto = Constants.PROTOCOL_VERSION,
                    Ts = DateTimeOffset.UtcNow.ToUnixTimeSeconds()
                };
                var bytes = JsonSerializer.SerializeToUtf8Bytes(beacon);
                // 局域网广播
                _socket!.Send(bytes, bytes.Length, new IPEndPoint(IPAddress.Broadcast, Constants.DISCOVERY_PORT));
                // 调试时也发到几个常见子网
                foreach (var ip in GetLocalSubnetBroadcasts())
                {
                    try
                    {
                        _socket!.Send(bytes, bytes.Length, new IPEndPoint(ip, Constants.DISCOVERY_PORT));
                    }
                    catch { }
                }
            }
            catch (Exception ex)
            {
                Logger.Warn("Discovery", $"broadcast failed: {ex.Message}");
            }
        }

        private void HandlePacket(byte[] buffer, IPEndPoint remote)
        {
            try
            {
                var beacon = JsonSerializer.Deserialize<DiscoveryBeacon>(buffer);
                if (beacon == null) return;
                if (beacon.Proto != Constants.PROTOCOL_VERSION) return;

                if (beacon.Type == "whoami")
                {
                    // 收到手机端查询，立刻回复 iam
                    BroadcastIam();
                    Logger.Info("Discovery", $"whoami from {remote}, replied with iam");
                }
            }
            catch { }
        }

        private static System.Collections.Generic.IEnumerable<IPAddress> GetLocalSubnetBroadcasts()
        {
            var result = new System.Collections.Generic.List<IPAddress>();
            try
            {
                foreach (var iface in NetworkInterface.GetAllNetworkInterfaces())
                {
                    if (iface.OperationalStatus != OperationalStatus.Up) continue;
                    if (iface.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;
                    if (iface.NetworkInterfaceType == NetworkInterfaceType.Tunnel) continue;
                    var desc = iface.Description ?? string.Empty;
                    var name = iface.Name ?? string.Empty;
                    if (desc.Contains("Hyper-V", StringComparison.OrdinalIgnoreCase)) continue;
                    if (desc.Contains("Virtual", StringComparison.OrdinalIgnoreCase)) continue;
                    if (desc.Contains("VMware", StringComparison.OrdinalIgnoreCase)) continue;
                    if (desc.Contains("VirtualBox", StringComparison.OrdinalIgnoreCase)) continue;
                    if (desc.Contains("WSL", StringComparison.OrdinalIgnoreCase)) continue;
                    if (desc.Contains("Docker", StringComparison.OrdinalIgnoreCase)) continue;
                    if (desc.Contains("Tailscale", StringComparison.OrdinalIgnoreCase)) continue;
                    if (desc.Contains("WireGuard", StringComparison.OrdinalIgnoreCase)) continue;
                    if (desc.Contains("VPN", StringComparison.OrdinalIgnoreCase)) continue;
                    if (name.StartsWith("vEthernet", StringComparison.OrdinalIgnoreCase)) continue;

                    foreach (var addr in iface.GetIPProperties().UnicastAddresses)
                    {
                        if (addr.Address.AddressFamily != AddressFamily.InterNetwork) continue;
                        var ip = addr.Address.GetAddressBytes();
                        var mask = addr.IPv4Mask?.GetAddressBytes();
                        if (mask == null) continue;

                        var bcast = new byte[4];
                        for (int i = 0; i < 4; i++)
                        {
                            bcast[i] = (byte)(ip[i] | ~mask[i]);
                        }
                        result.Add(new IPAddress(bcast));
                    }
                }
            }
            catch { }
            return result;
        }

        public void Dispose()
        {
            Stop();
            _socket?.Dispose();
        }
    }
}
