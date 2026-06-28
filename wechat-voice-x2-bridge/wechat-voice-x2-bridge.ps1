$ErrorActionPreference = 'Stop'

$pidPath = Join-Path $PSScriptRoot 'wechat-voice-x2-bridge.pid'
$logPath = Join-Path $PSScriptRoot 'wechat-voice-x2-bridge.log'
Set-Content -LiteralPath $pidPath -Value $PID -Encoding ASCII
Add-Content -LiteralPath $logPath -Value ("Started {0} PID={1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $PID) -Encoding UTF8

Add-Type -TypeDefinition @"
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;

public static class WeChatVoiceX2Bridge
{
    private const int WH_MOUSE_LL = 14;
    private const int WM_XBUTTONDOWN = 0x020B;
    private const int WM_XBUTTONUP = 0x020C;
    private const int XBUTTON1 = 1;
    private const int XBUTTON2 = 2;
    private const ushort VK_CONTROL = 0x11;
    private const ushort VK_MENU = 0x12;
    private const ushort VK_O = 0x4F;
    private const ushort SC_CONTROL = 0x1D;
    private const ushort SC_MENU = 0x38;
    private const ushort SC_O = 0x18;
    private const uint KEYEVENTF_KEYUP = 0x0002;

    private static LowLevelMouseProc _proc = HookCallback;
    private static IntPtr _hookID = IntPtr.Zero;
    private static string _logPath = "";

    public static void Run(string logPath)
    {
        _logPath = logPath;
        _hookID = SetHook(_proc);
        if (_hookID == IntPtr.Zero)
        {
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        }

        Log("Hook installed. Listening for XBUTTON2.");
        MSG msg;
        while (GetMessage(out msg, IntPtr.Zero, 0, 0) != 0) { }
        UnhookWindowsHookEx(_hookID);
    }

    private static IntPtr SetHook(LowLevelMouseProc proc)
    {
        using (Process curProcess = Process.GetCurrentProcess())
        using (ProcessModule curModule = curProcess.MainModule)
        {
            return SetWindowsHookEx(WH_MOUSE_LL, proc, GetModuleHandle(curModule.ModuleName), 0);
        }
    }

    private delegate IntPtr LowLevelMouseProc(int nCode, IntPtr wParam, IntPtr lParam);

    private static IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            int message = wParam.ToInt32();
            if (message == WM_XBUTTONDOWN || message == WM_XBUTTONUP)
            {
                MSLLHOOKSTRUCT data = (MSLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(MSLLHOOKSTRUCT));
                int xButton = (int)((data.mouseData >> 16) & 0xffff);
                if (xButton == XBUTTON2)
                {
                    Log("Mouse " + (message == WM_XBUTTONDOWN ? "down" : "up") + " XBUTTON" + xButton);
                    if (message == WM_XBUTTONUP)
                    {
                        Thread.Sleep(80);
                        Log("Sending LeftCtrl+LeftAlt+O.");
                        SendCtrlAltO();
                    }
                    return (IntPtr)1;
                }
            }
        }
        return CallNextHookEx(_hookID, nCode, wParam, lParam);
    }

    private static void SendCtrlAltO()
    {
        keybd_event((byte)VK_CONTROL, (byte)SC_CONTROL, 0, UIntPtr.Zero);
        keybd_event((byte)VK_MENU, (byte)SC_MENU, 0, UIntPtr.Zero);
        keybd_event((byte)VK_O, (byte)SC_O, 0, UIntPtr.Zero);
        Thread.Sleep(40);
        keybd_event((byte)VK_O, (byte)SC_O, KEYEVENTF_KEYUP, UIntPtr.Zero);
        keybd_event((byte)VK_MENU, (byte)SC_MENU, KEYEVENTF_KEYUP, UIntPtr.Zero);
        keybd_event((byte)VK_CONTROL, (byte)SC_CONTROL, KEYEVENTF_KEYUP, UIntPtr.Zero);
        Log("keybd_event sent LeftCtrl+LeftAlt+O.");
    }

    private static void Log(string text)
    {
        try
        {
            File.AppendAllText(_logPath, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff ") + text + Environment.NewLine);
        }
        catch { }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT
    {
        public int x;
        public int y;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MSLLHOOKSTRUCT
    {
        public POINT pt;
        public uint mouseData;
        public uint flags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MSG
    {
        public IntPtr hwnd;
        public uint message;
        public IntPtr wParam;
        public IntPtr lParam;
        public uint time;
        public POINT pt;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelMouseProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern IntPtr GetModuleHandle(string lpModuleName);

    [DllImport("user32.dll")]
    private static extern int GetMessage(out MSG lpMsg, IntPtr hWnd, uint wMsgFilterMin, uint wMsgFilterMax);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
}
"@

try {
    [WeChatVoiceX2Bridge]::Run($logPath)
}
finally {
    Remove-Item -LiteralPath $pidPath -ErrorAction SilentlyContinue
}

