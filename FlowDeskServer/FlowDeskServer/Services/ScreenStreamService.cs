using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using FlowDesk.Common;
using FlowDesk.Models;

namespace FlowDesk.Services
{
    /// <summary>
    /// 屏幕采集 + JPEG 编码 + UDP 发送
    /// MVP: 使用 GDI CopyFromScreen，15fps JPEG 单帧流
    /// V1.5 升级到 DXGI + H.264 硬编
    /// </summary>
    public class ScreenStreamService : IDisposable
    {
        private readonly PairingService _pairing;
        private readonly object _lock = new object();
        private CancellationTokenSource? _cts;
        private Task? _loopTask;
        private long _frameSeq = 0;
        private Rectangle _captureBounds;
        private int _targetWidth = Constants.SCREEN_TARGET_WIDTH;
        private int _targetHeight = 540;

        public bool IsStreaming => _loopTask != null && !_loopTask.IsCompleted;

        public ScreenStreamService(PairingService pairing)
        {
            _pairing = pairing;
        }

        public void Start()
        {
            UpdateBounds();
            _cts = new CancellationTokenSource();
            _loopTask = Task.Run(() => LoopAsync(_cts.Token));
            Logger.Info("Screen", $"started, bounds={_captureBounds}");
        }

        public void Stop()
        {
            try { _cts?.Cancel(); } catch { }
            _loopTask?.Wait(2000);
            _loopTask = null;
            Logger.Info("Screen", "stopped");
        }

        private void UpdateBounds()
        {
            _captureBounds = System.Windows.Forms.SystemInformation.VirtualScreen;
            // 缩放到目标宽，保持纵横比
            if (_captureBounds.Width > Constants.SCREEN_TARGET_WIDTH)
            {
                _targetWidth = Constants.SCREEN_TARGET_WIDTH;
                _targetHeight = (int)(_captureBounds.Height * ((double)Constants.SCREEN_TARGET_WIDTH / _captureBounds.Width));
                if (_targetHeight % 2 != 0) _targetHeight++;
            }
            else
            {
                _targetWidth = _captureBounds.Width;
                _targetHeight = _captureBounds.Height;
            }
        }

        private async Task LoopAsync(CancellationToken ct)
        {
            while (!ct.IsCancellationRequested)
            {
                try
                {
                    if (_pairing.IsPaired)
                    {
                        CaptureAndSend();
                    }
                    await Task.Delay(Constants.SCREEN_FRAME_INTERVAL_MS, ct);
                }
                catch (OperationCanceledException) { break; }
                catch (Exception ex)
                {
                    Logger.Warn("Screen", $"loop error: {ex.Message}");
                    await Task.Delay(1000, ct);
                }
            }
        }

        private void CaptureAndSend()
        {
            try
            {
                UpdateBounds();
                int screenW = _captureBounds.Width;
                int screenH = _captureBounds.Height;
                if (screenW <= 0 || screenH <= 0) return;

                using var bmp = new Bitmap(screenW, screenH, PixelFormat.Format24bppRgb);
                using (var g = Graphics.FromImage(bmp))
                {
                    g.CopyFromScreen(_captureBounds.X, _captureBounds.Y, 0, 0, new Size(screenW, screenH));
                }

                Bitmap toEncode = bmp;
                System.Drawing.Image? toDispose = null;
                if (screenW != _targetWidth || screenH != _targetHeight)
                {
                    var scaled = new Bitmap(_targetWidth, _targetHeight, PixelFormat.Format24bppRgb);
                    using (var sg = Graphics.FromImage(scaled))
                    {
                        sg.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
                        sg.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.HighQuality;
                        sg.PixelOffsetMode = System.Drawing.Drawing2D.PixelOffsetMode.HighQuality;
                        sg.DrawImage(bmp, 0, 0, _targetWidth, _targetHeight);
                    }
                    toEncode = scaled;
                    toDispose = scaled;
                }

                try
                {
                    using var ms = new MemoryStream();
                    var jpegCodec = GetEncoderInfo("image/jpeg")!;
                    var encoderParams = new EncoderParameters(1);
                    encoderParams.Param[0] = new EncoderParameter(Encoder.Quality, (long)Constants.JPEG_QUALITY);
                    toEncode.Save(ms, jpegCodec, encoderParams);
                    var jpegBytes = ms.ToArray();

                    _pairing.SendFrame(jpegBytes, ++_frameSeq);
                }
                finally
                {
                    toDispose?.Dispose();
                }
            }
            catch (Exception ex)
            {
                Logger.Warn("Screen", $"capture failed: {ex.Message}");
            }
        }

        private static ImageCodecInfo? GetEncoderInfo(string mimeType)
        {
            var codecs = ImageCodecInfo.GetImageEncoders();
            foreach (var c in codecs)
            {
                if (c.MimeType == mimeType) return c;
            }
            return null;
        }

        public void Dispose()
        {
            Stop();
        }
    }
}
