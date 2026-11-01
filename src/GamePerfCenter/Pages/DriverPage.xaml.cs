using System.Collections.ObjectModel;
using System.Diagnostics;
using GamePerfCenter.Core.Models;
using GamePerfCenter.Models;
using GamePerfCenter.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace GamePerfCenter.Pages;

public sealed partial class DriverPage : Page, IThemeAware
{
    private readonly ObservableCollection<DriverInventoryRow> _devices = new();
    private readonly ObservableCollection<DriverChange> _changes = new();
    private readonly ObservableCollection<DriverHistRow> _history = new();
    private bool _loaded;
    private bool _operationBusy;

    public DriverPage()
    {
        InitializeComponent();
        DeviceList.ItemsSource = _devices;
        ChangeList.ItemsSource = _changes;
        HistoryList.ItemsSource = _history;
        Loaded += OnLoaded;
    }

    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        if (_loaded) return;
        _loaded = true;
        await LoadAsync(false, true);
    }

    private async Task LoadAsync(bool includeUpdates, bool force)
    {
        SetBusy(true, includeUpdates ? "正在查询 Windows Update…" : "正在扫描本机驱动…");
        try
        {
            var inventory = await Task.Run(() =>
                App.Services.DriverInventory.Scan(includeUpdates, force));

            _devices.Clear();
            foreach (var device in inventory.Devices) _devices.Add(ToRow(device));

            UpdateSummary(inventory);
            DeviceEmpty.Visibility = _devices.Count == 0 ? Visibility.Visible : Visibility.Collapsed;

            if (includeUpdates && inventory.UpdateError is not null)
                ShowInfo("更新检测失败", inventory.UpdateError, InfoBarSeverity.Warning);
        }
        catch (Exception ex)
        {
            ShowInfo("读取驱动信息失败", ex.Message, InfoBarSeverity.Error);
        }
        finally
        {
            SetBusy(false, "");
        }

        await LoadHistoryAsync();
    }

    private void UpdateSummary(DriverInventory inventory)
    {
        var summary = inventory.Summary;
        StatDevices.Text = summary.DeviceCount.ToString();
        StatUpdates.Text = summary.UpdateCount.ToString();
        StatIssues.Text = summary.IssueCount.ToString();
        StatPackages.Text = summary.PackageCount.ToString();
        DeviceCountText.Text = $"共 {summary.DeviceCount} 个设备 · 驱动包 {summary.PackageCount} 个";

        var categories = summary.CategoryCounts
            .Where(pair => pair.Key != "全部")
            .Select(pair => $"{pair.Key} {pair.Value}");
        CategoryText.Text = string.Join(" · ", categories);

        var wuState = inventory.UpdateError is not null
            ? "Windows Update 检测失败"
            : inventory.WuChecked ? "已检测 Windows Update" : "未检测 Windows Update";
        ScanTimeText.Text = $"扫描于 {inventory.ScannedAt:yyyy/M/d HH:mm:ss} · {wuState}";
    }

    private static DriverInventoryRow ToRow(DriverDeviceInfo device)
    {
        var vendor = DriverService.DetectVendorName(device.Name, device.DeviceId);
        var canOpenVendor = vendor is "NVIDIA" or "AMD" or "INTEL" or "QUALCOMM";
        var level = !device.StatusOk ? "red"
            : device.UpdateCount > 0 ? "cyan"
            : device.OldCount > 0 ? "yellow"
            : "green";
        var status = !device.StatusOk
            ? device.StatusText
            : device.OldCount > 0 ? "有旧驱动包" : "正常";

        return new DriverInventoryRow
        {
            Name = device.Name,
            Category = device.Category,
            ClassName = device.Class,
            DeviceId = device.DeviceId,
            InfName = device.InfName,
            Version = device.Version,
            Provider = device.Provider,
            Date = device.Date,
            StatusText = status,
            StatusOk = device.StatusOk,
            UpdateCount = device.UpdateCount,
            OldCount = device.OldCount,
            PackageCount = device.Packages.Count,
            FlagsText = string.Join(" · ", device.Flags),
            Level = level,
            Vendor = vendor,
            CanOpenVendor = canOpenVendor,
            Device = device
        };
    }

    private async Task LoadHistoryAsync()
    {
        try
        {
            var history = await App.Services.State.GetDriverHistoryAsync();
            _changes.Clear();
            foreach (var change in history.LastChanges.Take(8)) _changes.Add(change);
            _history.Clear();
            foreach (var entry in history.Devices.Values
                         .Select(e => new DriverHistRow
                         {
                             Name = e.Name,
                             Class = e.Class,
                             Inf = e.Inf,
                             Version = e.Version,
                             Date = e.Date,
                             At = e.At
                         })
                         .OrderByDescending(e => e.At))
            {
                _history.Add(entry);
            }
        }
        catch (Exception ex)
        {
            AppLog.Write("读取驱动历史失败: " + ex.Message);
        }

        ChangeEmpty.Visibility = _changes.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        HistoryEmpty.Visibility = _history.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    private async void Refresh_Click(object sender, RoutedEventArgs e) => await LoadAsync(false, true);

    private async void CheckUpdates_Click(object sender, RoutedEventArgs e) => await LoadAsync(true, true);

    private void OpenDeviceManager_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = "devmgmt.msc",
                UseShellExecute = true
            });
        }
        catch (Exception ex)
        {
            ShowInfo("无法打开设备管理器", ex.Message, InfoBarSeverity.Error);
        }
    }

    private async void Manage_Click(object sender, RoutedEventArgs e)
    {
        if (_operationBusy) return;
        if (((FrameworkElement)sender).DataContext is not DriverInventoryRow row) return;
        var device = row.Device;
        if (device is null)
        {
            ShowInfo("无法管理该设备", "设备信息已过期，请先刷新本地列表。", InfoBarSeverity.Warning);
            return;
        }

        var candidates = device.Packages
            .Where(package => !package.InUse)
            .OrderByDescending(package => package.Date)
            .ThenByDescending(package => package.Version)
            .ToList();

        var actions = new RadioButtons { Header = "选择操作" };
        actions.Items.Add("重新绑定当前驱动");
        actions.Items.Add("切换到仓库中的其它驱动包");
        actions.Items.Add("清理仓库中的旧驱动包");
        actions.SelectedIndex = 0;

        var packages = new ComboBox
        {
            Header = "驱动包",
            HorizontalAlignment = HorizontalAlignment.Stretch,
            IsEnabled = false,
            PlaceholderText = candidates.Count == 0 ? "仓库中没有其它可用驱动包" : "选择一个驱动包"
        };
        foreach (var package in candidates) packages.Items.Add(PackageLabel(package));

        var summary = new TextBlock
        {
            Text = $"{row.Name}\n当前 {ValueOrUnknown(row.Version)} · {ValueOrUnknown(row.InfName)}" +
                   $"\n仓库匹配 {device.Packages.Count} 个驱动包，可切换或清理 {candidates.Count} 个",
            TextWrapping = TextWrapping.Wrap,
            LineHeight = 21
        };
        var note = new TextBlock
        {
            Text = "切换或清理会让设备短暂重新枚举，屏幕可能闪一下。操作前后会自动恢复被改动的音频静音状态。",
            TextWrapping = TextWrapping.Wrap,
            FontSize = 12,
            Opacity = 0.75
        };

        actions.SelectionChanged += (_, _) =>
        {
            var needsPackage = actions.SelectedIndex > 0;
            packages.IsEnabled = needsPackage && candidates.Count > 0;
        };

        var panel = new StackPanel { Spacing = 12 };
        panel.Children.Add(summary);
        panel.Children.Add(actions);
        panel.Children.Add(packages);
        panel.Children.Add(note);

        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = "管理驱动",
            Content = new ScrollViewer { Content = panel, MaxHeight = 460, VerticalScrollBarVisibility = ScrollBarVisibility.Auto },
            PrimaryButtonText = "继续",
            CloseButtonText = "取消",
            DefaultButton = ContentDialogButton.Primary
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;

        var action = actions.SelectedIndex;
        var selected = packages.SelectedIndex >= 0 && packages.SelectedIndex < candidates.Count
            ? candidates[packages.SelectedIndex]
            : null;

        if (action > 0 && selected is null)
        {
            ShowInfo("请选择驱动包", "该操作需要先选择一个仓库中的驱动包。", InfoBarSeverity.Warning);
            return;
        }

        var (title, message, primary, destructive) = action switch
        {
            1 => ("切换驱动包？",
                $"将把“{device.Name}”切换到 {PackageLabel(selected!)}\n\n设备会短暂重新枚举，部分驱动需要重启后生效。",
                "切换", false),
            2 => ("清理旧驱动包？",
                $"将从驱动仓库删除 {PackageLabel(selected!)}\n\n此操作不可撤销，但不会删除当前正在使用的驱动包。",
                "清理", true),
            _ => ("重新绑定当前驱动？",
                $"将使用当前 INF（{ValueOrUnknown(device.InfName)}）重新绑定“{device.Name}”。\n\n设备会短暂重新枚举，部分驱动需要重启后生效。",
                "重新绑定", false)
        };

        if (!await ConfirmAsync(title, message, primary,
                destructive ? ContentDialogButton.Close : ContentDialogButton.Primary))
            return;

        if (!App.Services.DriverOperations.IsElevated)
        {
            ShowInfo("需要管理员权限", "驱动操作需要以管理员身份运行。请关闭应用后使用“以管理员身份运行”重新启动。",
                InfoBarSeverity.Warning);
            return;
        }

        _operationBusy = true;
        SetBusy(true, "正在执行驱动操作...");
        try
        {
            var options = new DriverOperationOptions();
            var result = await Task.Run(() => action switch
            {
                1 => App.Services.DriverOperations.SwitchPackage(device, selected!, options),
                2 => App.Services.DriverOperations.DeletePackage(device, selected!, options),
                _ => App.Services.DriverOperations.RebindCurrent(device, options)
            });

            var text = result.Message;
            if (result.AudioEndpoints > 0)
                text += $"\n音频端点 {result.AudioEndpoints} 个，已恢复静音状态 {result.AudioRestored} 个。";
            if (result.RebootRecommended && result.Ok)
                text += "\n部分设备需要重启后才会完全生效。";

            ShowInfo(result.Ok ? result.Action + "完成" : result.Action + "失败", text,
                result.Ok ? InfoBarSeverity.Success : InfoBarSeverity.Error);
        }
        catch (Exception ex)
        {
            ShowInfo("驱动操作失败", ex.Message, InfoBarSeverity.Error);
        }
        finally
        {
            SetBusy(false, "");
        }

        await LoadAsync(false, true);
        _operationBusy = false;
    }

    private static string PackageLabel(DriverPackageMatch package) =>
        $"{package.PublishedName} · {ValueOrUnknown(package.Version)} · {ValueOrUnknown(package.Date)}";

    private static string ValueOrUnknown(string? value) =>
        string.IsNullOrWhiteSpace(value) ? "未知" : value;

    private async Task<bool> ConfirmAsync(string title, string message, string primary,
        ContentDialogButton defaultButton)
    {
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = title,
            Content = new TextBlock { Text = message, TextWrapping = TextWrapping.Wrap, LineHeight = 22 },
            PrimaryButtonText = primary,
            CloseButtonText = "取消",
            DefaultButton = defaultButton
        };
        return await dialog.ShowAsync() == ContentDialogResult.Primary;
    }

    private void OpenVendor_Click(object sender, RoutedEventArgs e)
    {
        if (((FrameworkElement)sender).DataContext is not DriverInventoryRow row) return;
        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = DriverService.VendorDownloadUrl(row.Vendor),
                UseShellExecute = true
            });
        }
        catch (Exception ex)
        {
            ShowInfo("无法打开厂商驱动页", ex.Message, InfoBarSeverity.Error);
        }
    }

    private void SetBusy(bool busy, string text)
    {
        BusyRing.IsActive = busy;
        BusyRing.Visibility = busy ? Visibility.Visible : Visibility.Collapsed;
        BusyText.Text = text ?? "";
        RefreshButton.IsEnabled = !busy;
        UpdateButton.IsEnabled = !busy;
        DeviceManagerButton.IsEnabled = !busy;
    }

    private void ShowInfo(string title, string message, InfoBarSeverity severity)
    {
        PageInfo.Title = title;
        PageInfo.Message = message;
        PageInfo.Severity = severity;
        PageInfo.IsOpen = true;
    }

    public void OnThemeChanged()
    {
        // 驱动页使用 ThemeResource 绑定，主题切换后无需额外处理。
    }
}
