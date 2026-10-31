using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Text.Json;
using GamePerfCenter.Models;
using GamePerfCenter.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace GamePerfCenter.Pages;

public sealed partial class BackupPage : Page, IThemeAware
{
    private readonly ObservableCollection<BackupInfo> _backups = new();
    private bool _loaded;

    public BackupPage()
    {
        InitializeComponent();
        BackupList.ItemsSource = _backups;
        Loaded += OnLoaded;
    }

    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        if (_loaded) return;
        _loaded = true;
        await LoadAsync();
    }

    private async Task LoadAsync()
    {
        try
        {
            var list = await App.Services.State.GetBackupsAsync();
            _backups.Clear();
            foreach (var backup in list) _backups.Add(backup);
            EmptyHint.Visibility = _backups.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
            UpdateLastApply();
        }
        catch (Exception ex)
        {
            ShowInfo("读取备份失败", ex.Message, InfoBarSeverity.Error);
        }
    }

    private void UpdateLastApply()
    {
        var last = App.Services.State.Snapshot?.LastApply;
        if (last is null || string.IsNullOrEmpty(last.Time))
        {
            LastApplyTime.Text = "暂无记录";
            LastApplySummary.Text = "应用优化后这里会显示本次改动数量与结果。";
            LastBackupName.Text = "备份文件：--";
            return;
        }

        LastApplyTime.Text = last.Time;
        var errors = last.Errors?.Count ?? 0;
        LastApplySummary.Text = $"本次处理 {last.Items?.Count ?? 0} 项，失败 {errors} 项"
                                + (string.IsNullOrEmpty(last.Result) ? "" : $" · {last.Result}");
        LastBackupName.Text = "备份文件：" + (string.IsNullOrEmpty(last.Backup) ? "未生成" : Path.GetFileName(last.Backup));
    }

    private async void Refresh_Click(object sender, RoutedEventArgs e) => await LoadAsync();

    private void OpenFolder_Click(object sender, RoutedEventArgs e) => OpenFolder(AppPaths.BackupDir);

    private void Reveal_Click(object sender, RoutedEventArgs e)
    {
        if (((FrameworkElement)sender).DataContext is not BackupInfo backup) return;
        try
        {
            if (!string.IsNullOrEmpty(backup.Path) && File.Exists(backup.Path))
            {
                Process.Start(new ProcessStartInfo
                {
                    FileName = "explorer.exe",
                    Arguments = $"/select,\"{backup.Path}\"",
                    UseShellExecute = true
                });
            }
            else
            {
                OpenFolder(AppPaths.BackupDir);
            }
        }
        catch (Exception ex)
        {
            ShowInfo("无法定位备份", ex.Message, InfoBarSeverity.Error);
        }
    }

    private async void Restore_Click(object sender, RoutedEventArgs e)
    {
        if (((FrameworkElement)sender).DataContext is not BackupInfo backup) return;
        if (!await ConfirmAsync("恢复这份备份？",
                $"将把 {backup.Time} 的 {backup.RecordsText} 恢复为原值。\n\n部分项目可能需要重启后生效。",
                "恢复", "取消", ContentDialogButton.Close))
            return;

        try
        {
            App.Services.State.SetStatus("正在恢复备份...");
            var result = await App.Services.State.RestoreAsync(backup.Path);
            ShowInfo("恢复完成", Summarize(result), InfoBarSeverity.Success);
            await App.Services.State.EnsureSnapshotAsync(force: true);
            await LoadAsync();
        }
        catch (Exception ex)
        {
            ShowInfo("恢复失败", ex.Message, InfoBarSeverity.Error);
        }
        finally
        {
            App.Services.State.SetStatus("就绪");
        }
    }

    private async void RestoreAll_Click(object sender, RoutedEventArgs e)
    {
        if (!await ConfirmAsync("恢复全部改动？",
                "将按备份记录把所有已应用的优化项恢复为原值。\n\n此操作会影响注册表、服务与电源设置，建议先关闭正在运行的游戏。",
                "全部恢复", "取消", ContentDialogButton.Close))
            return;

        try
        {
            App.Services.State.SetStatus("正在恢复全部改动...");
            var result = await App.Services.State.RestoreAllAsync();
            ShowInfo("恢复完成", Summarize(result), InfoBarSeverity.Success);
            await App.Services.State.EnsureSnapshotAsync(force: true);
            await LoadAsync();
        }
        catch (Exception ex)
        {
            ShowInfo("恢复失败", ex.Message, InfoBarSeverity.Error);
        }
        finally
        {
            App.Services.State.SetStatus("就绪");
        }
    }

    private async void RestorePoint_Click(object sender, RoutedEventArgs e)
    {
        if (!await ConfirmAsync("创建系统还原点？",
                "将通过系统还原点功能记录当前系统状态，通常需要 1-3 分钟。\n\n若系统已关闭保护，可能创建失败。",
                "创建", "取消", ContentDialogButton.Close))
            return;

        try
        {
            App.Services.State.SetStatus("正在创建系统还原点...");
            var result = await App.Services.State.CreateRestorePointAsync();
            var ok = result.TryGetProperty("Ok", out var okEl) && okEl.ValueKind == JsonValueKind.True;
            var message = result.TryGetProperty("Message", out var msgEl) ? msgEl.ToString() : "";
            ShowInfo(ok ? "还原点已创建" : "未能创建还原点",
                string.IsNullOrEmpty(message) ? "系统已记录当前状态。" : message,
                ok ? InfoBarSeverity.Success : InfoBarSeverity.Warning);
        }
        catch (Exception ex)
        {
            ShowInfo("创建还原点失败", ex.Message, InfoBarSeverity.Error);
        }
        finally
        {
            App.Services.State.SetStatus("就绪");
        }
    }

    private static string Summarize(JsonElement result)
    {
        var ok = ReadInt(result, "Ok");
        var fail = ReadInt(result, "Fail");
        return fail == 0 ? $"成功恢复 {ok} 项。" : $"成功 {ok} 项，失败 {fail} 项，请查看运行日志。";
    }

    private static int ReadInt(JsonElement element, string name)
    {
        if (!element.TryGetProperty(name, out var value)) return 0;
        if (value.ValueKind == JsonValueKind.Number) return value.TryGetInt32(out var n) ? n : 0;
        return int.TryParse(value.ToString(), out var parsed) ? parsed : 0;
    }

    private static void OpenFolder(string path)
    {
        try
        {
            Directory.CreateDirectory(path);
            Process.Start(new ProcessStartInfo { FileName = "explorer.exe", Arguments = $"\"{path}\"", UseShellExecute = true });
        }
        catch { }
    }

    private async Task<bool> ConfirmAsync(string title, string message, string primary, string close,
        ContentDialogButton defaultButton)
    {
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = title,
            Content = new TextBlock { Text = message, TextWrapping = TextWrapping.Wrap, LineHeight = 22 },
            PrimaryButtonText = primary,
            CloseButtonText = close,
            DefaultButton = defaultButton
        };
        return await dialog.ShowAsync() == ContentDialogResult.Primary;
    }

    private void ShowInfo(string title, string message, InfoBarSeverity severity)
    {
        PageInfo.Title = title;
        PageInfo.Message = message;
        PageInfo.Severity = severity;
        PageInfo.IsOpen = true;
    }

    public void OnThemeChanged() { }
}
