using System;
using System.Drawing;
using System.IO;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using FlowDesk.Common;
using FlowDesk.Services;
using Hardcodet.Wpf.TaskbarNotification;
using QRCoder;

namespace FlowDesk
{
    public partial class MainWindow : Window
    {
        private DispatcherTimer? _pinTimer;
        private DispatcherTimer? _clockTimer;
        private bool _realExit = false;

        public MainWindow()
        {
            InitializeComponent();
        }

        private void Window_Loaded(object sender, RoutedEventArgs e)
        {
            try
            {
                // 显示设备 ID
                DeviceIdText.Text = App.DeviceIds.DeviceId;

                // 首次显示 PIN
                UpdatePin();

                // PIN 倒计时刷新
                _pinTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
                _pinTimer.Tick += (_, _) => UpdatePin();
                _pinTimer.Start();

                // 时钟：刷新网络信息 + 二维码（IP 或 PIN 变化时重建）
                _clockTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(5) };
                string lastQrIp = string.Empty;
                string lastQrPin = string.Empty;
                _clockTimer.Tick += async (_, _) =>
                {
                    var ip = GetBestLocalIpv4();
                    var pin = App.Pins.CurrentPin;
                    await UpdateNetworkInfoAsync();
                    if (ip != lastQrIp || pin != lastQrPin)
                    {
                        lastQrIp = ip;
                        lastQrPin = pin;
                        await GenerateQrCodeAsync(ip, pin);
                    }
                };
                _clockTimer.Start();

                var initialIp = GetBestLocalIpv4();
                var initialPin = App.Pins.CurrentPin;
                lastQrIp = initialIp;
                lastQrPin = initialPin;
                _ = UpdateNetworkInfoAsync();
                _ = GenerateQrCodeAsync(initialIp, initialPin);

                // 配置托盘
                SetupTray();

                // 注册配对事件
                App.Pairing.OnPaired += OnDevicePaired;
                App.Pairing.OnDisconnected += OnDeviceDisconnected;

                // 首次启动时尝试配置防火墙
                try
                {
                    App.Firewall.EnsureRules();
                }
                catch (Exception ex)
                {
                    Logger.Warn("MainWindow", $"firewall setup failed (admin required?): {ex.Message}");
                }
            }
            catch (Exception ex)
            {
                Logger.Error("MainWindow", "load failed", ex);
            }
        }

        private void UpdatePin()
        {
            var pin = App.Pins.CurrentPin;
            PinText.Text = string.Join(" ", pin.ToCharArray());
            PinCountdownText.Text = $"{App.Pins.SecondsRemaining}s";
        }

        private async Task UpdateNetworkInfoAsync()
        {
            try
            {
                var ip = GetBestLocalIpv4();
                NetworkInfoText.Text = $"本机 IP: {ip}   ·   端口: {Constants.DATA_PORT}";
            }
            catch (Exception ex)
            {
                NetworkInfoText.Text = $"本机 IP: 获取失败 ({ex.Message})";
            }
            await Task.CompletedTask;
        }

        private static string GetBestLocalIpv4()
        {
            string best = "未知";
            NetworkInterface? bestIface = null;
            System.Net.IPAddress? bestAddr = null;
            int bestScore = -1;

            foreach (var iface in NetworkInterface.GetAllNetworkInterfaces())
            {
                if (iface.OperationalStatus != OperationalStatus.Up) continue;
                if (iface.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;
                if (iface.NetworkInterfaceType == NetworkInterfaceType.Tunnel) continue;
                var desc = iface.Description ?? string.Empty;
                var name = iface.Name ?? string.Empty;
                // 跳过常见虚拟网卡
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

                int score = 0;
                switch (iface.NetworkInterfaceType)
                {
                    case NetworkInterfaceType.Wireless80211: score = 100; break;
                    case NetworkInterfaceType.Ethernet: score = 90; break;
                    case NetworkInterfaceType.GigabitEthernet: score = 90; break;
                    case NetworkInterfaceType.FastEthernetT: score = 80; break;
                    default: score = 10; break;
                }

                var props = iface.GetIPProperties();
                foreach (var addr in props.UnicastAddresses)
                {
                    if (addr.Address.AddressFamily != AddressFamily.InterNetwork) continue;
                    var bytes = addr.Address.GetAddressBytes();
                    if (bytes[0] == 169 && bytes[1] == 254) continue; // APIPA
                    if (bytes[0] == 127) continue; // loopback
                    if (score > bestScore)
                    {
                        bestScore = score;
                        bestIface = iface;
                        bestAddr = addr.Address;
                    }
                }
            }
            if (bestAddr != null) return bestAddr.ToString();
            return best;
        }

        private async Task GenerateQrCodeAsync(string localIp, string pin)
        {
            try
            {
                await Task.Run(() =>
                {
                    // 二维码内容：设备ID + alias + ip + pin（手机扫码后自动配对，无需手动输 PIN）
                    var payload = $"flowdesk://pair?id={App.DeviceIds.DeviceId}&alias={Uri.EscapeDataString(App.DeviceIds.Alias)}&ip={Uri.EscapeDataString(localIp)}&pin={Uri.EscapeDataString(pin)}";
                    using var qrGen = new QRCodeGenerator();
                    using var qrData = qrGen.CreateQrCode(payload, QRCodeGenerator.ECCLevel.M);
                    using var qrCode = new PngByteQRCode(qrData);
                    var pngBytes = qrCode.GetGraphic(8);

                    Dispatcher.Invoke(() =>
                    {
                        var img = new BitmapImage();
                        using var ms = new MemoryStream(pngBytes);
                        img.BeginInit();
                        img.CacheOption = BitmapCacheOption.OnLoad;
                        img.StreamSource = ms;
                        img.EndInit();
                        img.Freeze();
                        QrCodeImage.Source = img;
                    });
                });
            }
            catch (Exception ex)
            {
                Logger.Warn("MainWindow", $"qr code generation failed: {ex.Message}");
            }
        }

        private void CopyIdButton_Click(object sender, RoutedEventArgs e)
        {
            try
            {
                Clipboard.SetText(App.DeviceIds.DeviceId);
                CopyIdButton.Content = "已复制";
                var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2) };
                timer.Tick += (_, _) =>
                {
                    CopyIdButton.Content = "复制";
                    timer.Stop();
                };
                timer.Start();
            }
            catch (Exception ex)
            {
                Logger.Warn("MainWindow", $"clipboard failed: {ex.Message}");
            }
        }

        private void SetupTray()
        {
            Tray.IconSource = new BitmapImage(new Uri("pack://application:,,,/assets/app_icon.ico"));
            var menu = new System.Windows.Controls.ContextMenu();

            var openItem = new System.Windows.Controls.MenuItem { Header = "打开主面板" };
            openItem.Click += (_, _) =>
            {
                Show();
                WindowState = WindowState.Normal;
                Activate();
            };
            menu.Items.Add(openItem);

            menu.Items.Add(new System.Windows.Controls.Separator());

            var exitItem = new System.Windows.Controls.MenuItem { Header = "退出" };
            exitItem.Click += (_, _) =>
            {
                _realExit = true;
                Close();
            };
            menu.Items.Add(exitItem);

            Tray.ContextMenu = menu;
            Tray.Visibility = Visibility.Visible;
        }

        private void Tray_DoubleClick(object sender, RoutedEventArgs e)
        {
            Show();
            WindowState = WindowState.Normal;
            Activate();
        }

        private void OnDevicePaired(string deviceId)
        {
            Dispatcher.Invoke(() =>
            {
                StatusBadge.Visibility = Visibility.Visible;
                StatusText.Text = $"已配对:{deviceId} · 正在传输屏幕";
            });
        }

        private void OnDeviceDisconnected(string deviceId)
        {
            Dispatcher.Invoke(() =>
            {
                StatusBadge.Visibility = Visibility.Collapsed;
                StatusText.Text = "已断开";
            });
        }

        private void OpenLogButton_Click(object sender, RoutedEventArgs e)
        {
            try
            {
                var logDir = System.IO.Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "FlowDesk", "logs");
                if (System.IO.Directory.Exists(logDir))
                {
                    System.Diagnostics.Process.Start("explorer.exe", logDir);
                }
                else
                {
                    System.Windows.MessageBox.Show("日志目录不存在:\n" + logDir);
                }
            }
            catch (Exception ex)
            {
                System.Windows.MessageBox.Show("打开失败: " + ex.Message);
            }
        }

        private void Window_Closing(object sender, System.ComponentModel.CancelEventArgs e)
        {
            if (!_realExit)
            {
                // 最小化到托盘而不是退出
                e.Cancel = true;
                Hide();
                Tray.ShowBalloonTip("FlowDesk", "已最小化到托盘", BalloonIcon.Info);
            }
        }
    }
}
