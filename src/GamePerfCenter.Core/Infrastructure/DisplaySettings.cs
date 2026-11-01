using System.Runtime.InteropServices;

namespace GamePerfCenter.Core.Infrastructure;

/// <summary>显示器刷新率读写（ChangeDisplaySettingsEx）。</summary>
public static class DisplaySettings
{
    private const int EnumCurrentSettings = -1;
    private const int DmDisplayFrequency = 0x400000;
    private const uint CdsTest = 0x02;
    private const uint CdsUpdateRegistry = 0x01;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct DevMode
    {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string DmDeviceName;
        public short DmSpecVersion;
        public short DmDriverVersion;
        public short DmSize;
        public short DmDriverExtra;
        public int DmFields;
        public int DmPositionX;
        public int DmPositionY;
        public int DmDisplayOrientation;
        public int DmDisplayFixedOutput;
        public short DmColor;
        public short DmDuplex;
        public short DmYResolution;
        public short DmTTOption;
        public short DmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string DmFormName;
        public short DmLogPixels;
        public int DmBitsPerPel;
        public int DmPelsWidth;
        public int DmPelsHeight;
        public int DmDisplayFlags;
        public int DmDisplayFrequency;
        public int DmICMMethod;
        public int DmICMIntent;
        public int DmMediaType;
        public int DmDitherType;
        public int DmReserved1;
        public int DmReserved2;
        public int DmPanningWidth;
        public int DmPanningHeight;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool EnumDisplaySettingsW(string? deviceName, int modeNum, ref DevMode devMode);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern int ChangeDisplaySettingsExW(string? deviceName, ref DevMode devMode,
        IntPtr hwnd, uint flags, IntPtr param);

    public static int? GetRefreshRate(string deviceName)
    {
        if (string.IsNullOrWhiteSpace(deviceName)) return null;
        var mode = new DevMode { DmDeviceName = deviceName, DmFormName = "" };
        mode.DmSize = (short)Marshal.SizeOf<DevMode>();
        return EnumDisplaySettingsW(deviceName, EnumCurrentSettings, ref mode)
            ? mode.DmDisplayFrequency
            : null;
    }

    /// <summary>切换刷新率；成功返回提示文本，失败抛出带 DISP_CHANGE 详情的中文错误。</summary>
    public static string ChangeRefreshRate(string deviceName, int refresh)
    {
        if (string.IsNullOrWhiteSpace(deviceName))
            throw new InvalidOperationException("缺少显示器设备名");

        var mode = new DevMode { DmDeviceName = deviceName, DmFormName = "" };
        mode.DmSize = (short)Marshal.SizeOf<DevMode>();
        if (!EnumDisplaySettingsW(deviceName, EnumCurrentSettings, ref mode))
            throw new InvalidOperationException($"EnumDisplaySettings 失败（设备名: {deviceName}）");

        if (mode.DmDisplayFrequency == refresh) return "已是目标值";

        var original = mode.DmDisplayFrequency;
        mode.DmFields = DmDisplayFrequency;
        mode.DmDisplayFrequency = refresh;

        var test = ChangeDisplaySettingsExW(deviceName, ref mode, IntPtr.Zero, CdsTest, IntPtr.Zero);
        if (test != 0)
            throw new InvalidOperationException($"刷新率预检未通过（DISP_CHANGE={test}）");

        var result = ChangeDisplaySettingsExW(deviceName, ref mode, IntPtr.Zero, CdsUpdateRegistry, IntPtr.Zero);
        var message = result switch
        {
            0 => "成功",
            1 => "成功（需注销或重启生效）",
            -1 => throw new InvalidOperationException("切换刷新率失败（DISP_CHANGE_FAILED）"),
            -2 => throw new InvalidOperationException("模式不被支持（DISP_CHANGE_BADMODE）"),
            -3 => throw new InvalidOperationException("标志无效（DISP_CHANGE_BADFLAGS）"),
            -4 => throw new InvalidOperationException("参数无效（DISP_CHANGE_BADPARAM）"),
            -5 => throw new InvalidOperationException("未能写入注册表（DISP_CHANGE_NOTUPDATED）"),
            _ => throw new InvalidOperationException($"未知返回码: {result}")
        };

        Thread.Sleep(1500);
        var current = GetRefreshRate(deviceName);
        if (current is not null && current != refresh && result == 0)
        {
            // 尝试回退到原刷新率，避免留下不受支持的模式。
            try
            {
                var rollback = new DevMode { DmDeviceName = deviceName, DmFormName = "" };
                rollback.DmSize = (short)Marshal.SizeOf<DevMode>();
                if (EnumDisplaySettingsW(deviceName, EnumCurrentSettings, ref rollback))
                {
                    rollback.DmFields = DmDisplayFrequency;
                    rollback.DmDisplayFrequency = original;
                    ChangeDisplaySettingsExW(deviceName, ref rollback, IntPtr.Zero, CdsUpdateRegistry, IntPtr.Zero);
                }
            }
            catch { }
            throw new InvalidOperationException($"刷新率验证失败（读回 {current}Hz）");
        }

        return message;
    }
}
