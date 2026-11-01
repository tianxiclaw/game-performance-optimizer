using System.Diagnostics;
using System.Text;

namespace GamePerfCenter.Core.Infrastructure;

/// <summary>
/// 以 UTF-8 控制台代码页运行 pnputil。
/// pnputil 默认按控制台代码页输出，直接重定向会得到 GBK 字节；
/// 先 chcp 65001 再执行，才能稳定拿到 UTF-8 中文。
/// </summary>
public static class PnPUtilRunner
{
    private static readonly TimeSpan DefaultTimeout = TimeSpan.FromSeconds(45);

    public static IReadOnlyList<string> Run(string arguments, TimeSpan? timeout = null)
    {
        var result = Execute(arguments, timeout);
        if (result.ExitCode != 0 && result.Lines.Count == 0)
            throw new InvalidOperationException(
                $"pnputil {arguments} 退出码 {result.ExitCode}: {result.ErrorText.Trim()}");
        return result.Lines;
    }

    /// <summary>
    /// 执行 pnputil 并保留退出码与错误输出，供驱动安装/清理判断结果使用。
    /// </summary>
    public static PnPUtilResult Execute(string arguments, TimeSpan? timeout = null)
    {
        var comspec = Environment.GetEnvironmentVariable("COMSPEC");
        if (string.IsNullOrWhiteSpace(comspec)) comspec = "cmd.exe";

        var psi = new ProcessStartInfo
        {
            FileName = comspec,
            Arguments = "/d /c chcp 65001>nul & pnputil.exe " + arguments,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8
        };

        using var process = new Process { StartInfo = psi };
        process.Start();

        var stdoutTask = process.StandardOutput.ReadToEndAsync();
        var stderrTask = process.StandardError.ReadToEndAsync();

        var limit = timeout ?? DefaultTimeout;
        if (!process.WaitForExit((int)limit.TotalMilliseconds))
        {
            try { process.Kill(entireProcessTree: true); } catch { }
            throw new TimeoutException($"pnputil {arguments} 超过 {limit.TotalSeconds:0} 秒未返回");
        }

        var stdout = stdoutTask.GetAwaiter().GetResult();
        var stderr = stderrTask.GetAwaiter().GetResult();
        var lines = SplitLines(stdout);
        if (lines.Count == 0) lines = SplitLines(stderr);
        return new PnPUtilResult(process.ExitCode, lines, stderr);
    }

    private static List<string> SplitLines(string text)
    {
        var lines = new List<string>();
        using var reader = new StringReader(text ?? "");
        while (reader.ReadLine() is { } line) lines.Add(line);
        return lines;
    }
}

public sealed record PnPUtilResult(int ExitCode, IReadOnlyList<string> Lines, string ErrorText);
