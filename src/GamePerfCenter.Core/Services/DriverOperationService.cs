using System.Security.Principal;
using System.Text;
using GamePerfCenter.Core.Infrastructure;
using GamePerfCenter.Core.Models;

namespace GamePerfCenter.Core.Services;

/// <summary>
/// 驱动安装、切换与清理。所有会写入系统的操作都要求管理员权限，
/// 并在开始前捕获音频端点静音状态，结束后自动恢复被意外改变的部分。
/// </summary>
public sealed class DriverOperationService
{
    private readonly InfMetadataReader _infReader;

    public DriverOperationService(InfMetadataReader? infReader = null)
    {
        _infReader = infReader ?? new InfMetadataReader();
    }

    public bool IsElevated
    {
        get
        {
            try
            {
                using var identity = WindowsIdentity.GetCurrent();
                return new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator);
            }
            catch { return false; }
        }
    }

    /// <summary>使用设备当前生效的 INF 重新绑定驱动。</summary>
    public DriverOperationResult RebindCurrent(DriverDeviceInfo device, DriverOperationOptions? options = null)
    {
        options ??= new DriverOperationOptions();
        var infName = (device.InfName ?? "").Trim();
        if (infName.Length == 0)
            return Fail(DriverOperationKind.RebindCurrent, "当前设备没有可用的 INF 文件名，无法重新绑定。", device, options);
        var path = Path.Combine(WindowsInfDirectory, infName);
        return RunInstall(DriverOperationKind.RebindCurrent, device, infName, path, options);
    }

    /// <summary>把设备切换到驱动仓库中的另一个包。</summary>
    public DriverOperationResult SwitchPackage(
        DriverDeviceInfo device,
        DriverPackageMatch package,
        DriverOperationOptions? options = null)
    {
        options ??= new DriverOperationOptions();
        if (package.InUse)
            return Fail(DriverOperationKind.SwitchPackage, "选中的已经是当前正在使用的驱动包。", device, options, package.PublishedName);

        var owner = device.Packages.FirstOrDefault(p =>
            p.PublishedName.Equals(package.PublishedName, StringComparison.OrdinalIgnoreCase));
        if (owner is null)
            return Fail(DriverOperationKind.SwitchPackage,
                "该驱动包不在当前设备的匹配列表中，已拒绝切换。", device, options, package.PublishedName);

        var path = Path.Combine(WindowsInfDirectory, package.PublishedName);
        return RunInstall(DriverOperationKind.SwitchPackage, device, package.PublishedName, path, options);
    }

    /// <summary>安装任意 INF 文件；提供设备时校验该 INF 是否匹配设备硬件 ID。</summary>
    public DriverOperationResult InstallInf(
        string infPath,
        DriverDeviceInfo? device = null,
        DriverOperationOptions? options = null)
    {
        options ??= new DriverOperationOptions();
        if (string.IsNullOrWhiteSpace(infPath))
            return Fail(DriverOperationKind.InstallInf, "INF 路径为空。", device, options);

        var resolved = ResolveInfPath(infPath);
        if (resolved is null)
            return Fail(DriverOperationKind.InstallInf, $"找不到 INF 文件：{infPath}", device, options);

        return RunInstall(DriverOperationKind.InstallInf, device, Path.GetFileName(resolved), resolved, options);
    }

    /// <summary>从驱动仓库删除一个旧包；当前正在使用的包会被拒绝。</summary>
    public DriverOperationResult DeletePackage(
        DriverDeviceInfo device,
        DriverPackageMatch package,
        DriverOperationOptions? options = null)
    {
        options ??= new DriverOperationOptions();
        if (package.InUse)
            return Fail(DriverOperationKind.DeletePackage,
                "当前正在使用的驱动包不能删除。请先切换到其它驱动包。", device, options, package.PublishedName);

        var owner = device.Packages.FirstOrDefault(p =>
            p.PublishedName.Equals(package.PublishedName, StringComparison.OrdinalIgnoreCase));
        if (owner is null)
            return Fail(DriverOperationKind.DeletePackage,
                "该驱动包不在当前设备的匹配列表中，已拒绝删除。", device, options, package.PublishedName);

        if (string.IsNullOrWhiteSpace(package.PublishedName))
            return Fail(DriverOperationKind.DeletePackage, "驱动包发布名称为空。", device, options);

        var command = $"/delete-driver {Quote(package.PublishedName)}";
        if (options.Uninstall) command += " /uninstall";
        if (options.Force) command += " /force";
        return RunCommand(
            DriverOperationKind.DeletePackage,
            device,
            package.PublishedName,
            "",
            command,
            options,
            rebootRecommended: true);
    }

    private DriverOperationResult RunInstall(
        DriverOperationKind kind,
        DriverDeviceInfo? device,
        string publishedName,
        string infPath,
        DriverOperationOptions options)
    {
        if (!File.Exists(infPath))
            return Fail(kind, $"未找到驱动包：{infPath}", device, options, publishedName);

        if (device is not null && !options.AllowUnverifiedInf)
        {
            var meta = _infReader.ReadFile(infPath);
            if (meta is null)
                return Fail(kind, $"无法解析 INF：{infPath}", device, options, publishedName);

            var hardwareId = string.IsNullOrWhiteSpace(device.HardwareId) ? device.DeviceId : device.HardwareId;
            var matched = meta.HardwareIds.Any(candidate =>
                DriverUtils.HardwareMatches(hardwareId, candidate));
            if (!matched)
            {
                return Fail(kind,
                    $"该 INF 不包含设备 {device.Name} 的硬件 ID，已拒绝安装。" +
                    "如确认无误，可使用强制选项跳过校验。",
                    device, options, publishedName);
            }
        }

        var command = $"/add-driver {Quote(infPath)} /install";
        return RunCommand(kind, device, publishedName, infPath, command, options, rebootRecommended: true);
    }

    private DriverOperationResult RunCommand(
        DriverOperationKind kind,
        DriverDeviceInfo? device,
        string publishedName,
        string infPath,
        string command,
        DriverOperationOptions options,
        bool rebootRecommended)
    {
        var action = ActionFor(kind);

        if (!options.DryRun && !IsElevated)
        {
            return Fail(kind, "该操作需要管理员权限，请以管理员身份重新启动。", device, options, publishedName, infPath);
        }

        if (options.DryRun)
        {
            return new DriverOperationResult
            {
                Ok = true,
                Kind = kind,
                Action = action,
                DeviceName = device?.Name ?? "",
                DeviceId = device?.DeviceId ?? "",
                PublishedName = publishedName,
                InfPath = infPath,
                Command = "pnputil " + command,
                DryRun = true,
                RebootRecommended = rebootRecommended,
                Message = "预览模式：未执行任何写入。"
            };
        }

        var guard = new AudioEndpointGuard();
        var captured = 0;
        try { captured = guard.Capture(); } catch { }
        var restored = 0;

        try
        {
            var result = PnPUtilRunner.Execute(command, TimeSpan.FromMinutes(10));
            var ok = result.ExitCode == 0;
            var message = BuildMessage(ok, action, result.Lines, result.ExitCode);

            if (ok && options.WaitForAudioRestore && captured > 0)
            {
                // 驱动重新枚举端点有延迟，立即恢复一次后再等待一次，避免端点稍后才被静音。
                try { restored += guard.Restore(); } catch { }
                try { Thread.Sleep(options.AudioRestoreDelay); } catch { }
            }

            return new DriverOperationResult
            {
                Ok = ok,
                Kind = kind,
                Action = action,
                DeviceName = device?.Name ?? "",
                DeviceId = device?.DeviceId ?? "",
                PublishedName = publishedName,
                InfPath = infPath,
                Command = "pnputil " + command,
                ExitCode = result.ExitCode,
                Output = result.Lines,
                Message = message,
                DryRun = false,
                RebootRecommended = rebootRecommended,
                AudioEndpoints = captured,
                AudioRestored = restored
            };
        }
        catch (Exception ex)
        {
            return new DriverOperationResult
            {
                Ok = false,
                Kind = kind,
                Action = action,
                DeviceName = device?.Name ?? "",
                DeviceId = device?.DeviceId ?? "",
                PublishedName = publishedName,
                InfPath = infPath,
                Command = "pnputil " + command,
                Message = ex.Message,
                AudioEndpoints = captured,
                AudioRestored = restored,
                RebootRecommended = rebootRecommended
            };
        }
        finally
        {
            try { restored += guard.Restore(); } catch { }
        }
    }

    private static string BuildMessage(bool ok, string action, IReadOnlyList<string> lines, int exitCode)
    {
        var text = new StringBuilder();
        text.Append(ok ? $"{action}命令已完成。" : $"{action}失败（退出码 {exitCode}）。");
        var detail = string.Join("\n", lines.Where(l => !string.IsNullOrWhiteSpace(l)).Take(12));
        if (detail.Length > 0)
        {
            text.AppendLine();
            text.Append(detail);
        }
        if (ok) text.Append("\n如果设备没有立即变化，请重启后再查看。");
        return text.ToString();
    }

    private static string ActionFor(DriverOperationKind kind) => kind switch
    {
        DriverOperationKind.RebindCurrent => "重新绑定当前驱动",
        DriverOperationKind.SwitchPackage => "切换驱动包",
        DriverOperationKind.DeletePackage => "清理旧驱动包",
        _ => "安装 INF 驱动"
    };

    private static DriverOperationResult Fail(
        DriverOperationKind kind,
        string message,
        DriverDeviceInfo? device,
        DriverOperationOptions options,
        string publishedName = "",
        string infPath = "")
    {
        return new DriverOperationResult
        {
            Ok = false,
            Kind = kind,
            Action = ActionFor(kind),
            DeviceName = device?.Name ?? "",
            DeviceId = device?.DeviceId ?? "",
            PublishedName = publishedName,
            InfPath = infPath,
            Message = message,
            DryRun = options.DryRun
        };
    }

    private static string? ResolveInfPath(string infPath)
    {
        if (File.Exists(infPath)) return Path.GetFullPath(infPath);
        var candidate = Path.Combine(WindowsInfDirectory, infPath);
        return File.Exists(candidate) ? candidate : null;
    }

    private static string WindowsInfDirectory =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "INF");

    private static string Quote(string value) => "\"" + value.Replace("\"", "\\\"") + "\"";
}
