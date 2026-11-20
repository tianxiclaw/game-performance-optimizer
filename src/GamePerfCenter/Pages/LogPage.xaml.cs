using System.Diagnostics;
using System.Text;
using GamePerfCenter.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace GamePerfCenter.Pages;

public sealed partial class LogPage : Page, IThemeAware
{
    private const int TailLines = 900;
    private const string EmptyPlaceholder = "暂无日志。执行优化、恢复或诊断后会在此显示引擎输出。";
    private const string NoMatchPlaceholder = "没有匹配当前筛选的日志行。换个关键词或关闭“仅看失败”。";

    private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromSeconds(3) };
    private readonly List<string> _lines = new();
    private bool _loaded;
    private bool _cleared;
    private bool _clearing;
    private bool _onlyErrors;
    private string _query = "";
    private string _lastText = "";

    public LogPage()
    {
        InitializeComponent();
        _timer.Tick += (_, _) => Reload();
        Loaded += OnLoaded;
        Unloaded += OnUnloaded;
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        if (!_loaded)
        {
            _loaded = true;
            LogPathText.Text = AppPaths.AppLogPath;
            ToolTipService.SetToolTip(LogPathText, AppPaths.AppLogPath);
        }
        Reload();
        if (AutoRefresh.IsOn) _timer.Start();
    }

    private void OnUnloaded(object sender, RoutedEventArgs e) => _timer.Stop();

    private void Reload()
    {
        try
        {
            if (!File.Exists(AppPaths.AppLogPath))
            {
                _lines.Clear();
                Render();
                LogMetaText.Text = _cleared ? "日志已清理 · 新的记录会自动写入" : "日志文件尚未生成";
                return;
            }

            _cleared = false;
            var info = new FileInfo(AppPaths.AppLogPath);
            _lines.Clear();
            _lines.AddRange(ReadTail(AppPaths.AppLogPath, TailLines));
            Render();
            LogMetaText.Text = $"{info.Length / 1024.0:0.0} KB · 更新于 {info.LastWriteTime:MM-dd HH:mm:ss}"
                               + (AutoRefresh.IsOn ? " · 每 3 秒刷新" : " · 已暂停自动刷新");
        }
        catch (Exception ex)
        {
            LogMetaText.Text = "读取日志失败: " + ex.Message;
        }
    }

    /// <summary>按关键词与“仅看失败”过滤当前缓存的日志行，不重复读盘。</summary>
    private void Render()
    {
        if (LogText is null || LogCount is null) return;

        var filtering = _query.Length > 0 || _onlyErrors;
        IEnumerable<string> view = _lines;
        if (_query.Length > 0)
            view = view.Where(line => line.Contains(_query, StringComparison.OrdinalIgnoreCase));
        if (_onlyErrors)
            view = view.Where(IsFailure);

        var shown = view.ToList();
        LogText.PlaceholderText = filtering && shown.Count == 0 ? NoMatchPlaceholder : EmptyPlaceholder;

        var text = string.Join(Environment.NewLine, shown);
        if (text != _lastText)
        {
            LogText.Text = text;
            _lastText = text;
            if (text.Length > 0)
            {
                LogText.SelectionStart = LogText.Text.Length;
                LogText.Select(LogText.Text.Length, 0);
            }
        }

        LogCount.Text = filtering
            ? $"显示 {shown.Count} / {_lines.Count} 行"
            : _lines.Count == 0 ? "暂无记录" : $"共 {_lines.Count} 行";
    }

    private static bool IsFailure(string line) =>
        line.Contains("失败", StringComparison.Ordinal)
        || line.Contains("错误", StringComparison.Ordinal)
        || line.Contains("异常", StringComparison.Ordinal)
        || line.Contains("error", StringComparison.OrdinalIgnoreCase)
        || line.Contains("fail", StringComparison.OrdinalIgnoreCase)
        || line.Contains("exception", StringComparison.OrdinalIgnoreCase);

    private static List<string> ReadTail(string path, int count)
    {
        try
        {
            using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
            using var reader = new StreamReader(stream, Encoding.UTF8);
            var queue = new Queue<string>();
            while (reader.ReadLine() is { } line)
            {
                queue.Enqueue(line);
                if (queue.Count > count) queue.Dequeue();
            }
            return queue.ToList();
        }
        catch { return new List<string>(); }
    }

    private void Refresh_Click(object sender, RoutedEventArgs e) => Reload();

    private void AutoRefresh_Toggled(object sender, RoutedEventArgs e)
    {
        if (AutoRefresh is null || LogText is null) return;
        if (AutoRefresh.IsOn) _timer.Start();
        else _timer.Stop();
        Reload();
    }

    private void LogSearch_TextChanged(object sender, TextChangedEventArgs e)
    {
        if (LogSearch is null) return;
        _query = LogSearch.Text?.Trim() ?? "";
        Render();
    }

    private void OnlyErrors_Toggled(object sender, RoutedEventArgs e)
    {
        if (OnlyErrors is null) return;
        _onlyErrors = OnlyErrors.IsOn;
        Render();
    }

    private void OpenFolder_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            Directory.CreateDirectory(AppPaths.DataDir);
            Process.Start(new ProcessStartInfo
            {
                FileName = "explorer.exe",
                Arguments = $"\"{AppPaths.DataDir}\"",
                UseShellExecute = true
            });
        }
        catch { }
    }

    private async void Clear_Click(object sender, RoutedEventArgs e)
    {
        if (_clearing) return;
        _clearing = true;
        try
        {
            var dialog = new ContentDialog
            {
                XamlRoot = XamlRoot,
                Title = "清理运行日志？",
                Content = "将删除 data 目录下的 winui.log 与 winui.log.1，清理后无法恢复。备份、游戏库与优化记录不受影响。",
                PrimaryButtonText = "清理日志",
                CloseButtonText = "取消",
                DefaultButton = ContentDialogButton.Close
            };

            if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;

            if (!AppLog.Clear())
            {
                LogMetaText.Text = "清理失败：日志文件可能被占用，请稍后重试";
                return;
            }

            _cleared = true;
            _lines.Clear();
            // 不要提前清空 _lastText：Render 依赖它与旧文本的差异来刷新文本框，
            // 提前置空会让 text == _lastText 成立，界面继续显示清理前的日志。
            Render();
            LogMetaText.Text = "日志已清理 · 新的记录会自动写入";
        }
        finally
        {
            _clearing = false;
        }
    }

    private void Copy_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            if (_lastText.Length == 0)
            {
                LogMetaText.Text = "当前视图没有内容可复制";
                return;
            }

            var package = new Windows.ApplicationModel.DataTransfer.DataPackage();
            package.SetText(_lastText);
            Windows.ApplicationModel.DataTransfer.Clipboard.SetContent(package);
            LogMetaText.Text = _onlyErrors || _query.Length > 0
                ? "已复制当前筛选视图"
                : "日志已复制到剪贴板";
        }
        catch (Exception ex)
        {
            LogMetaText.Text = "复制失败: " + ex.Message;
        }
    }

    public void OnThemeChanged() { }
}