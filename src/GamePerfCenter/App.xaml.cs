using System.Diagnostics;
using System.Security.Principal;
using Microsoft.UI.Xaml;
using GamePerfCenter.Services;

namespace GamePerfCenter;

public partial class App : Application
{
    public static AppServices Services { get; private set; } = null!;
    public static Window? MainWindow { get; private set; }
    public static bool SelfTest { get; private set; }
    public static bool Preview { get; private set; }

    public App()
    {
        InitializeComponent();
        UnhandledException += (_, e) =>
        {
            AppLog.Write("未处理异常: " + e.Exception);
            try
            {
                var path = Path.Combine(AppPaths.DataDir, "crash.log");
                Directory.CreateDirectory(AppPaths.DataDir);
                File.AppendAllText(path, $"{DateTime.Now:O} {e.Exception}{Environment.NewLine}");
            }
            catch { }
        };
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        var cmd = Environment.GetCommandLineArgs();
        var noElevate = cmd.Any(a => a.Equals("--no-elevate", StringComparison.OrdinalIgnoreCase));
        SelfTest = cmd.Any(a => a.Equals("--self-test", StringComparison.OrdinalIgnoreCase));
        Preview = cmd.Any(a => a.Equals("--preview", StringComparison.OrdinalIgnoreCase));
        if (!IsElevated() && !noElevate && !SelfTest && !Preview && !Debugger.IsAttached)
        {
            RelaunchElevated();
            return;
        }

        AppPaths.EnsureDirectories();
        Services = new AppServices();
        var window = new MainWindow();
        MainWindow = window;
        if (SelfTest)
        {
            _ = RunSelfTestAsync(window);
            return;
        }
        if (Preview)
        {
            _ = RunPreviewAsync(window, cmd);
            return;
        }
        window.Activate();
    }

    /// <summary>
    /// 预览模式：窗口显示但不激活，适合截图与视觉检查；默认 20 秒后自动退出。
    /// 参数：--preview --no-elevate --page=items --seconds=20
    /// </summary>
    private static async Task RunPreviewAsync(MainWindow window, string[] cmd)
    {
        try
        {
            var page = cmd.FirstOrDefault(a => a.StartsWith("--page=", StringComparison.OrdinalIgnoreCase))?
                .Substring("--page=".Length) ?? "overview";
            var seconds = 20;
            var secArg = cmd.FirstOrDefault(a => a.StartsWith("--seconds=", StringComparison.OrdinalIgnoreCase));
            if (secArg is not null) int.TryParse(secArg.Substring("--seconds=".Length), out seconds);
            if (seconds <= 0) seconds = 20;

            window.AppWindow.Show(false);
            window.NavigateTo(page);
            await Task.Delay(TimeSpan.FromSeconds(seconds));
        }
        catch (Exception ex)
        {
            AppLog.Write("预览模式失败: " + ex);
        }
        finally
        {
            try { _ = Services.Engine.DisposeAsync(); } catch { }
            Environment.Exit(0);
        }
    }

    /// <summary>
    /// 无窗口激活的自检模式：不抢前台焦点，逐个实例化页面并记录 XAML / 绑定异常。
    /// 启动参数：--self-test --no-elevate
    /// </summary>
    private static async Task RunSelfTestAsync(MainWindow window)
    {
        var lines = new List<string>();
        var tags = new[]
        {
            "overview", "items", "driver", "backup", "games",
            "diagnostics", "startup", "log", "settings", "about"
        };
        try
        {
            // 以“显示但不激活”的方式打开窗口，避免自测时抢走前台焦点。
            window.AppWindow.Show(false);
            await Task.Delay(2500);
            foreach (var tag in tags)
            {
                try
                {
                    window.NavigateTo(tag);
                    await Task.Delay(900);
                    lines.Add($"{tag}: ok");
                }
                catch (Exception ex)
                {
                    lines.Add($"{tag}: FAIL {ex.GetType().Name} {ex.Message}");
                }
            }
        }
        catch (Exception ex)
        {
            lines.Add("selftest: FAIL " + ex);
        }
        finally
        {
            try
            {
                var path = Path.Combine(AppPaths.DataDir, "selftest.log");
                File.WriteAllLines(path, lines, new System.Text.UTF8Encoding(true));
            }
            catch { }
            try { _ = Services.Engine.DisposeAsync(); } catch { }
            Environment.Exit(lines.Any(l => l.Contains("FAIL")) ? 1 : 0);
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

    private static void RelaunchElevated()
    {
        try
        {
            var exe = Environment.ProcessPath;
            if (string.IsNullOrEmpty(exe)) return;
            var psi = new ProcessStartInfo
            {
                FileName = exe,
                UseShellExecute = true,
                Verb = "runas",
                WorkingDirectory = AppPaths.BaseDir
            };
            Process.Start(psi);
        }
        catch (Exception ex)
        {
            AppLog.Write("提权失败: " + ex.Message);
        }
        Environment.Exit(0);
    }
}
