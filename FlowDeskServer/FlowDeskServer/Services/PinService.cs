using System;
using System.Threading;
using System.Threading.Tasks;
using FlowDesk.Common;

namespace FlowDesk.Services
{
    /// <summary>
    /// 动态 PIN 服务：每 30 秒刷新一次 6 位数字 PIN，用于首次配对
    /// </summary>
    public class PinService : IDisposable
    {
        public string CurrentPin { get; private set; } = "";
        public DateTimeOffset GeneratedAt { get; private set; }
        public DateTimeOffset ExpiresAt => GeneratedAt.AddSeconds(Constants.PIN_REFRESH_SECONDS);
        public int SecondsRemaining => Math.Max(0, (int)(ExpiresAt - DateTimeOffset.UtcNow).TotalSeconds);
        public bool IsFrozen { get; private set; }

        private Timer? _timer;
        private bool _disposed;

        public Task InitializeAsync()
        {
            Refresh();
            _timer = new Timer(_ => Tick(), null,
                TimeSpan.FromSeconds(Constants.PIN_REFRESH_SECONDS),
                TimeSpan.FromSeconds(Constants.PIN_REFRESH_SECONDS));
            Logger.Info("Pin", $"initial pin generated, refresh every {Constants.PIN_REFRESH_SECONDS}s");
            return Task.CompletedTask;
        }

        private void Tick()
        {
            if (IsFrozen) return;
            Refresh();
        }

        private void Refresh()
        {
            CurrentPin = Constants.GeneratePin();
            GeneratedAt = DateTimeOffset.UtcNow;
            Logger.Info("Pin", $"refreshed: {CurrentPin}");
        }

        public void Freeze()
        {
            IsFrozen = true;
            Logger.Info("Pin", $"frozen at {CurrentPin}");
        }

        public void Unfreeze()
        {
            IsFrozen = false;
            Refresh();
            Logger.Info("Pin", $"unfrozen, new pin: {CurrentPin}");
        }

        public bool Validate(string? pin)
        {
            if (string.IsNullOrEmpty(pin)) return false;
            if (DateTimeOffset.UtcNow > ExpiresAt) return false;
            return string.Equals(pin, CurrentPin, StringComparison.Ordinal);
        }

        public void Dispose()
        {
            if (_disposed) return;
            _timer?.Dispose();
            _timer = null;
            _disposed = true;
        }
    }
}
