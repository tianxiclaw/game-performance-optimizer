using System.Diagnostics;
using System.Text;
using GamePerfCenter.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace GamePerfCenter.Pages;

public sealed partial class LogPage : Page, IThemeAware
{
    private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromSeconds(3) };
    private bool _loaded;
    private bool _cleared;
    private bool _clearing;
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
                LogText.Text = "";
                _lastText = "";
                LogMetaText.Text = _cleared ? "日志已清理 · 新的记录会自动写入" : "日志文件尚未生成";
                return;
            }

            _cleared = false;
            var info = new FileInfo(AppPaths.AppLogPath);
            var lines = ReadTail(AppPaths.AppLogPath, 900);
            var text = string.Join(Environment.NewLine, lines);
            if (text != _lastText)
            {
                LogText.Text = text;
                _lastText = text;
                LogText.SelectionStart = LogText.Text.Length;
                LogText.Select(LogText.Text.Length, 0);
            }
            LogMetaText.Text = $"{info.Length / 1024.0:0.0} KB · 更新于 {info.LastWriteTime:MM-dd HH:mm:ss}"
                               + (AutoRefresh.IsOn ? " · 每 3 秒刷新" : " · 已暂停自动刷新");
        }
        catch (Exception ex)
        {
            LogMetaText.Text = "读取日志失败: " + ex.Message;
        }
    }

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
            _lastText = "";
            LogText.Text = "";
            Reload();
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
            var package = new Windows.ApplicationModel.DataTransfer.DataPackage();
            package.SetText(LogText.Text ?? "");
            Windows.ApplicationModel.DataTransfer.Clipboard.SetContent(package);
            LogMetaText.Text = "日志已复制到剪贴板";
        }
        catch (Exception ex)
        {
            LogMetaText.Text = "复制失败: " + ex.Message;
        }
    }

    public void OnThemeChanged() { }
}
