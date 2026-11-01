using System.Diagnostics;
using System.Security.Principal;
using System.Text;

namespace GamePerfCenter.Services;

/// <summary>供 PCL 风格错误弹窗直接展示的报告。</summary>
public sealed class EngineReport
{
    public string Summary { get; init; } = "";
    public string Cause { get; init; } = "";
    public IReadOnlyList<string> Suggestions { get; init; } = Array.Empty<string>();
    public string Details { get; init; } = "";
    public string? ReportPath { get; init; }
}

/// <summary>
/// 不依赖优化引擎本身，单独探测 PowerShell、执行策略、语言模式、WMI 与目录权限，
/// 把“为什么退出”变成能看懂、能带走的一段文字。
/// </summary>
public static class EngineDiagnostics
{
    public static async Task<EngineReport> BuildAsync(EngineFailure? failure, Exception? error,
        CancellationToken ct = default)
    {
        var checks = new List<Check>();
        var suggestions = new List<string>();

        var os = Environment.OSVersion.VersionString;
        var arch = System.Runtime.InteropServices.RuntimeInformation.OSArchitecture.ToString();
        var elevated = IsElevated();

        var powershell = EngineBridge.ResolvePowerShell(out var psError);
        ProbeResult? psProbe = null;
        string languageMode = "";
        string executionPolicy = "";
        if (powershell is not null)
        {
            psProbe = await RunProbeAsync(powershell, PsProbeScript, TimeSpan.FromSeconds(25), ct)
                .ConfigureAwait(false);
            if (psProbe.TimedOut)
                checks.Add(new Check(false, "Windows PowerShell", "探测超时，PowerShell 可能被安全软件挂起"));
            else if (psProbe.ExitCode != 0)
                checks.Add(new Check(false, "Windows PowerShell", $"执行命令失败（退出码 {psProbe.ExitCode}）：{Short(psProbe.Error)}"));
            else
                checks.Add(new Check(true, "Windows PowerShell", Short(psProbe.Output)));

            languageMode = ReadValue(psProbe.Output, "LanguageMode");
            executionPolicy = ReadValue(psProbe.Output, "ExecutionPolicy");
            if (languageMode.Contains("Constrained", StringComparison.OrdinalIgnoreCase))
                checks.Add(new Check(false, "PowerShell 语言模式", "ConstrainedLanguage：系统策略禁止执行完整脚本"));
            if (IsRestrictivePolicy(executionPolicy))
                checks.Add(new Check(false, "PowerShell 执行策略", executionPolicy.Replace(";", " · ")));
        }
        else
        {
            checks.Add(new Check(false, "Windows PowerShell", psError ?? "未找到 powershell.exe"));
        }

        var bridgeOk = File.Exists(AppPaths.BridgePath);
        var engineOk = File.Exists(AppPaths.EnginePath);
        checks.Add(new Check(bridgeOk, "桥接脚本", bridgeOk ? AppPaths.BridgePath : "缺失：" + AppPaths.BridgePath));
        checks.Add(new Check(engineOk, "引擎脚本", engineOk ? $"{AppPaths.EnginePath}（{SizeText(AppPaths.EnginePath)}）" : "缺失：" + AppPaths.EnginePath));

        var writeOk = CanWrite(AppPaths.DataDir, out var writeError);
        checks.Add(new Check(writeOk, "数据目录可写", writeOk ? AppPaths.DataDir : writeError));

        ProbeResult? wmiProbe = null;
        if (powershell is not null)
        {
            wmiProbe = await RunProbeAsync(powershell, WmiProbeScript, TimeSpan.FromSeconds(30), ct)
                .ConfigureAwait(false);
            var wmiOk = wmiProbe.ExitCode == 0 && wmiProbe.Output.Contains("WMI=OK", StringComparison.Ordinal);
            checks.Add(new Check(wmiOk, "WMI 查询", Short(wmiProbe.Output + " " + wmiProbe.Error)));
        }

        var exitCode = failure?.ExitCode;
        var cause = DetermineCause(failure, error, powershell, psProbe, languageMode, executionPolicy,
            wmiProbe, writeOk);
        AddSuggestions(suggestions, failure, error, powershell, psProbe, languageMode, executionPolicy,
            wmiProbe, writeOk, elevated);

        var summary = failure?.Summary
            ?? (error is not null ? "优化引擎没有正常工作" : "引擎连接中断");

        var details = BuildDetails(failure, error, os, arch, elevated, checks, suggestions,
            languageMode, executionPolicy, powershell);

        var path = SaveReport(details);

        return new EngineReport
        {
            Summary = summary,
            Cause = cause,
            Suggestions = suggestions,
            Details = details,
            ReportPath = path
        };
    }

    private sealed record Check(bool Ok, string Name, string Detail);

    private sealed record ProbeResult(string Output, string Error, int? ExitCode, bool TimedOut);

    private const string PsProbeScript = """
        $ErrorActionPreference = 'Continue'
        try { 'PSVersion=' + $PSVersionTable.PSVersion.ToString() } catch { 'PSVersion=ERROR ' + $_.Exception.Message }
        try { 'LanguageMode=' + [string]$ExecutionContext.SessionState.LanguageMode } catch { }
        try {
            $p = Get-ExecutionPolicy -List -ErrorAction Stop |
                ForEach-Object { "$($_.Scope)=$($_.ExecutionPolicy)" }
            'ExecutionPolicy=' + ($p -join ';')
        } catch { 'ExecutionPolicy=ERROR ' + $_.Exception.Message }
        try { 'OutputEncoding=' + [Console]::OutputEncoding.WebName } catch { }
        """;

    private const string WmiProbeScript = """
        $ErrorActionPreference = 'Stop'
        try {
            $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop | Select-Object -First 1
            'WMI=OK ' + $os.Caption + ' ' + $os.Version + ' build ' + $os.BuildNumber
        } catch {
            'WMI=FAIL ' + $_.Exception.Message
        }
        """;

    private static string DetermineCause(EngineFailure? failure, Exception? error, string? powershell,
        ProbeResult? psProbe, string languageMode, string executionPolicy, ProbeResult? wmiProbe, bool writeOk)
    {
        if (powershell is null)
            return "找不到 Windows PowerShell，引擎根本没有机会启动。常见原因是安全软件删除系统组件，或系统镜像经过精简。";
        if (psProbe is not null && psProbe.TimedOut)
            return "Windows PowerShell 启动后没有任何响应，通常是被安全软件挂起或系统组件损坏。";
        if (psProbe is not null && psProbe.ExitCode != 0)
            return "Windows PowerShell 无法正常执行命令，可能是系统组件损坏或被安全策略拦截。";
        if (languageMode.Contains("Constrained", StringComparison.OrdinalIgnoreCase))
            return "系统把 PowerShell 限制在 ConstrainedLanguage 模式，优化脚本无法执行完整操作。";
        if (IsRestrictivePolicy(executionPolicy))
            return "PowerShell 执行策略禁止运行本地脚本，引擎在加载时被系统拒绝。";
        if (!writeOk)
            return "程序目录不可写，引擎无法创建日志或备份文件，启动过程中被迫退出。";
        if (wmiProbe is not null && !wmiProbe.Output.Contains("WMI=OK", StringComparison.Ordinal))
            return "本机 WMI 查询失败。引擎读取硬件、显卡和网卡信息都依赖 WMI，这个组件损坏会直接导致退出。";

        if (failure?.ExitCode is int code)
        {
            var mapped = code switch
            {
                0 => "引擎以 0 退出，通常是脚本被策略中止或主动结束，而不是崩溃。",
                -1073741819 => "引擎遇到内存访问冲突（0xC0000005），常见于显卡驱动、安全软件注入或系统组件损坏。",
                -1073741571 => "引擎发生栈溢出（0xC00000FD），通常是硬件查询返回了异常数据。",
                -1073741515 => "引擎缺少系统 DLL（0xC0000135），系统组件可能不完整。",
                -1073741701 => "系统组件位数不匹配（0xC000007B），可能混入了 32 位 DLL。",
                -1073741795 => "CPU 执行到非法指令（0xC000001D），常见于虚拟机或兼容性模式。",
                _ => $"引擎以退出代码 {code}（0x{code:X8}）结束，没有留下更明确的错误。"
            };
            var stderr = failure.StderrTail ?? "";
            if (stderr.Contains("running scripts is disabled", StringComparison.OrdinalIgnoreCase)
                || stderr.Contains("禁止运行脚本", StringComparison.Ordinal))
                return "PowerShell 执行策略禁止运行脚本，引擎在加载时被系统拒绝。";
            if (stderr.Contains("Access is denied", StringComparison.OrdinalIgnoreCase)
                || stderr.Contains("拒绝访问", StringComparison.Ordinal))
                return "引擎访问系统资源时被拒绝，通常是安全软件拦截或权限不足。";
            return mapped;
        }

        if (error is not null)
            return $"界面在准备引擎时遇到异常：{Short(error.Message)}";
        return "引擎进程退出，但没有留下明确的退出代码或错误输出。";
    }

    private static void AddSuggestions(List<string> suggestions, EngineFailure? failure, Exception? error,
        string? powershell, ProbeResult? psProbe, string languageMode, string executionPolicy,
        ProbeResult? wmiProbe, bool writeOk, bool elevated)
    {
        if (powershell is null)
        {
            suggestions.Add("在“设置 → 应用 → 可选功能”中检查 Windows PowerShell，或运行 sfc /scannow 修复系统文件。");
            suggestions.Add("暂时关闭安全软件的自定义脚本防护，再重新打开本程序。");
        }
        if (psProbe is not null && (psProbe.TimedOut || psProbe.ExitCode != 0))
            suggestions.Add("重启电脑后重试；如果仍然失败，运行 sfc /scannow 与 DISM /Online /Cleanup-Image /RestoreHealth。");
        if (languageMode.Contains("Constrained", StringComparison.OrdinalIgnoreCase))
            suggestions.Add("检查 Windows Defender 应用控制（WDAC）、AppLocker 或企业安全策略，确认没有限制 powershell.exe。");
        if (IsRestrictivePolicy(executionPolicy))
        {
            suggestions.Add("用管理员 PowerShell 执行：Set-ExecutionPolicy -Scope LocalMachine RemoteSigned");
            suggestions.Add("如果 MachinePolicy/UserPolicy 被组策略锁定，需要联系管理员放行，脚本无法自行绕过。");
        }
        if (!writeOk)
            suggestions.Add("把程序移动到当前用户可写的目录（例如桌面或 D 盘），不要放在受保护的系统目录。");
        if (wmiProbe is not null && !wmiProbe.Output.Contains("WMI=OK", StringComparison.Ordinal))
            suggestions.Add("用管理员 PowerShell 执行：winmgmt /verifyrepository；若提示损坏，再执行 winmgmt /salvagerepository。");
        if (failure?.ExitCode is -1073741819)
            suggestions.Add("更新或回退显卡驱动，并暂时退出带注入功能的安全软件、加速器或录屏工具后重试。");
        if (failure?.ExitCode is 0)
            suggestions.Add("查看下方“技术详情”里的 stderr 与引擎日志，通常会指出被拦截的具体行。");
        if (!elevated)
            suggestions.Add("右键程序选择“以管理员身份运行”，引擎需要管理员权限读取部分硬件与注册表信息。");

        suggestions.Add("点击“重新连接”会重启引擎；仍失败时点“复制报告”，把完整内容发给作者。");
        suggestions.Add("也可以到“运行日志”页查看最近输出，日志只保存在本机。");
    }

    private static string BuildDetails(EngineFailure? failure, Exception? error, string os, string arch,
        bool elevated, List<Check> checks, List<string> suggestions, string languageMode,
        string executionPolicy, string? powershell)
    {
        var sb = new StringBuilder();
        sb.AppendLine("游戏性能优化中心 · 引擎故障报告");
        sb.AppendLine($"生成时间: {DateTime.Now:yyyy-MM-dd HH:mm:ss}");
        sb.AppendLine($"程序版本: {AppPaths.Version}");
        sb.AppendLine($"程序目录: {AppPaths.BaseDir}");
        sb.AppendLine($"操作系统: {os} ({arch})");
        sb.AppendLine($"管理员权限: {(elevated ? "是" : "否")}");
        sb.AppendLine($"系统区域: {System.Globalization.CultureInfo.CurrentCulture.Name} / 界面 {System.Globalization.CultureInfo.CurrentUICulture.Name}");
        sb.AppendLine($"PowerShell: {powershell ?? "未找到"}");
        sb.AppendLine($"语言模式: {(string.IsNullOrEmpty(languageMode) ? "未知" : languageMode)}");
        sb.AppendLine($"执行策略: {(string.IsNullOrEmpty(executionPolicy) ? "未知" : executionPolicy.Replace(";", " · "))}");
        sb.AppendLine();

        sb.AppendLine("── 自动检测 ──────────────────────────────");
        foreach (var check in checks)
            sb.AppendLine($"[{(check.Ok ? "通过" : "异常")}] {check.Name}: {check.Detail}");
        sb.AppendLine();

        sb.AppendLine("── 故障现场 ──────────────────────────────");
        if (failure is not null)
        {
            sb.AppendLine($"概要: {failure.Summary}");
            sb.AppendLine($"退出代码: {(failure.ExitCode is int c ? $"{c} (0x{c:X8})" : "未知")}");
            sb.AppendLine($"最后命令: {failure.Command ?? "—"}");
            sb.AppendLine($"启动时间: {failure.StartedAt:yyyy-MM-dd HH:mm:ss}");
            sb.AppendLine($"退出时间: {failure.ExitedAt:yyyy-MM-dd HH:mm:ss}");
            if (!string.IsNullOrWhiteSpace(failure.StderrTail))
            {
                sb.AppendLine();
                sb.AppendLine("stderr (最多 200 行):");
                sb.AppendLine(Tail(failure.StderrTail, 120));
            }
            if (!string.IsNullOrWhiteSpace(failure.StdoutTail))
            {
                sb.AppendLine();
                sb.AppendLine("stdout 非协议输出 (最多 200 行):");
                sb.AppendLine(Tail(failure.StdoutTail, 80));
            }
        }
        else if (error is not null)
        {
            sb.AppendLine($"异常类型: {error.GetType().FullName}");
            sb.AppendLine($"异常消息: {error.Message}");
            if (error is EngineException { Detail: { } detail }) sb.AppendLine(detail);
            sb.AppendLine(error.StackTrace ?? "");
        }
        else
        {
            sb.AppendLine("没有捕获到退出代码或异常。");
        }
        sb.AppendLine();

        sb.AppendLine("── 建议 ──────────────────────────────────");
        for (var i = 0; i < suggestions.Count; i++)
            sb.AppendLine($"{i + 1}. {suggestions[i]}");
        sb.AppendLine();

        sb.AppendLine("── 应用日志 (data\\winui.log 末尾) ────────");
        sb.AppendLine(TailFile(AppPaths.AppLogPath, 120));
        sb.AppendLine();
        sb.AppendLine("── 引擎镜像日志 (data\\engine.log 末尾) ───");
        sb.AppendLine(TailFile(Path.Combine(AppPaths.DataDir, "engine.log"), 160));
        return sb.ToString();
    }

    private static string? SaveReport(string details)
    {
        try
        {
            Directory.CreateDirectory(AppPaths.DataDir);
            var path = Path.Combine(AppPaths.DataDir, $"engine-report_{DateTime.Now:yyyyMMdd_HHmmss}.txt");
            File.WriteAllText(path, details, new UTF8Encoding(false));
            return path;
        }
        catch { return null; }
    }

    private static async Task<ProbeResult> RunProbeAsync(string fileName, string script, TimeSpan timeout,
        CancellationToken ct)
    {
        var encoded = Convert.ToBase64String(Encoding.Unicode.GetBytes(script));
        var psi = new ProcessStartInfo
        {
            FileName = fileName,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            WindowStyle = ProcessWindowStyle.Hidden
        };
        psi.ArgumentList.Add("-NoLogo");
        psi.ArgumentList.Add("-NoProfile");
        psi.ArgumentList.Add("-NonInteractive");
        psi.ArgumentList.Add("-ExecutionPolicy");
        psi.ArgumentList.Add("Bypass");
        psi.ArgumentList.Add("-EncodedCommand");
        psi.ArgumentList.Add(encoded);

        try
        {
            using var proc = new Process { StartInfo = psi };
            if (!proc.Start())
                return new ProbeResult("", "无法启动探测进程", null, false);

            var stdoutTask = proc.StandardOutput.ReadToEndAsync();
            var stderrTask = proc.StandardError.ReadToEndAsync();
            using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            cts.CancelAfter(timeout);
            try
            {
                await proc.WaitForExitAsync(cts.Token).ConfigureAwait(false);
                return new ProbeResult(await stdoutTask.ConfigureAwait(false),
                    await stderrTask.ConfigureAwait(false), proc.ExitCode, false);
            }
            catch (OperationCanceledException)
            {
                try { proc.Kill(true); } catch { }
                return new ProbeResult("", "探测超时", null, true);
            }
        }
        catch (Exception ex)
        {
            return new ProbeResult("", ex.Message, null, false);
        }
    }

    private static bool CanWrite(string directory, out string error)
    {
        try
        {
            Directory.CreateDirectory(directory);
            var probe = Path.Combine(directory, ".write-test");
            File.WriteAllText(probe, "ok");
            File.Delete(probe);
            error = "可写";
            return true;
        }
        catch (Exception ex)
        {
            error = ex.Message;
            return false;
        }
    }

    private static bool IsElevated()
    {
        try
        {
            using var identity = WindowsIdentity.GetCurrent();
            return new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator);
        }
        catch { return false; }
    }

    private static bool IsRestrictivePolicy(string policy)
    {
        if (string.IsNullOrWhiteSpace(policy)) return false;
        // 启动时始终带 -ExecutionPolicy Bypass，本地/当前用户的 AllSigned 会被命令行覆盖；
        // 真正无法绕过的是组策略锁定的 MachinePolicy / UserPolicy。
        foreach (var part in policy.Split(';', StringSplitOptions.RemoveEmptyEntries))
        {
            var pair = part.Split('=', 2);
            if (pair.Length != 2) continue;
            var scope = pair[0].Trim();
            var value = pair[1].Trim();
            if (!scope.Equals("MachinePolicy", StringComparison.OrdinalIgnoreCase)
                && !scope.Equals("UserPolicy", StringComparison.OrdinalIgnoreCase))
                continue;
            if (value.Equals("Restricted", StringComparison.OrdinalIgnoreCase)
                || value.Equals("AllSigned", StringComparison.OrdinalIgnoreCase))
                return true;
        }
        return false;
    }

    private static string ReadValue(string text, string key)
    {
        foreach (var line in text.Split('\n'))
        {
            var trimmed = line.Trim();
            if (trimmed.StartsWith(key + "=", StringComparison.OrdinalIgnoreCase))
                return trimmed[(key.Length + 1)..].Trim();
        }
        return "";
    }

    private static string Short(string? text)
    {
        if (string.IsNullOrWhiteSpace(text)) return "没有输出";
        var oneLine = text.Replace("\r", " ").Replace("\n", " ").Trim();
        return oneLine.Length <= 220 ? oneLine : oneLine[..220] + "…";
    }

    private static string SizeText(string path)
    {
        try { return $"{new FileInfo(path).Length / 1024.0:0.0} KB"; }
        catch { return "大小未知"; }
    }

    private static string Tail(string text, int lines)
    {
        var all = text.Replace("\r\n", "\n").Split('\n');
        return string.Join(Environment.NewLine, all.TakeLast(lines));
    }

    private static string TailFile(string path, int lines)
    {
        try
        {
            if (!File.Exists(path)) return "(文件不存在)";
            using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
            using var reader = new StreamReader(stream, Encoding.UTF8);
            var queue = new Queue<string>();
            while (reader.ReadLine() is { } line)
            {
                queue.Enqueue(line);
                if (queue.Count > lines) queue.Dequeue();
            }
            return queue.Count == 0 ? "(空文件)" : string.Join(Environment.NewLine, queue);
        }
        catch (Exception ex)
        {
            return "(读取失败: " + ex.Message + ")";
        }
    }
}
