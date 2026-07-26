$ErrorActionPreference = 'Stop'

$pidPath = Join-Path $PSScriptRoot 'wechat-voice-x2-bridge.pid'
$logPath = Join-Path $PSScriptRoot 'wechat-voice-x2-bridge.log'
$heartbeatPath = Join-Path $PSScriptRoot 'wechat-voice-x2-bridge.heartbeat'
$bridgeVersion = '0.4.0'
$createdNew = $false
$instanceMutex = [System.Threading.Mutex]::new($true, 'Local\WeChatVoiceX2Bridge', [ref]$createdNew)
if (-not $createdNew) {
    Add-Content -LiteralPath $logPath -Value ("{0} Duplicate bridge launch ignored PID={1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $PID) -Encoding UTF8
    $instanceMutex.Dispose()
    exit 0
}
Set-Content -LiteralPath $pidPath -Value $PID -Encoding ASCII
Add-Content -LiteralPath $logPath -Value ("Started {0} PID={1} Version={2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $PID, $bridgeVersion) -Encoding UTF8

Add-Type -TypeDefinition @"
using System;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;

public static class WeChatVoiceX2Bridge
{
    private const int WH_MOUSE_LL = 14;
    private const int WM_XBUTTONDOWN = 0x020B;
    private const int WM_XBUTTONUP = 0x020C;
    private const uint WM_TIMER = 0x0113;
    private const int XBUTTON1 = 1;
    private const int XBUTTON2 = 2;
    private const int VK_XBUTTON2 = 0x06;
    private const ushort VK_CONTROL = 0x11;
    private const ushort VK_MENU = 0x12;
    private const ushort VK_SHIFT = 0x10;
    private const ushort VK_LWIN = 0x5B;
    private const ushort VK_RWIN = 0x5C;
    private const ushort VK_LCONTROL = 0xA2;
    private const ushort VK_LMENU = 0xA4;
    private const ushort VK_O = 0x4F;
    private const ushort SC_CONTROL = 0x1D;
    private const ushort SC_MENU = 0x38;
    private const ushort SC_O = 0x18;
    private const uint INPUT_KEYBOARD = 1;
    private const uint KEYEVENTF_KEYUP = 0x0002;

    private static LowLevelMouseProc _proc = HookCallback;
    private static IntPtr _hookID = IntPtr.Zero;
    private static string _logPath = "";
    private static string _heartbeatPath = "";
    private static int _buttonDown = 0;
    private static readonly ConcurrentQueue<int> _mouseEvents = new ConcurrentQueue<int>();
    private static readonly AutoResetEvent _eventReady = new AutoResetEvent(false);

    public static void Run(string logPath, string heartbeatPath)
    {
        _logPath = logPath;
        _heartbeatPath = heartbeatPath;
        RefreshHook("installed");

        Thread worker = new Thread(ProcessMouseEvents);
        worker.IsBackground = true;
        worker.Name = "WeChatVoiceX2Worker";
        worker.Start();

        Thread poller = new Thread(PollMouseState);
        poller.IsBackground = true;
        poller.Name = "WeChatVoiceX2Poller";
        poller.Start();

        UIntPtr timerId = SetTimer(IntPtr.Zero, UIntPtr.Zero, 60000, IntPtr.Zero);
        Log("Listening for XBUTTON2 with hook + polling fallback.");
        MSG msg;
        while (GetMessage(out msg, IntPtr.Zero, 0, 0) != 0)
        {
            if (msg.message == WM_TIMER)
                RefreshHook("refreshed");
        }
        if (timerId != UIntPtr.Zero)
            KillTimer(IntPtr.Zero, timerId);
        UnhookWindowsHookEx(_hookID);
    }

    private static void RefreshHook(string action)
    {
        if (_hookID != IntPtr.Zero)
            UnhookWindowsHookEx(_hookID);
        _hookID = SetHook(_proc);
        if (_hookID == IntPtr.Zero)
            Log("Hook " + action + " failed; polling fallback remains active. Win32Error=" + Marshal.GetLastWin32Error());
        else
            Log("Hook " + action + " successfully.");
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
                    PublishButtonState(message == WM_XBUTTONDOWN);
                    return (IntPtr)1;
                }
            }
        }
        return CallNextHookEx(_hookID, nCode, wParam, lParam);
    }

    private static void PollMouseState()
    {
        DateTime nextHeartbeat = DateTime.MinValue;
        while (true)
        {
            bool isDown = (GetAsyncKeyState(VK_XBUTTON2) & 0x8000) != 0;
            PublishButtonState(isDown);

            if (DateTime.UtcNow >= nextHeartbeat)
            {
                try { File.WriteAllText(_heartbeatPath, DateTime.UtcNow.ToString("o")); } catch { }
                nextHeartbeat = DateTime.UtcNow.AddSeconds(15);
            }
            Thread.Sleep(10);
        }
    }

    private static void PublishButtonState(bool isDown)
    {
        int next = isDown ? 1 : 0;
        int previous = Interlocked.Exchange(ref _buttonDown, next);
        if (previous == next)
            return;
        _mouseEvents.Enqueue(isDown ? WM_XBUTTONDOWN : WM_XBUTTONUP);
        _eventReady.Set();
    }

    private static void ProcessMouseEvents()
    {
        while (true)
        {
            _eventReady.WaitOne();
            int message;
            while (_mouseEvents.TryDequeue(out message))
            {
                Log("Mouse " + (message == WM_XBUTTONDOWN ? "down" : "up") + " XBUTTON2");
                if (message == WM_XBUTTONUP)
                {
                    Thread.Sleep(80);
                    Log("Sending LeftCtrl+LeftAlt+O.");
                    SendCtrlAltO();
                }
            }
        }
    }

    private static void SendCtrlAltO()
    {
        ReleaseCommonModifiers();
        Thread.Sleep(30);
        INPUT[] inputs = new INPUT[] {
            KeyboardInput(VK_LCONTROL, 0),
            KeyboardInput(VK_LMENU, 0),
            KeyboardInput(VK_O, 0),
            KeyboardInput(VK_O, KEYEVENTF_KEYUP),
            KeyboardInput(VK_LMENU, KEYEVENTF_KEYUP),
            KeyboardInput(VK_LCONTROL, KEYEVENTF_KEYUP)
        };
        uint sent = SendInput((uint)inputs.Length, inputs, Marshal.SizeOf(typeof(INPUT)));
        if (sent == inputs.Length)
            Log("SendInput sent LeftCtrl+LeftAlt+O.");
        else
            Log("SendInput failed: sent " + sent + "/" + inputs.Length + ", Win32Error=" + Marshal.GetLastWin32Error());
    }

    private static void ReleaseCommonModifiers()
    {
        ushort[] keys = new ushort[] { VK_CONTROL, VK_LCONTROL, VK_MENU, VK_LMENU, VK_SHIFT, VK_LWIN, VK_RWIN };
        INPUT[] inputs = new INPUT[keys.Length];
        int index = 0;
        foreach (ushort key in keys)
        {
            inputs[index++] = KeyboardInput(key, KEYEVENTF_KEYUP);
        }
        SendInput((uint)inputs.Length, inputs, Marshal.SizeOf(typeof(INPUT)));
    }

    private static INPUT KeyboardInput(ushort virtualKey, uint flags)
    {
        INPUT input = new INPUT();
        input.type = INPUT_KEYBOARD;
        input.U.ki.wVk = virtualKey;
        input.U.ki.dwFlags = flags;
        return input;
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

    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT
    {
        public uint type;
        public InputUnion U;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion
    {
        [FieldOffset(0)] public MOUSEINPUT mi;
        [FieldOffset(0)] public KEYBDINPUT ki;
        [FieldOffset(0)] public HARDWAREINPUT hi;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MOUSEINPUT
    {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public UIntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT
    {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public UIntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct HARDWAREINPUT
    {
        public uint uMsg;
        public ushort wParamL;
        public ushort wParamH;
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

    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int vKey);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern UIntPtr SetTimer(IntPtr hWnd, UIntPtr nIDEvent, uint uElapse, IntPtr lpTimerFunc);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool KillTimer(IntPtr hWnd, UIntPtr uIDEvent);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);
}
"@

try {
    [WeChatVoiceX2Bridge]::Run($logPath, $heartbeatPath)
}
finally {
    $ownedPid = (Get-Content -LiteralPath $pidPath -Raw -ErrorAction SilentlyContinue).Trim()
    if ($ownedPid -eq [string]$PID) {
        Remove-Item -LiteralPath $pidPath -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $heartbeatPath -ErrorAction SilentlyContinue
    }
    try { $instanceMutex.ReleaseMutex() } catch { }
    $instanceMutex.Dispose()
}
