using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading.Tasks;
using System.Windows;

namespace FlowDesk.Common
{
    public static class Constants
    {
        public const int DISCOVERY_PORT = 47800;
        public const int DATA_PORT = 47801;
        public const string PROTOCOL_VERSION = "flowdesk-v1";
        public const int PIN_REFRESH_SECONDS = 30;
        public const int PAIRING_TIMEOUT_MS = 60000;
        public const int HEARTBEAT_INTERVAL_MS = 3000;
        public const int HEARTBEAT_TIMEOUT_MS = 10000;
        public const int SCREEN_FRAME_INTERVAL_MS = 16; // ~60fps
        public const int JPEG_QUALITY = 50;
        public const int SCREEN_TARGET_WIDTH = 1280;

        // 字符集：去掉易混淆字符 0/O/1/I
        private static readonly char[] DEVICE_ID_CHARSET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".ToCharArray();
        private static readonly Random _rng = new Random();

        public static string GenerateDeviceId()
        {
            var sb = new StringBuilder(14);
            for (int g = 0; g < 3; g++)
            {
                if (g > 0) sb.Append('-');
                for (int i = 0; i < 4; i++)
                {
                    sb.Append(DEVICE_ID_CHARSET[_rng.Next(DEVICE_ID_CHARSET.Length)]);
                }
            }
            return sb.ToString();
        }

        public static string GeneratePin()
        {
            return _rng.Next(0, 1000000).ToString("D6");
        }

        public static bool IsValidDeviceId(string id)
        {
            if (string.IsNullOrEmpty(id)) return false;
            return System.Text.RegularExpressions.Regex.IsMatch(id, "^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$");
        }
    }

    public static class Logger
    {
        private static readonly object _logLock = new object();
        private static string? _logFilePath;

        private static string LogFile
        {
            get
            {
                if (_logFilePath == null)
                {
                    var dir = Path.Combine(
                        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                        "FlowDesk", "logs");
                    Directory.CreateDirectory(dir);
                    _logFilePath = Path.Combine(dir, $"flowdesk-{DateTime.Now:yyyyMMdd}.log");
                }
                return _logFilePath;
            }
        }

        private static void WriteLine(string level, string tag, string message, Exception? ex)
        {
            var line = $"[{DateTime.Now:HH:mm:ss.fff}][{level}/{tag}] {message}{(ex != null ? " : " + ex : string.Empty)}";
            Debug.WriteLine(line);
            Console.WriteLine(line);
            try
            {
                lock (_logLock)
                {
                    File.AppendAllText(LogFile, line + Environment.NewLine);
                }
            }
            catch { }
        }

        public static void Info(string tag, string message)
        {
            WriteLine("I", tag, message, null);
        }

        public static void Warn(string tag, string message)
        {
            WriteLine("W", tag, message, null);
        }

        public static void Error(string tag, string message, Exception? ex = null)
        {
            WriteLine("E", tag, message, ex);
        }
    }

    // Win32 API 常量
    public static class Win32
    {
        public const int MOUSEEVENTF_MOVE = 0x0001;
        public const int MOUSEEVENTF_LEFTDOWN = 0x0002;
        public const int MOUSEEVENTF_LEFTUP = 0x0004;
        public const int MOUSEEVENTF_RIGHTDOWN = 0x0008;
        public const int MOUSEEVENTF_RIGHTUP = 0x0010;
        public const int MOUSEEVENTF_MIDDLEDOWN = 0x0020;
        public const int MOUSEEVENTF_MIDDLEUP = 0x0040;
        public const int MOUSEEVENTF_WHEEL = 0x0800;
        public const int MOUSEEVENTF_ABSOLUTE = 0x8000;

        public const uint KEYEVENTF_KEYDOWN = 0x0000u;
        public const uint KEYEVENTF_KEYUP = 0x0002u;

        [DllImport("user32.dll")]
        public static extern bool SetCursorPos(int X, int Y);

        [DllImport("user32.dll")]
        public static extern void mouse_event(int dwFlags, int dx, int dy, int dwData, int dwExtraInfo);

        [DllImport("user32.dll")]
        public static extern void keybd_event(byte bVk, byte bScan, int dwFlags, int dwExtraInfo);

        [StructLayout(LayoutKind.Sequential)]
        public struct INPUT
        {
            public uint type;
            public INPUTUNION union;
        }

        [StructLayout(LayoutKind.Explicit)]
        public struct INPUTUNION
        {
            [FieldOffset(0)] public MOUSEINPUT mi;
            [FieldOffset(0)] public KEYBDINPUT ki;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct MOUSEINPUT
        {
            public int dx;
            public int dy;
            public uint mouseData;
            public uint dwFlags;
            public uint time;
            public IntPtr dwExtraInfo;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct KEYBDINPUT
        {
            public ushort wVk;
            public ushort wScan;
            public uint dwFlags;
            public uint time;
            public IntPtr dwExtraInfo;
        }

        [DllImport("user32.dll", SetLastError = true)]
        public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

        [StructLayout(LayoutKind.Sequential)]
        public struct POINT
        {
            public int X;
            public int Y;
        }

        [DllImport("user32.dll")]
        public static extern bool GetCursorPos(out POINT lpPoint);

        [DllImport("user32.dll")]
        public static extern IntPtr WindowFromPoint(POINT p);

        [DllImport("user32.dll")]
        public static extern IntPtr GetAncestor(IntPtr hwnd, uint gaFlags);

        public const uint GA_ROOT = 2;

        [DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(IntPtr hwnd);

        public static readonly IntPtr HWND_TOP = new IntPtr(0);

        public const uint SWP_NOSIZE = 0x0001;
        public const uint SWP_NOMOVE = 0x0002;
        public const uint SWP_NOACTIVATE = 0x0010;
        public const uint SWP_SHOWWINDOW = 0x0040;

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool BringWindowToTop(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

        [DllImport("kernel32.dll")]
        public static extern uint GetCurrentThreadId();

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);

        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        public static extern IntPtr GetFocus();

        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

        public const uint WM_KEYDOWN = 0x0100;
        public const uint WM_KEYUP = 0x0101;
        public const uint WM_CHAR = 0x0102;

        // ---- 剪贴板 ----
        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool OpenClipboard(IntPtr hWndNewOwner);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool CloseClipboard();

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool EmptyClipboard();

        [DllImport("user32.dll")]
        public static extern IntPtr SetClipboardData(uint uFormat, IntPtr hMem);

        public const uint CF_UNICODETEXT = 13;

        [DllImport("kernel32.dll")]
        public static extern IntPtr GlobalAlloc(uint uFlags, UIntPtr dwBytes);

        public const uint GMEM_MOVEABLE = 0x0002;

        [DllImport("kernel32.dll")]
        public static extern IntPtr GlobalLock(IntPtr hMem);

        [DllImport("kernel32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool GlobalUnlock(IntPtr hMem);

        [DllImport("kernel32.dll")]
        public static extern IntPtr GlobalFree(IntPtr hMem);
    }
}
