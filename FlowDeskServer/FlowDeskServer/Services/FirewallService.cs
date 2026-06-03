using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using FlowDesk.Common;
using FlowDesk.Models;

namespace FlowDesk.Services
{
    /// <summary>
    /// 防火墙放行：首次启动时自动添加 udp 47800/47801 入站规则
    /// </summary>
    public class FirewallService
    {
        public void EnsureRules()
        {
            try
            {
                var exe = System.Diagnostics.Process.GetCurrentProcess().MainModule?.FileName
                          ?? AppContext.BaseDirectory;
                var rules = new[]
                {
                    ("FlowDesk Discovery (UDP 47800)", "udp", "47800"),
                    ("FlowDesk Data (UDP 47801)", "udp", "47801")
                };

                foreach (var (name, protocol, port) in rules)
                {
                    var args = $"advfirewall firewall delete rule name=\"{name}\"";
                    RunNetSh(args, suppressError: true);

                    args = $"advfirewall firewall add rule name=\"{name}\" " +
                           $"dir=in action=allow protocol={protocol} localport={port} " +
                           $"program=\"{exe}\" enable=yes profile=any";
                    var ok = RunNetSh(args, suppressError: false);
                    Logger.Info("Firewall", $"rule '{name}' {(ok ? "added" : "FAILED")}");
                }
            }
            catch (Exception ex)
            {
                Logger.Warn("Firewall", $"ensure rules failed: {ex.Message}");
            }
        }

        private static bool RunNetSh(string args, bool suppressError)
        {
            try
            {
                var psi = new System.Diagnostics.ProcessStartInfo
                {
                    FileName = "netsh",
                    Arguments = args,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    Verb = "runas" // 需要管理员权限
                };
                using var proc = System.Diagnostics.Process.Start(psi);
                proc?.WaitForExit(5000);
                return proc?.ExitCode == 0;
            }
            catch (Exception ex)
            {
                if (!suppressError)
                    Logger.Warn("Firewall", $"netsh failed: {ex.Message}");
                return false;
            }
        }
    }
}
