using System.Runtime.InteropServices;

namespace GamePerfCenter.Services;

/// <summary>
/// 轻量托盘图标：不依赖 WinForms，使用 Win32 消息窗口接收 Shell_NotifyIcon 回调。
/// 仅在“关闭时最小化到托盘”启用时显示。
/// </summary>
internal sealed class TrayIcon : IDisposable
{
    private const int WM_APP = 0x8000;
    private const int WM_TRAY = WM_APP + 20;
    private const int WM_LBUTTONUP = 0x0202;
    private const int WM_LBUTTONDBLCLK = 0x0203;
    private const int WM_RBUTTONUP = 0x0205;
    private const int NIM_ADD = 0;
    private const int NIM_DELETE = 2;
    private const int NIF_MESSAGE = 0x1;
    private const int NIF_ICON = 0x2;
    private const int NIF_TIP = 0x4;
    private const int IMAGE_ICON = 1;
    private const int LR_LOADFROMFILE = 0x10;
    private const int LR_DEFAULTSIZE = 0x40;
    private const int MF_STRING = 0;
    private const int MF_SEPARATOR = 0x800;
    private const int TPM_RETURNCMD = 0x100;
    private const int TPM_RIGHTBUTTON = 0x2;
    private const int WM_NULL = 0;

    private readonly WndProcDelegate _wndProc;
    private readonly string _className = "GamePerfCenterTray_" + Guid.NewGuid().ToString("N");
    private readonly string _iconPath;
    private IntPtr _hwnd;
    private IntPtr _hIcon;
    private bool _visible;

    public Action? OnOpen { get; set; }
    public Action? OnExit { get; set; }

    public TrayIcon(string iconPath)
    {
        _iconPath = iconPath;
        _wndProc = WndProc;
        CreateHostWindow();
        LoadIconFile();
    }

    private void CreateHostWindow()
    {
        var hInstance = GetModuleHandle(null);
        var wc = new WNDCLASSEX
        {
            cbSize = Marshal.SizeOf<WNDCLASSEX>(),
            lpfnWndProc = Marshal.GetFunctionPointerForDelegate(_wndProc),
            hInstance = hInstance,
            lpszClassName = _className
        };
        RegisterClassEx(ref wc);
        _hwnd = CreateWindowEx(0, _className, "GamePerfCenterTray", 0, 0, 0, 0, 0,
            IntPtr.Zero, IntPtr.Zero, hInstance, IntPtr.Zero);
    }

    private void LoadIconFile()
    {
        try
        {
            if (File.Exists(_iconPath))
            {
                var size = GetSystemMetrics(49); // SM_CXSMICON
                _hIcon = LoadImage(IntPtr.Zero, _iconPath, IMAGE_ICON, size, size, LR_LOADFROMFILE);
            }
            if (_hIcon == IntPtr.Zero)
                _hIcon = LoadIcon(IntPtr.Zero, (IntPtr)32512); // IDI_APPLICATION
        }
        catch { }
    }

    public void Show()
    {
        if (_visible || _hwnd == IntPtr.Zero) return;
        var data = new NOTIFYICONDATA
        {
            cbSize = Marshal.SizeOf<NOTIFYICONDATA>(),
            hWnd = _hwnd,
            uID = 1,
            uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP,
            uCallbackMessage = WM_TRAY,
            hIcon = _hIcon,
            szTip = "游戏性能优化中心"
        };
        if (Shell_NotifyIcon(NIM_ADD, ref data)) _visible = true;
    }

    public void Hide()
    {
        if (!_visible || _hwnd == IntPtr.Zero) return;
        var data = new NOTIFYICONDATA
        {
            cbSize = Marshal.SizeOf<NOTIFYICONDATA>(),
            hWnd = _hwnd,
            uID = 1
        };
        Shell_NotifyIcon(NIM_DELETE, ref data);
        _visible = false;
    }

    private IntPtr WndProc(IntPtr hwnd, uint msg, IntPtr wParam, IntPtr lParam)
    {
        if (msg == WM_TRAY)
        {
            var evt = lParam.ToInt32() & 0xFFFF;
            if (evt is WM_LBUTTONUP or WM_LBUTTONDBLCLK)
                OnOpen?.Invoke();
            else if (evt == WM_RBUTTONUP)
                ShowMenu();
            return IntPtr.Zero;
        }
        return DefWindowProc(hwnd, msg, wParam, lParam);
    }

    private void ShowMenu()
    {
        var menu = CreatePopupMenu();
        if (menu == IntPtr.Zero) return;
        try
        {
            AppendMenu(menu, MF_STRING, 1, "打开主界面");
            AppendMenu(menu, MF_SEPARATOR, 0, null);
            AppendMenu(menu, MF_STRING, 2, "退出");
            if (!GetCursorPos(out var pt)) return;
            SetForegroundWindow(_hwnd);
            var cmd = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON, pt.X, pt.Y, 0, _hwnd, IntPtr.Zero);
            PostMessage(_hwnd, WM_NULL, IntPtr.Zero, IntPtr.Zero);
            if (cmd == 1) OnOpen?.Invoke();
            else if (cmd == 2) OnExit?.Invoke();
        }
        finally
        {
            DestroyMenu(menu);
        }
    }

    public void Dispose()
    {
        Hide();
        if (_hIcon != IntPtr.Zero)
        {
            DestroyIcon(_hIcon);
            _hIcon = IntPtr.Zero;
        }
        if (_hwnd != IntPtr.Zero)
        {
            DestroyWindow(_hwnd);
            _hwnd = IntPtr.Zero;
        }
    }

    private delegate IntPtr WndProcDelegate(IntPtr hwnd, uint msg, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WNDCLASSEX
    {
        public int cbSize;
        public uint style;
        public IntPtr lpfnWndProc;
        public int cbClsExtra;
        public int cbWndExtra;
        public IntPtr hInstance;
        public IntPtr hIcon;
        public IntPtr hCursor;
        public IntPtr hbrBackground;
        [MarshalAs(UnmanagedType.LPWStr)] public string? lpszMenuName;
        [MarshalAs(UnmanagedType.LPWStr)] public string lpszClassName;
        public IntPtr hIconSm;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct NOTIFYICONDATA
    {
        public int cbSize;
        public IntPtr hWnd;
        public uint uID;
        public uint uFlags;
        public uint uCallbackMessage;
        public IntPtr hIcon;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string szTip;
        public uint dwState;
        public uint dwStateMask;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string szInfo;
        public uint uTimeoutOrVersion;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string szInfoTitle;
        public uint dwInfoFlags;
        public Guid guidItem;
        public IntPtr hBalloonIcon;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT { public int X; public int Y; }

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern ushort RegisterClassEx(ref WNDCLASSEX wc);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateWindowEx(int exStyle, string className, string windowName, int style,
        int x, int y, int width, int height, IntPtr parent, IntPtr menu, IntPtr instance, IntPtr param);

    [DllImport("user32.dll")] private static extern IntPtr DefWindowProc(IntPtr hwnd, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] private static extern bool DestroyWindow(IntPtr hwnd);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr GetModuleHandle(string? name);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern bool Shell_NotifyIcon(int message, ref NOTIFYICONDATA data);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr LoadImage(IntPtr instance, string name, int type, int cx, int cy, int load);

    [DllImport("user32.dll")]
    private static extern IntPtr LoadIcon(IntPtr instance, IntPtr name);

    [DllImport("user32.dll")] private static extern bool DestroyIcon(IntPtr icon);
    [DllImport("user32.dll")] private static extern int GetSystemMetrics(int index);

    [DllImport("user32.dll")] private static extern IntPtr CreatePopupMenu();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern bool AppendMenu(IntPtr menu, int flags, int id, string? text);
    [DllImport("user32.dll")] private static extern bool DestroyMenu(IntPtr menu);
    [DllImport("user32.dll")] private static extern int TrackPopupMenu(IntPtr menu, int flags, int x, int y,
        int reserved, IntPtr hwnd, IntPtr rect);
    [DllImport("user32.dll")] private static extern bool GetCursorPos(out POINT point);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool PostMessage(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam);
}
