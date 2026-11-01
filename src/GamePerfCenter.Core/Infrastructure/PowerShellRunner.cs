using System.Diagnostics;
using System.Text;

namespace GamePerfCenter.Core.Infrastructure;

/// <summary>以隐藏窗口调用 Windows PowerShell，供网卡高级属性等仅 cmdlet 可写的场景使用。</summary>
public static class PowerShellRunner
{
    public static string RunScript(string script, TimeSpan? timeout = null)
    {
        var encoded = Convert.ToBase64String(Encoding.Unicode.GetBytes(script));
        var result = Execute("powershell.exe",
            new[] { "-NoProfile", "-ExecutionPolicy", "Bypass", "-EncodedCommand", encoded },
            timeout);
        if (result.ExitCode != 0)
            throw new InvalidOperationException($"PowerShell 退出码 {result.ExitCode}: {result.ErrorText.Trim()}");
        return result.OutputText;
    }

    public static string RunFile(string scriptPath, IEnumerable<string>? arguments = null, TimeSpan? timeout = null)
    {
        var args = new List<string> { "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", scriptPath };
        if (arguments is not null) args.AddRange(arguments);
        var result = Execute("powershell.exe", args, timeout);
        if (result.ExitCode != 0)
            throw new InvalidOperationException($"PowerShell 退出码 {result.ExitCode}: {result.ErrorText.Trim()}");
        return result.OutputText;
    }

    public static ProcessResult Execute(string fileName, IEnumerable<string> arguments, TimeSpan? timeout = null)
    {
        var psi = new ProcessStartInfo
        {
            FileName = fileName,
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            StandardOutputEncoding = new UTF8Encoding(false),
            StandardErrorEncoding = new UTF8Encoding(false)
        };
        foreach (var arg in arguments) psi.ArgumentList.Add(arg);

        using var process = new Process { StartInfo = psi };
        if (!process.Start())
            throw new InvalidOperationException($"无法启动进程: {fileName}");

        var stdout = process.StandardOutput.ReadToEndAsync();
        var stderr = process.StandardError.ReadToEndAsync();
        var limit = timeout ?? TimeSpan.FromMinutes(2);
        if (!process.WaitForExit((int)limit.TotalMilliseconds))
        {
            try { process.Kill(entireProcessTree: true); } catch { }
            throw new TimeoutException($"{fileName} 执行超时（{limit.TotalSeconds:0} 秒）");
        }

        Task.WaitAll(new Task[] { stdout, stderr }, TimeSpan.FromSeconds(10));
        return new ProcessResult(process.ExitCode, stdout.Result, stderr.Result);
    }
}

public sealed record ProcessResult(int ExitCode, string OutputText, string ErrorText);
