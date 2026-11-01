using System.Runtime.InteropServices;

namespace GamePerfCenter.Core.Services;

/// <summary>
/// 音频端点静音保护：驱动安装/切换/清理前后记录所有活动端点的静音状态，
/// 操作结束后只还原“被意外改变”的静音状态，不触碰用户主动调整的音量与静音。
/// </summary>
public sealed class AudioEndpointGuard
{
    private const int RenderFlow = 0;      // eRender
    private const int CaptureFlow = 1;     // eCapture
    private const int StateActive = 1;     // DEVICE_STATE_ACTIVE

    private static readonly Guid ClsidMMDeviceEnumerator =
        new("BCDE0395-E52F-467C-8E3D-C4579291692E");

    private static readonly Guid IidAudioEndpointVolume =
        new("5CDF2C82-841E-4546-9722-0CF74078229A");

    private readonly Dictionary<string, bool> _snapshot = new(StringComparer.OrdinalIgnoreCase);
    private readonly object _lock = new();

    /// <summary>本次捕获到的活动端点数量。</summary>
    public int CapturedCount
    {
        get { lock (_lock) return _snapshot.Count; }
    }

    /// <summary>记录当前所有活动音频端点（渲染 + 采集）的静音状态。</summary>
    public int Capture()
    {
        var states = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
        try
        {
            var enumerator = CreateEnumerator();
            foreach (var flow in new[] { RenderFlow, CaptureFlow })
            {
                if (enumerator.EnumAudioEndpoints(flow, StateActive, out var collection) != 0 ||
                    collection is null) continue;
                try
                {
                    if (collection.GetCount(out var count) != 0) continue;
                    for (var i = 0; i < count; i++)
                    {
                        if (collection.Item(i, out var device) != 0 || device is null) continue;
                        try
                        {
                            if (TryReadState(device, out var id, out var muted))
                                states[id] = muted;
                        }
                        finally { ReleaseCom(device); }
                    }
                }
                finally { ReleaseCom(collection); }
            }
        }
        catch
        {
            return 0;
        }

        lock (_lock)
        {
            _snapshot.Clear();
            foreach (var pair in states) _snapshot[pair.Key] = pair.Value;
            return _snapshot.Count;
        }
    }

    /// <summary>
    /// 与捕获状态比对，只把被改变的端点静音状态还原。
    /// 返回实际修复的端点数量。
    /// </summary>
    public int Restore()
    {
        Dictionary<string, bool> snapshot;
        lock (_lock)
        {
            if (_snapshot.Count == 0) return 0;
            snapshot = new Dictionary<string, bool>(_snapshot, StringComparer.OrdinalIgnoreCase);
        }

        var restored = 0;
        try
        {
            var enumerator = CreateEnumerator();
            foreach (var flow in new[] { RenderFlow, CaptureFlow })
            {
                if (enumerator.EnumAudioEndpoints(flow, StateActive, out var collection) != 0 ||
                    collection is null) continue;
                try
                {
                    if (collection.GetCount(out var count) != 0) continue;
                    for (var i = 0; i < count; i++)
                    {
                        if (collection.Item(i, out var device) != 0 || device is null) continue;
                        try
                        {
                            if (!TryReadState(device, out var id, out var muted)) continue;
                            if (!snapshot.TryGetValue(id, out var wanted) || muted == wanted) continue;
                            if (TrySetMute(device, wanted)) restored++;
                        }
                        finally { ReleaseCom(device); }
                    }
                }
                finally { ReleaseCom(collection); }
            }
        }
        catch
        {
            return restored;
        }

        return restored;
    }

    /// <summary>清空快照，避免把上一次操作的状态带到下一次。</summary>
    public void Reset()
    {
        lock (_lock) _snapshot.Clear();
    }

    private static IMMDeviceEnumerator CreateEnumerator()
    {
        var type = Type.GetTypeFromCLSID(ClsidMMDeviceEnumerator, throwOnError: true)!;
        return (IMMDeviceEnumerator)Activator.CreateInstance(type)!;
    }

    private static bool TryReadState(IMMDevice device, out string id, out bool muted)
    {
        id = "";
        muted = false;
        if (device.GetId(out var deviceId) != 0 || string.IsNullOrWhiteSpace(deviceId)) return false;
        id = deviceId!;
        var stateRead = false;
        var isMuted = false;
        var ok = TryWithVolume(device, volume =>
        {
            if (volume.GetMute(out var value) != 0) return false;
            isMuted = value != 0;
            stateRead = true;
            return true;
        });
        if (!ok || !stateRead) return false;
        muted = isMuted;
        return true;
    }

    private static bool TrySetMute(IMMDevice device, bool muted) =>
        TryWithVolume(device, volume => volume.SetMute(muted ? 1 : 0, Guid.Empty) == 0);

    private static bool TryWithVolume(IMMDevice device, Func<IAudioEndpointVolume, bool> action)
    {
        var iid = IidAudioEndpointVolume;
        if (device.Activate(ref iid, 23 /* CLSCTX_ALL */, IntPtr.Zero, out var pointer) != 0 ||
            pointer == IntPtr.Zero) return false;
        try
        {
            var volume = (IAudioEndpointVolume)Marshal.GetObjectForIUnknown(pointer);
            try { return action(volume); }
            finally { ReleaseCom(volume); }
        }
        finally
        {
            Marshal.Release(pointer);
        }
    }

    private static void ReleaseCom(object? value)
    {
        if (value is not null && Marshal.IsComObject(value))
        {
            try { Marshal.ReleaseComObject(value); } catch { }
        }
    }

    [ComImport]
    [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IMMDeviceEnumerator
    {
        [PreserveSig] int EnumAudioEndpoints(int dataFlow, int stateMask, out IMMDeviceCollection devices);
        [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice endpoint);
        [PreserveSig] int GetDevice([MarshalAs(UnmanagedType.LPWStr)] string id, out IMMDevice device);
        [PreserveSig] int RegisterEndpointNotificationCallback(IntPtr client);
        [PreserveSig] int UnregisterEndpointNotificationCallback(IntPtr client);
    }

    [ComImport]
    [Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IMMDeviceCollection
    {
        [PreserveSig] int GetCount(out int count);
        [PreserveSig] int Item(int index, out IMMDevice device);
    }

    [ComImport]
    [Guid("D666063F-1587-4E43-81F1-B948E807363F")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IMMDevice
    {
        [PreserveSig] int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, out IntPtr interfacePointer);
        [PreserveSig] int OpenPropertyStore(int access, out IntPtr properties);
        [PreserveSig] int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
        [PreserveSig] int GetState(out int state);
    }

    [ComImport]
    [Guid("5CDF2C82-841E-4546-9722-0CF74078229A")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IAudioEndpointVolume
    {
        [PreserveSig] int RegisterControlChangeNotify(IntPtr notify);
        [PreserveSig] int UnregisterControlChangeNotify(IntPtr notify);
        [PreserveSig] int GetChannelCount(out int count);
        [PreserveSig] int SetMasterVolumeLevel(float level, Guid eventContext);
        [PreserveSig] int SetMasterVolumeLevelScalar(float level, Guid eventContext);
        [PreserveSig] int GetMasterVolumeLevel(out float level);
        [PreserveSig] int GetMasterVolumeLevelScalar(out float level);
        [PreserveSig] int SetChannelVolumeLevel(uint channel, float level, Guid eventContext);
        [PreserveSig] int SetChannelVolumeLevelScalar(uint channel, float level, Guid eventContext);
        [PreserveSig] int GetChannelVolumeLevel(uint channel, out float level);
        [PreserveSig] int GetChannelVolumeLevelScalar(uint channel, out float level);
        [PreserveSig] int SetMute(int muted, Guid eventContext);
        [PreserveSig] int GetMute(out int muted);
    }
}
