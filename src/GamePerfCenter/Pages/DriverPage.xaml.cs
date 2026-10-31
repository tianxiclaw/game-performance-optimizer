using System.Collections.ObjectModel;
using System.Diagnostics;
using GamePerfCenter.Models;
using GamePerfCenter.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace GamePerfCenter.Pages;

public sealed partial class DriverPage : Page, IThemeAware
{
    private readonly ObservableCollection<DriverDevice> _devices = new();
    private readonly ObservableCollection<DriverChange> _changes = new();
    private readonly ObservableCollection<DriverHistRow> _history = new();
    private bool _loaded;

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
        await LoadAsync(true);
    }

    private async Task LoadAsync(bool force)
    {
        try
        {
            try { await App.Services.State.EnsureSnapshotAsync(); } catch { }
            var devices = await Task.Run(() => App.Services.Drivers.GetDevices(force));
            // WMI 的 AdapterRAM 是 32 位，超过 4GB 会截断；优先采用引擎快照里的显存值。
            var snapshotGpus = App.Services.State.Snapshot?.Gpus ?? new List<GpuInfo>();
            foreach (var device in devices)
            {
                var match = snapshotGpus.FirstOrDefault(g =>
                    !string.IsNullOrEmpty(g.Name) && !string.IsNullOrEmpty(device.Name) &&
                    (device.Name.Contains(g.Name, StringComparison.OrdinalIgnoreCase) ||
                     g.Name.Contains(device.Name, StringComparison.OrdinalIgnoreCase)));
                if (match?.VRAM is > 0 && (device.AdapterRam is null || match.VRAM > device.AdapterRam))
                    device.AdapterRam = match.VRAM;
            }
            _devices.Clear();
            foreach (var device in devices) _devices.Add(device);
            DeviceCountText.Text = $"共 {_devices.Count} 个显示适配器";
            DeviceEmpty.Visibility = _devices.Count == 0 ? Visibility.Visible : Visibility.Collapsed;

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
        catch (Exception ex)
        {
            ShowInfo("读取驱动信息失败", ex.Message, InfoBarSeverity.Error);
        }
    }

    private async void Refresh_Click(object sender, RoutedEventArgs e) => await LoadAsync(true);

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

    private void OpenTool_Click(object sender, RoutedEventArgs e)
    {
        if (((FrameworkElement)sender).DataContext is not DriverDevice device) return;
        App.Services.Drivers.OpenVendorTool(device);
        ShowInfo("已打开厂商工具", $"{DriverService.VendorDisplayName(device.Vendor)} · {device.ToolText}",
            InfoBarSeverity.Success);
    }

    private void DownloadDriver_Click(object sender, RoutedEventArgs e)
    {
        if (((FrameworkElement)sender).DataContext is not DriverDevice device) return;
        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = DriverService.VendorDownloadUrl(device.Vendor),
                UseShellExecute = true
            });
        }
        catch (Exception ex)
        {
            ShowInfo("无法打开驱动下载页", ex.Message, InfoBarSeverity.Error);
        }
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
