using System.Diagnostics;
using System.Security.Principal;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media.Imaging;
using GamePerfCenter.Helpers;
using GamePerfCenter.Services;

namespace GamePerfCenter;

public partial class App : Application
{
    public static AppServices Services { get; private set; } = null!;
    public static Window? MainWindow { get; private set; }
    public static bool SelfTest { get; private set; }
    public static bool Preview { get; private set; }
    public static bool LangAudit { get; private set; }
    public static bool Shot { get; private set; }

    // 单实例：同一时间只允许一个主界面，避免两份引擎同时写备份与配置。
    // QA 模式（自测 / 预览 / 截图 / 语言检查）不参与，便于与正在运行的主程序并存。
    private static Mutex? _instanceMutex;
    private const string InstanceMutexName = @"Local\GamePerfCenter.SingleInstance";

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
        // async void 事件处理器与非 UI 线程的异常统一留痕，避免只看到进程退出。
        AppDomain.CurrentDomain.UnhandledException += (_, e) =>
            AppLog.Write("AppDomain 未处理异常: " + e.ExceptionObject);
        TaskScheduler.UnobservedTaskException += (_, e) =>
        {
            AppLog.Write("未观察的任务异常: " + e.Exception);
            e.SetObserved();
        };
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        var cmd = Environment.GetCommandLineArgs();
        var noElevate = cmd.Any(a => a.Equals("--no-elevate", StringComparison.OrdinalIgnoreCase));
        SelfTest = cmd.Any(a => a.Equals("--self-test", StringComparison.OrdinalIgnoreCase));
        Preview = cmd.Any(a => a.Equals("--preview", StringComparison.OrdinalIgnoreCase));
        LangAudit = cmd.Any(a => a.Equals("--lang-audit", StringComparison.OrdinalIgnoreCase));
        Shot = cmd.Any(a => a.Equals("--shot", StringComparison.OrdinalIgnoreCase));
        if (!IsElevated() && !noElevate && !SelfTest && !Preview && !LangAudit && !Shot && !Debugger.IsAttached)
        {
            RelaunchElevated();
            return;
        }

        // 提权之后再抢单实例锁：非提权进程只是转发启动参数后退出，不应占用锁。
        var isQaMode = SelfTest || Preview || LangAudit || Shot || Debugger.IsAttached;
        if (!isQaMode && !TryAcquireSingleInstance())
        {
            AppLog.Write("已有实例在运行，本次启动直接退出。");
            Environment.Exit(0);
            return;
        }

        AppPaths.EnsureDirectories();
        ThemeService.RefreshHighContrast();
        Services = new AppServices();
        Localization.Configure(Services.Settings.Language);
        Motion.Configure(Services.Settings.ReduceMotion);
        // 系统“动画效果”在不少游戏机上默认关闭；它不再直接停用应用内反馈，
        // 但写进日志，方便判断“为什么没看到动效”。
        AppLog.Write($"动效配置: 应用内={(Motion.Enabled ? "开" : "关")} 减弱动效={Services.Settings.ReduceMotion} Windows动画={(Motion.SystemEnabled ? "开" : "关")} 提权={IsElevated()}");
        var window = new MainWindow();
        MainWindow = window;
        if (LangAudit)
        {
            _ = RunLanguageAuditAsync(window);
            return;
        }
        if (SelfTest)
        {
            _ = RunSelfTestAsync(window);
            return;
        }
        if (Shot)
        {
            _ = RunShotAsync(window, cmd);
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
            if (secArg is not null && int.TryParse(secArg.Substring("--seconds=".Length), out var parsed))
                seconds = parsed;
            if (seconds <= 0) seconds = 20;

            window.AppWindow.Show(false);
            // 等首屏导航完成后再跳转，否则会被 Nav_Loaded 的默认概览覆盖。
            await Task.Delay(700);
            window.NavigateTo(page);
            await Task.Delay(TimeSpan.FromSeconds(seconds));
        }
        catch (Exception ex)
        {
            AppLog.Write("预览模式失败: " + ex);
        }
        finally
        {
            try { await Services.Engine.DisposeAsync(); } catch { }
            Environment.Exit(0);
        }
    }

    /// <summary>
    /// 语言回归检查：逐页执行 中文 → English → 中文，随后扫描仍为英文译文的文案。
    /// 窗口不激活；结果写入 data/lang-audit.log。
    /// </summary>
    private static async Task RunLanguageAuditAsync(MainWindow window)
    {
        var lines = new List<string>();
        var tags = new[]
        {
            "overview", "items", "driver", "backup", "games",
            "diagnostics", "startup", "log", "settings", "about"
        };
        try
        {
            window.AppWindow.Show(false);
            await Task.Delay(2500);
            foreach (var tag in tags)
            {
                try
                {
                    window.NavigateTo(tag);
                    await Task.Delay(1200);
                    window.SwitchLanguageForAudit("en");
                    await Task.Delay(700);
                    // 对照组：英文模式下应当能扫出大量英文文案，用来确认检测器本身有效。
                    var control = Localization.AuditEnglish(window.AuditRoot, tag + "/en").Count;
                    // 反向检查：英文模式下仍显示中文的界面文案（运行数据不会命中词表）。
                    var untranslated = Localization.AuditUntranslated(window.AuditRoot, tag + "/en");
                    if (tag == "overview")
                    {
                        // 复现真实路径：英文模式下产生带参数的状态与通知，再切回中文。
                        Services.State.SetStatusFormat("已加载 {0} 个优化项 · {1}", 32, "AUDIT");
                        window.ShowInfo("刷新完成", "硬件与优化项状态已更新。");
                        await Task.Delay(300);
                    }
                    window.SwitchLanguageForAudit("zh");
                    await Task.Delay(900);
                    var found = Localization.AuditEnglish(window.AuditRoot, tag);
                    lines.Add($"{tag}: {found.Count} leftover(s), " +
                              $"{untranslated.Count} untranslated, en control {control}");
                    lines.AddRange(untranslated);
                    lines.AddRange(found);
                }
                catch (Exception ex)
                {
                    lines.Add($"{tag}: AUDIT FAIL {ex.GetType().Name} {ex.Message}");
                }
            }
        }
        catch (Exception ex)
        {
            lines.Add("lang-audit: FAIL " + ex);
        }
        finally
        {
            try
            {
                var path = Path.Combine(AppPaths.DataDir, "lang-audit.log");
                File.WriteAllLines(path, lines, new System.Text.UTF8Encoding(true));
            }
            catch { }
            try { await Services.Engine.DisposeAsync(); } catch { }
            Environment.Exit(lines.Any(l => l.Contains("UNTRANSLATED")) ||
                             lines.Any(l => l.Contains("leftover(s)") && !l.Contains(" 0 leftover")) ||
                             lines.Any(l => l.Contains("FAIL")) ? 1 : 0);
        }
    }

    /// <summary>
    /// 离屏截图：窗口移到屏幕外且不激活，直接把 XAML 树渲染成 BMP，供视觉回归使用。
    /// 启动参数：--shot --no-elevate --page=overview --out=.tmp/shot.bmp
    /// 不抢前台焦点、不移动鼠标、不在屏幕上留下窗口。
    /// </summary>
    private static async Task RunShotAsync(MainWindow window, string[] cmd)
    {
        var page = cmd.FirstOrDefault(a => a.StartsWith("--page=", StringComparison.OrdinalIgnoreCase))?
            .Substring("--page=".Length) ?? "overview";
        var outArg = cmd.FirstOrDefault(a => a.StartsWith("--out=", StringComparison.OrdinalIgnoreCase))?
            .Substring("--out=".Length) ?? Path.Combine(".tmp", "shot.bmp");
        var theme = cmd.FirstOrDefault(a => a.StartsWith("--theme=", StringComparison.OrdinalIgnoreCase))?
            .Substring("--theme=".Length).ToLowerInvariant();
#if DEBUG
        var expandArg = cmd.FirstOrDefault(a => a.StartsWith("--expand=", StringComparison.OrdinalIgnoreCase))?
            .Substring("--expand=".Length);
        var widthArg = cmd.FirstOrDefault(a => a.StartsWith("--width=", StringComparison.OrdinalIgnoreCase))?
            .Substring("--width=".Length);
#endif
        var path = Path.GetFullPath(outArg);

        try
        {
            // 只在内存里覆盖主题，不写回设置文件。
            if (theme is "dark" or "light" or "system")
            {
                Services.Settings.Theme = theme;
                window.RefreshTheme();
            }

            window.AppWindow.Move(new Windows.Graphics.PointInt32(-4000, -4000));
            window.AppWindow.Show(false);
            await Task.Delay(4200);
#if DEBUG
            // QA：按 DIP 指定窗口宽度，用于核对宽/窄断点。窗口加载后再取缩放比，避免拿到 1.0。
            if (int.TryParse(widthArg, out var requestedWidth) && requestedWidth >= 640)
            {
                var scale = (window.Content as FrameworkElement)?.XamlRoot?.RasterizationScale ?? 1;
                window.AppWindow.Resize(new Windows.Graphics.SizeInt32(
                    (int)(requestedWidth * scale), (int)(900 * scale)));
                await Task.Delay(900);
            }
#endif
            window.NavigateTo(page);
            await Task.Delay(2500);
#if DEBUG
            // QA：在离屏窗口里展开指定行，便于检查展开态渲染，不需要真实点击。
            if (int.TryParse(expandArg, out var expandIndex) &&
                window.CurrentPage is Pages.ItemsPage itemsPage)
            {
                itemsPage.QaExpand(expandIndex);
                await Task.Delay(900);
            }

            // QA：离屏窗口里直接展开待优化清单，用于核对悬浮态排版。
            if (cmd.Any(a => string.Equals(a, "--tip", StringComparison.OrdinalIgnoreCase)))
            {
                window.QaShowPendingTip();
                await Task.Delay(300);
            }

            // QA：模拟勾选一行，核对“只更新计数、不重建列表”。
            var checkArg = cmd.FirstOrDefault(a => a.StartsWith("--check=", StringComparison.OrdinalIgnoreCase))?
                .Substring("--check=".Length);
            if (int.TryParse(checkArg, out var checkIndex) &&
                window.CurrentPage is Pages.ItemsPage checkPage)
            {
                checkPage.QaCheck(checkIndex);
                await Task.Delay(300);
            }

            // QA：在页面已加载后切换主题，核对颜色绑定与列表状态是否保持。
            if (cmd.Any(a => string.Equals(a, "--theme-switch", StringComparison.OrdinalIgnoreCase)))
            {
                Services.Settings.Theme = Services.Settings.Theme == "light" ? "dark" : "light";
                window.RefreshTheme();
                await Task.Delay(700);
            }
#endif

            if (window.Content is not UIElement root)
            {
                throw new InvalidOperationException("窗口内容尚未就绪");
            }

            var bitmap = new RenderTargetBitmap();
            await bitmap.RenderAsync(root);
            var buffer = await bitmap.GetPixelsAsync();
            var pixels = new byte[(int)buffer.Length];
            using (var reader = Windows.Storage.Streams.DataReader.FromBuffer(buffer))
            {
                reader.ReadBytes(pixels);
            }
            // BMP 阅读器可能按 alpha 混合；统一置为不透明，保证截图所见即界面。
            for (var i = 3; i < pixels.Length; i += 4) pixels[i] = 255;

            var dir = Path.GetDirectoryName(path);
            if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
            WriteBmp(path, pixels, bitmap.PixelWidth, bitmap.PixelHeight);
            AppLog.Write($"离屏截图: {page} -> {path} ({bitmap.PixelWidth}x{bitmap.PixelHeight})");
        }
        catch (Exception ex)
        {
            AppLog.Write("离屏截图失败: " + ex);
        }
        finally
        {
            try { await Services.Engine.DisposeAsync(); } catch { }
            Environment.Exit(0);
        }
    }

    private static void WriteBmp(string path, byte[] bgra, int width, int height)
    {
        var stride = width * 4;
        using var stream = File.Create(path);
        using var writer = new BinaryWriter(stream);
        writer.Write((ushort)0x4D42);
        writer.Write(54 + stride * height);
        writer.Write((ushort)0);
        writer.Write((ushort)0);
        writer.Write(54);
        writer.Write(40);
        writer.Write(width);
        writer.Write(height);
        writer.Write((ushort)1);
        writer.Write((ushort)32);
        writer.Write(0);
        writer.Write(stride * height);
        writer.Write(2835);
        writer.Write(2835);
        writer.Write(0);
        writer.Write(0);
        for (var y = height - 1; y >= 0; y--)
        {
            writer.Write(bgra, y * stride, stride);
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
            // 以“显示但不激活”的方式打开窗口，移到屏幕外，避免自测时抢走前台焦点或出现在画面上。
            window.AppWindow.Move(new Windows.Graphics.PointInt32(-4000, -4000));
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
            try { await Services.Engine.DisposeAsync(); } catch { }
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

    private static bool TryAcquireSingleInstance()
    {
        try
        {
            _instanceMutex = new Mutex(false, InstanceMutexName);
            // 前一个实例异常退出时会抛 AbandonedMutexException，此时锁已归当前进程。
            if (_instanceMutex.WaitOne(0)) return true;
            _instanceMutex.Dispose();
            _instanceMutex = null;
            return false;
        }
        catch (AbandonedMutexException)
        {
            return true;
        }
        catch (Exception ex)
        {
            // 拿不到锁不影响主流程，记录后继续，避免因系统对象异常导致无法启动。
            AppLog.Write("单实例锁初始化失败: " + ex.Message);
            _instanceMutex?.Dispose();
            _instanceMutex = null;
            return true;
        }
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
