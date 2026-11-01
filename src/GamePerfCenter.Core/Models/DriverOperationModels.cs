namespace GamePerfCenter.Core.Models;

public enum DriverOperationKind
{
    RebindCurrent,
    SwitchPackage,
    DeletePackage,
    InstallInf
}

public sealed class DriverOperationOptions
{
    /// <summary>只验证并输出将要执行的命令，不写入系统。</summary>
    public bool DryRun { get; init; }

    /// <summary>删除驱动包时调用 pnputil /uninstall。</summary>
    public bool Uninstall { get; init; } = true;

    /// <summary>删除驱动包时追加 /force（Windows 11 可用，强制卸载相关设备）。</summary>
    public bool Force { get; init; }

    /// <summary>跳过 INF 与设备硬件 ID 的匹配校验（仅用于明确知道 INF 用途的场景）。</summary>
    public bool AllowUnverifiedInf { get; init; }

    /// <summary>操作结束后等待一段时间再恢复一次音频静音状态，覆盖端点重新枚举的延迟。</summary>
    public bool WaitForAudioRestore { get; init; } = true;

    public TimeSpan AudioRestoreDelay { get; init; } = TimeSpan.FromMilliseconds(2500);
}

public sealed class DriverOperationResult
{
    public bool Ok { get; init; }
    public DriverOperationKind Kind { get; init; }
    public string Action { get; init; } = "";
    public string DeviceName { get; init; } = "";
    public string DeviceId { get; init; } = "";
    public string PublishedName { get; init; } = "";
    public string InfPath { get; init; } = "";
    public string Command { get; init; } = "";
    public int ExitCode { get; init; }
    public IReadOnlyList<string> Output { get; init; } = Array.Empty<string>();
    public string Message { get; init; } = "";
    public bool DryRun { get; init; }
    public bool RebootRecommended { get; init; }
    public int AudioEndpoints { get; init; }
    public int AudioRestored { get; init; }
    public DateTime At { get; init; } = DateTime.Now;
}
