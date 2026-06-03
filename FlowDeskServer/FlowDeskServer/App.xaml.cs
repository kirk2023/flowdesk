using System;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using FlowDesk.Services;

namespace FlowDesk;

public partial class App : Application
{
    public static DeviceIdService DeviceIds { get; private set; } = null!;
    public static PinService Pins { get; private set; } = null!;
    public static DiscoveryService Discovery { get; private set; } = null!;
    public static PairingService Pairing { get; private set; } = null!;
    public static ScreenStreamService Screen { get; private set; } = null!;
    public static InputInjectionService Input { get; private set; } = null!;
    public static FirewallService Firewall { get; private set; } = null!;

    private static Mutex? _singleInstanceMutex;

    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        _singleInstanceMutex = new Mutex(true, "Global\\FlowDeskServer_SingleInstance", out var createdNew);
        if (!createdNew)
        {
            MessageBox.Show("FlowDesk 已在运行", "FlowDesk", MessageBoxButton.OK, MessageBoxImage.Information);
            Shutdown();
            return;
        }

        try
        {
            await InitializeServicesAsync();
        }
        catch (Exception ex)
        {
            MessageBox.Show($"启动失败: {ex.Message}", "FlowDesk", MessageBoxButton.OK, MessageBoxImage.Error);
            Shutdown();
        }
    }

    private static async Task InitializeServicesAsync()
    {
        DeviceIds = new DeviceIdService();
        await DeviceIds.InitializeAsync();

        Pins = new PinService();
        await Pins.InitializeAsync();

        Firewall = new FirewallService();

        Discovery = new DiscoveryService(DeviceIds);
        await Discovery.StartAsync();

        Input = new InputInjectionService();

        Pairing = new PairingService(DeviceIds, Pins, Input);
        await Pairing.StartAsync();

        Screen = new ScreenStreamService(Pairing);
        Screen.Start();
    }

    protected override async void OnExit(ExitEventArgs e)
    {
        try
        {
            Screen?.Stop();
            await Pairing?.StopAsync();
            Discovery?.Stop();
        }
        catch { }
        finally
        {
            _singleInstanceMutex?.ReleaseMutex();
            _singleInstanceMutex?.Dispose();
        }
        base.OnExit(e);
    }
}
