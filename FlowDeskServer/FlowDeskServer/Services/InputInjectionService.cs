using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;
using FlowDesk.Common;
using FlowDesk.Models;

namespace FlowDesk.Services
{
    /// <summary>
    /// 输入注入：把从手机端收到的鼠标/键盘事件转换成 Win32 SendInput 调用
    /// </summary>
    public class InputInjectionService
    {
        private double _lastClickX = 0;
        private double _lastClickY = 0;
        private bool _hasLastClick = false;

        public void HandleMouseMove(double x, double y)
        {
            Win32.SetCursorPos((int)x, (int)y);
        }

        public void HandleMouseDown(string button)
        {
            BringWindowAtCursorToFront();
            SendMouseButton(button, down: true);
        }

        public void HandleMouseDown(string button, double x, double y)
        {
            Win32.SetCursorPos((int)x, (int)y);
            _lastClickX = x;
            _lastClickY = y;
            _hasLastClick = true;
            BringWindowAtCursorToFront();
            // 借前台线程输入权限
            var fg = Win32.GetForegroundWindow();
            bool attached = false;
            uint ourThread = Win32.GetCurrentThreadId();
            uint fgThread = fg != IntPtr.Zero ? Win32.GetWindowThreadProcessId(fg, out _) : 0;
            if (fg != IntPtr.Zero && fgThread != 0 && ourThread != fgThread)
            {
                attached = Win32.AttachThreadInput(ourThread, fgThread, true);
            }
            try
            {
                SendMouseButton(button, down: true);
            }
            finally
            {
                if (attached) Win32.AttachThreadInput(ourThread, fgThread, false);
            }
        }

        public void HandleMouseUp(string button)
        {
            SendMouseButton(button, down: false);
        }

        public void HandleMouseUp(string button, double x, double y)
        {
            Win32.SetCursorPos((int)x, (int)y);
            _lastClickX = x;
            _lastClickY = y;
            _hasLastClick = true;
            SendMouseButton(button, down: false);
        }

        private static void SendMouseButton(string button, bool down)
        {
            var flag = (button, down) switch
            {
                ("left", true) => Win32.MOUSEEVENTF_LEFTDOWN,
                ("left", false) => Win32.MOUSEEVENTF_LEFTUP,
                ("right", true) => Win32.MOUSEEVENTF_RIGHTDOWN,
                ("right", false) => Win32.MOUSEEVENTF_RIGHTUP,
                ("middle", true) => Win32.MOUSEEVENTF_MIDDLEDOWN,
                ("middle", false) => Win32.MOUSEEVENTF_MIDDLEUP,
                (_, true) => Win32.MOUSEEVENTF_LEFTDOWN,
                (_, false) => Win32.MOUSEEVENTF_LEFTUP
            };
            Win32.mouse_event(flag, 0, 0, 0, 0);
        }

        public void HandleMouseWheel(int dx, int dy)
        {
            // 垂直滚动
            if (dy != 0)
            {
                Win32.mouse_event(Win32.MOUSEEVENTF_WHEEL, 0, 0, dy * 120, 0);
            }
            // 水平滚动（一些应用不支持）
            // if (dx != 0)
            // {
            //     Win32.mouse_event(Win32.MOUSEEVENTF_HWHEEL, 0, 0, dx * 120, 0);
            // }
        }

        public void HandleKeyDown(int code, int modifiers)
        {
            if (code <= 0) return;
            // 每次按键前把光标移回上次点击位置,确保前台窗口是用户选中的那个
            if (_hasLastClick)
            {
                Win32.SetCursorPos((int)_lastClickX, (int)_lastClickY);
                BringWindowAtCursorToFront();
            }
            // 借前台线程的输入权限
            var fg = Win32.GetForegroundWindow();
            bool attached = false;
            uint ourThread = Win32.GetCurrentThreadId();
            uint fgThread = fg != IntPtr.Zero ? Win32.GetWindowThreadProcessId(fg, out _) : 0;
            if (fg != IntPtr.Zero && fgThread != 0 && ourThread != fgThread)
            {
                attached = Win32.AttachThreadInput(ourThread, fgThread, true);
            }
            try
            {
                // 拿到真正的聚焦控件 HWND
                IntPtr focus = Win32.GetFocus();
                if (focus == IntPtr.Zero) focus = fg;
                if (focus != IntPtr.Zero)
                {
                    // 可打印字符:用 WM_CHAR,绕开 SendInput 权限
                    if (IsPrintableVk((ushort)code, modifiers))
                    {
                        char ch = VkToChar((ushort)code, modifiers);
                        if (ch != '\0')
                        {
                            // 有 Shift 时也要发 Shift down/up
                            if ((modifiers & 1) != 0) Win32.PostMessage(focus, Win32.WM_KEYDOWN, (IntPtr)0x10, IntPtr.Zero);
                            Win32.PostMessage(focus, Win32.WM_CHAR, (IntPtr)ch, IntPtr.Zero);
                            if ((modifiers & 1) != 0) Win32.PostMessage(focus, Win32.WM_KEYUP, (IntPtr)0x10, IntPtr.Zero);
                            return;
                        }
                    }
                    // 特殊键:WM_KEYDOWN
                    Win32.PostMessage(focus, Win32.WM_KEYDOWN, (IntPtr)(uint)code, IntPtr.Zero);
                    return;
                }
                // 拿不到 focus 控件才退回 SendInput
                ApplyModifiers(modifiers, down: true);
                SendKeyboard((ushort)code, keyUp: false);
            }
            finally
            {
                if (attached) Win32.AttachThreadInput(ourThread, fgThread, false);
            }
        }

        public void HandleKeyUp(int code, int modifiers)
        {
            if (code <= 0) return;
            // 配对的 KEYUP 也要发,否则某些应用会以为键还按着
            var fg = Win32.GetForegroundWindow();
            bool attached = false;
            uint ourThread = Win32.GetCurrentThreadId();
            uint fgThread = fg != IntPtr.Zero ? Win32.GetWindowThreadProcessId(fg, out _) : 0;
            if (fg != IntPtr.Zero && fgThread != 0 && ourThread != fgThread)
            {
                attached = Win32.AttachThreadInput(ourThread, fgThread, true);
            }
            try
            {
                IntPtr focus = Win32.GetFocus();
                if (focus == IntPtr.Zero) focus = fg;
                if (focus != IntPtr.Zero)
                {
                    if (IsPrintableVk((ushort)code, modifiers))
                    {
                        // WM_CHAR 不用配 KEYUP
                        return;
                    }
                    Win32.PostMessage(focus, Win32.WM_KEYUP, (IntPtr)(uint)code, IntPtr.Zero);
                    return;
                }
                SendKeyboard((ushort)code, keyUp: true);
                ApplyModifiers(modifiers, down: false);
            }
            finally
            {
                if (attached) Win32.AttachThreadInput(ourThread, fgThread, false);
            }
        }

        private static bool IsPrintableVk(ushort vk, int modifiers)
        {
            // 字母 / 数字 / 空格 / 常用符号
            if (vk >= 0x30 && vk <= 0x39) return true;
            if (vk >= 0x41 && vk <= 0x5A) return true;
            if (vk == 0x20) return true;
            if (vk == 0xBD || vk == 0xBB || vk == 0xDC || vk == 0xDD || vk == 0xBA || vk == 0xDE || vk == 0xBC || vk == 0xBE || vk == 0xBF) return true;
            if (vk == 0xC0) return true; // `
            return false;
        }

        private static char VkToChar(ushort vk, int modifiers)
        {
            bool shift = (modifiers & 1) != 0;
            if (vk >= 0x30 && vk <= 0x39)
            {
                if (!shift) return (char)vk;
                char[] s = { ')', '!', '@', '#', '$', '%', '^', '&', '*', '(' };
                return s[vk - 0x30];
            }
            if (vk >= 0x41 && vk <= 0x5A)
            {
                return shift ? (char)vk : (char)(vk + 0x20);
            }
            if (vk == 0x20) return ' ';
            if (vk == 0xBD) return shift ? '_' : '-';
            if (vk == 0xBB) return shift ? '+' : '=';
            if (vk == 0xDC) return shift ? '|' : '\\';
            if (vk == 0xDD) return shift ? '}' : ']';
            if (vk == 0xBA) return shift ? ':' : ';';
            if (vk == 0xDE) return shift ? '"' : '\'';
            if (vk == 0xBC) return shift ? '<' : ',';
            if (vk == 0xBE) return shift ? '>' : '.';
            if (vk == 0xBF) return shift ? '?' : '/';
            if (vk == 0xC0) return shift ? '~' : '`';
            return '\0';
        }

        public void HandlePasteText(string text)
        {
            if (string.IsNullOrEmpty(text)) return;
            // 先把光标移回上次点击位置,确保前台是用户选中的窗口
            if (_hasLastClick)
            {
                Win32.SetCursorPos((int)_lastClickX, (int)_lastClickY);
                BringWindowAtCursorToFront();
            }
            // 写剪贴板
            if (!SetClipboardText(text))
            {
                Logger.Warn("Input", $"set clipboard failed");
                return;
            }
            // 发 Ctrl+V
            SendCtrlV();
            Logger.Info("Input", $"paste-text len={text.Length}");
        }

        private static bool SetClipboardText(string text)
        {
            if (!Win32.OpenClipboard(IntPtr.Zero))
            {
                return false;
            }
            try
            {
                Win32.EmptyClipboard();
                // UTF-16 LE + null terminator
                var bytes = System.Text.Encoding.Unicode.GetBytes(text);
                var size = (UIntPtr)(bytes.Length + 2);
                var hGlobal = Win32.GlobalAlloc(Win32.GMEM_MOVEABLE, size);
                if (hGlobal == IntPtr.Zero) return false;
                var target = Win32.GlobalLock(hGlobal);
                if (target == IntPtr.Zero)
                {
                    Win32.GlobalFree(hGlobal);
                    return false;
                }
                try
                {
                    System.Runtime.InteropServices.Marshal.Copy(bytes, 0, target, bytes.Length);
                    System.Runtime.InteropServices.Marshal.WriteInt16(target, bytes.Length, 0);
                }
                finally
                {
                    Win32.GlobalUnlock(hGlobal);
                }
                var res = Win32.SetClipboardData(Win32.CF_UNICODETEXT, hGlobal);
                if (res == IntPtr.Zero)
                {
                    Win32.GlobalFree(hGlobal);
                    return false;
                }
                return true;
            }
            finally
            {
                Win32.CloseClipboard();
            }
        }

        private static void SendCtrlV()
        {
            SendKeyboard(0x11, keyUp: false); // VK_CONTROL down
            SendKeyboard(0x56, keyUp: false); // 'V' down
            Thread.Sleep(15);
            SendKeyboard(0x56, keyUp: true);  // 'V' up
            SendKeyboard(0x11, keyUp: true);  // VK_CONTROL up
        }

        private static void SendKeyboard(ushort vk, bool keyUp)
        {
            var input = new Win32.INPUT
            {
                type = 1, // INPUT_KEYBOARD
                union = new Win32.INPUTUNION
                {
                    ki = new Win32.KEYBDINPUT
                    {
                        wVk = vk,
                        wScan = 0,
                        dwFlags = keyUp ? Win32.KEYEVENTF_KEYUP : Win32.KEYEVENTF_KEYDOWN,
                        time = 0,
                        dwExtraInfo = IntPtr.Zero
                    }
                }
            };
            Win32.SendInput(1, new[] { input }, System.Runtime.InteropServices.Marshal.SizeOf<Win32.INPUT>());
            if (!keyUp)
            {
                // KEYDOWN 和 KEYUP 之间留 5ms 间隔,避免某些应用识别不到
                Thread.Sleep(5);
            }
        }

        private static void BringWindowAtCursorToFront()
        {
            try
            {
                if (!Win32.GetCursorPos(out var pt)) return;
                var hwnd = Win32.WindowFromPoint(pt);
                if (hwnd == IntPtr.Zero) return;
                var top = Win32.GetAncestor(hwnd, Win32.GA_ROOT);
                if (top == IntPtr.Zero) top = hwnd;

                // 先尝试 SetForegroundWindow（仅当我们是前台进程时才有效）
                var fgOk = Win32.SetForegroundWindow(top);

                // 用 SetWindowPos 把窗口带到 Z 序顶部
                Win32.SetWindowPos(top, Win32.HWND_TOP, 0, 0, 0, 0,
                    Win32.SWP_NOMOVE | Win32.SWP_NOSIZE | Win32.SWP_NOACTIVATE | Win32.SWP_SHOWWINDOW);

                // 再 BringWindowToTop
                Win32.BringWindowToTop(top);

                if (!fgOk)
                {
                    // 用 AttachThreadInput 解锁前台锁
                    var fgThread = Win32.GetWindowThreadProcessId(Win32.GetForegroundWindow(), out _);
                    var ourThread = Win32.GetCurrentThreadId();
                    if (fgThread != 0 && ourThread != 0)
                    {
                        if (Win32.AttachThreadInput(ourThread, fgThread, true))
                        {
                            Win32.SetForegroundWindow(top);
                            Win32.SetWindowPos(top, Win32.HWND_TOP, 0, 0, 0, 0,
                                Win32.SWP_NOMOVE | Win32.SWP_NOSIZE | Win32.SWP_SHOWWINDOW);
                            Win32.AttachThreadInput(ourThread, fgThread, false);
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                Logger.Warn("Input", $"bring-to-front failed: {ex.Message}");
            }
        }

        private static void ApplyModifiers(int modifiers, bool down)
        {
            if ((modifiers & ModifierMask.SHIFT) != 0) SendKeyboard(0x10, down); // VK_SHIFT
            if ((modifiers & ModifierMask.CTRL) != 0) SendKeyboard(0x11, down);  // VK_CONTROL
            if ((modifiers & ModifierMask.ALT) != 0) SendKeyboard(0x12, down);   // VK_MENU
            if ((modifiers & ModifierMask.META) != 0) SendKeyboard(0x5B, down);  // VK_LWIN
        }
    }
}
