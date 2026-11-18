using System.Runtime.InteropServices;

namespace GamePerfCenter.Helpers;

/// <summary>
/// 系统高对比度检测。WinRT 的 AccessibilitySettings 在部分非打包环境里构造失败，
/// 这里直接读 Win32 的 HIGHCONTRAST 标志，不依赖 WinRT 激活。
/// </summary>
public static class HighContrast
{
    private const uint SpiGetHighContrast = 0x0042;
    private const int HcfHighContrastOn = 0x0001;

    [StructLayout(LayoutKind.Sequential)]
    private struct HighContrastData
    {
        public int cbSize;
        public int dwFlags;
        public IntPtr lpszDefaultScheme;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SystemParametersInfo(
        uint action, uint param, ref HighContrastData data, uint winIni);

    public static bool IsEnabled
    {
        get
        {
            try
            {
                var data = new HighContrastData { cbSize = Marshal.SizeOf<HighContrastData>() };
                return SystemParametersInfo(SpiGetHighContrast, (uint)data.cbSize, ref data, 0) &&
                       (data.dwFlags & HcfHighContrastOn) != 0;
            }
            catch { return false; }
        }
    }
}