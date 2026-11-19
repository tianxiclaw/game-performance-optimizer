using System.Runtime.CompilerServices;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using GamePerfCenter.Controls;

namespace GamePerfCenter.Services;

/// <summary>
/// 界面语言：中文为源语言，英文按词表替换。
/// 只翻译界面文案；优化项、游戏、日志等运行数据保持引擎返回的原文。
/// </summary>
public static class Localization
{
    public static string Language { get; private set; } = "zh";

    public static bool IsEnglish => Language == "en";

    public static void Configure(string? language)
        => Language = string.Equals(language, "en", StringComparison.OrdinalIgnoreCase) ? "en" : "zh";

    /// <summary>把中文界面文案换成当前语言；没有词条时原样返回。</summary>
    public static string T(string zh)
    {
        if (!IsEnglish || string.IsNullOrEmpty(zh)) return zh;
        if (English.TryGetValue(zh, out var en)) return en;
        return English.TryGetValue(zh.Trim(), out en) ? en : zh;
    }

    /// <summary>带占位符的文案：中文模板作为词条键，英文模板用 string.Format 填充。</summary>
    public static string F(string zhFormat, params object?[] args)
    {
        var format = zhFormat;
        if (IsEnglish && English.TryGetValue(zhFormat, out var en)) format = en;
        try { return string.Format(format, args); }
        catch (FormatException) { return zhFormat; }
    }

    /// <summary>递归翻译已构建的界面树；原始中文会缓存，切换语言时可再次还原或替换。</summary>
    public static void Apply(DependencyObject? root)
    {
        if (root is null) return;
        // 运行期会被代码反复改写的元素由各自赋值处翻译，避免缓存住上一次的文案。
        if (root is FrameworkElement named && DynamicSources.Contains(named.Name)) return;
        TranslateElement(root);

        // 不直接改写 Run.Text：文本块里的 Run 常由 x:Bind 绑定，赋值会破坏绑定。
        // 需要翻译的片段改为绑定到模型上的本地化属性。
        var count = VisualTreeHelper.GetChildrenCount(root);
        for (var i = 0; i < count; i++) Apply(VisualTreeHelper.GetChild(root, i));
    }

    private static void TranslateElement(DependencyObject element)
    {
        switch (element)
        {
            case TextBlock text:
                Set(element, "Text", text.Text, v => text.Text = v);
                break;
            case PageHeader header:
                Set(element, "Title", header.Title, v => header.Title = v);
                Set(element, "Subtitle", header.Subtitle, v => header.Subtitle = v);
                break;
            case InfoBar bar:
                Set(element, "Title", bar.Title, v => bar.Title = v);
                Set(element, "Message", bar.Message, v => bar.Message = v);
                break;
            case ToggleSwitch toggle:
                if (toggle.Header is string headerText)
                    Set(element, "Header", headerText, v => toggle.Header = v);
                if (toggle.OnContent is string on)
                    Set(element, "OnContent", on, v => toggle.OnContent = v);
                if (toggle.OffContent is string off)
                    Set(element, "OffContent", off, v => toggle.OffContent = v);
                break;
            case ContentControl content when content.Content is string value:
                Set(element, "Content", value, v => content.Content = v);
                break;
        }

        if (element is TextBox textBox)
            Set(element, "Placeholder", textBox.PlaceholderText, v => textBox.PlaceholderText = v);
        if (element is PasswordBox passwordBox)
            Set(element, "Placeholder", passwordBox.PlaceholderText, v => passwordBox.PlaceholderText = v);
        if (element is MenuFlyoutItem menuItem)
            Set(element, "Text", menuItem.Text, v => menuItem.Text = v);

        if (ToolTipService.GetToolTip(element) is string tip)
            Set(element, "ToolTip", tip, v => ToolTipService.SetToolTip(element, v));

        var name = AutomationProperties.GetName(element);
        if (!string.IsNullOrEmpty(name))
            Set(element, "AutomationName", name, v => AutomationProperties.SetName(element, v));
    }

    private static string Lookup(string zh)
        => English.TryGetValue(zh, out var en) ? en
            : English.TryGetValue(zh.Trim(), out en) ? en : zh;

    private static void Set(DependencyObject element, string key, string? current, Action<string> assign)
    {
        if (string.IsNullOrEmpty(current)) return;

        var originals = Cache.GetOrCreateValue(element).Values;
        // 列表容器会被回收并重新绑定；当前值既不是缓存原文也不是它的译文时，旧缓存作废。
        if (originals.TryGetValue(key, out var cached) &&
            !string.Equals(current, cached, StringComparison.Ordinal) &&
            !string.Equals(current, Lookup(cached), StringComparison.Ordinal))
        {
            originals.Remove(key);
        }

        if (!originals.TryGetValue(key, out var source))
        {
            if (!English.ContainsKey(current) && !English.ContainsKey(current.Trim())) return;
            source = current;
            originals[key] = source;
        }

        var target = IsEnglish ? Lookup(source) : source;
        if (!string.Equals(current, target, StringComparison.Ordinal)) assign(target);
    }

    private sealed class Originals
    {
        public readonly Dictionary<string, string> Values = new();
    }

    private static readonly ConditionalWeakTable<DependencyObject, Originals> Cache = new();

    /// <summary>由代码维护、会随运行状态变化的元素名；它们不走遍历缓存。</summary>
    private static readonly HashSet<string> DynamicSources = new(StringComparer.Ordinal)
    {
        "StatusText", "EngineStateText", "TopBreadcrumb", "DrawerPageTitle", "DrawerPageDesc",
        "TopPendingText", "DrawerPendingText", "PaneEngineText", "PaneDeviceName",
        "DockHintText", "CountText", "EngineInfoBar"
    };

    private static readonly Dictionary<string, string> English = new(StringComparer.Ordinal)
    {
        // 外壳 / 顶栏
        ["游戏性能优化中心"] = "Game Performance Center",
        ["本机调优工作台"] = "Local tuning workspace",
        ["工作台"] = "Workspace",
        ["概览"] = "Overview",
        ["仅本机运行"] = "Runs locally",
        ["待优化"] = "Pending",
        ["查看待应用的低风险优化项"] = "View pending low-risk optimizations",
        ["浅色主题"] = "Light theme",
        ["深色主题"] = "Dark theme",
        ["跟随系统"] = "System",
        ["展开控制台"] = "Expand console",
        ["收起控制台"] = "Collapse console",
        ["展开右侧控制台：实时负载、待办与快捷操作"] = "Open the console: live load, pending items and shortcuts",
        ["打开项目主页"] = "Open project page",

        // 控制台
        ["控制台"] = "Console",
        ["实时状态与快捷入口"] = "Live status and shortcuts",
        ["本机"] = "This PC",
        ["正在识别本机"] = "Identifying this PC",
        ["正在连接优化引擎"] = "Connecting to engine",
        ["笔记本"] = "Laptop",
        ["台式机"] = "Desktop",
        ["实时负载"] = "Live load",
        ["每 2 秒"] = "Every 2 s",
        ["内存"] = "Memory",
        ["待应用"] = "To apply",
        ["查看"] = "View",
        ["快捷操作"] = "Quick actions",
        ["命令面板"] = "Command palette",
        ["刷新状态"] = "Refresh",
        ["数据目录"] = "Data folder",
        ["备份目录"] = "Backup folder",
        ["当前页面"] = "Current page",
        ["暂无待应用项"] = "Nothing to apply",

        // 底部状态 / 导航
        ["正在启动..."] = "Starting...",
        ["本地运行 · 不上传数据"] = "Local only · No uploads",
        ["引擎未连接"] = "Engine offline",
        ["引擎已连接"] = "Engine connected",
        ["引擎连接失败"] = "Engine connection failed",
        ["引擎已断开"] = "Engine disconnected",
        ["正在重连..."] = "Reconnecting...",
        ["正在连接优化引擎..."] = "Connecting to engine...",
        ["正在读取硬件信息..."] = "Reading hardware info...",
        ["正在刷新硬件与优化项..."] = "Refreshing hardware and optimizations...",
        ["就绪"] = "Ready",
        ["刷新完成"] = "Refresh complete",
        ["刷新失败"] = "Refresh failed",
        ["硬件与优化项状态已更新。"] = "Hardware and optimization status updated.",
        ["状态已刷新"] = "Status refreshed",
        ["优化项状态与硬件快照已更新。"] = "Optimization status and hardware snapshot updated.",
        ["打开目录失败"] = "Could not open folder",
        ["打开文件失败"] = "Could not open file",
        ["启动失败"] = "Launch failed",
        ["已启动"] = "Launched",
        ["命令执行失败"] = "Command failed",
        ["优化项"] = "Optimizations",
        ["诊断报告"] = "Diagnostics",
        ["启动项与后台"] = "Startup & background",
        ["游戏库"] = "Games library",
        ["驱动中心"] = "Drivers",
        ["备份还原"] = "Backups",
        ["运行日志"] = "Logs",
        ["设置"] = "Settings",
        ["关于与支持"] = "About & support",

        // 页面说明（命令面板 / 抽屉共用）
        ["实时负载、优化进度与硬件摘要。"] = "Live load, optimization progress and hardware summary.",
        ["按分类筛选并应用可还原的系统优化。"] = "Filter and apply reversible system optimizations.",
        ["只读检查 VBS、内存、PCIe、NVMe 与显示链路。"] = "Read-only checks for VBS, memory, PCIe, NVMe and the display path.",
        ["查看开机自启项与内存占用较高的后台进程。"] = "Review startup entries and background processes with high memory use.",
        ["识别本地游戏并保存独立运行配置。"] = "Detect local games and keep a separate launch profile for each.",
        ["显卡驱动版本、厂商工具与回退记录。"] = "GPU driver versions, vendor tools and rollback history.",
        ["原值备份、单项还原与全部回放。"] = "Original-value backups, single restore and full rollback.",
        ["本机操作与引擎输出，不上传。"] = "Local actions and engine output; nothing is uploaded.",
        ["外观、托盘与配置文件。"] = "Appearance, tray behavior and config files.",
        ["版本信息、赞赏码与项目链接。"] = "Version, support QR code and project links.",

        // 命令面板
        ["页面"] = "Pages",
        ["操作"] = "Actions",
        ["材质"] = "Materials",
        ["命令面板搜索框"] = "Command palette search",
        ["没有匹配的命令"] = "No matching commands",
        ["换个关键词，或直接输入页面名。"] = "Try another keyword, or type a page name.",
        ["↑↓ 选择"] = "↑↓ Select",
        ["↵ 执行"] = "↵ Run",
        ["ESC 关闭"] = "ESC Close",
        ["搜索页面、优化项、游戏或命令..."] = "Search pages, optimizations, games or commands...",
        ["刷新硬件与优化项"] = "Refresh hardware and optimizations",
        ["重新采样 CPU、GPU、内存与本机状态"] = "Re-sample CPU, GPU, memory and system state",
        ["打开程序目录"] = "Open program folder",
        ["打开备份目录"] = "Open backup folder",
        ["打开数据目录"] = "Open data folder",
        ["打开配置文件"] = "Open settings file",
        ["材质：深空"] = "Material: Deep Space",
        ["材质：云母"] = "Material: Mica",
        ["材质：云母 Alt"] = "Material: Mica Alt",
        ["材质：液态玻璃"] = "Material: Liquid Glass",
        ["自带渐变背景，不依赖系统合成层"] = "Built-in gradient background, no system composition",
        ["Windows 11 Mica，桌面颜色直接透出"] = "Windows 11 Mica; desktop colors show through",
        ["Mica Alt 底色更深，适合深色桌面与高对比内容"] = "Mica Alt has a deeper base for dark desktops and high-contrast content",
        ["Acrylic 半透明，适合浅色桌面"] = "Translucent acrylic for light desktops",
        ["主题：深色"] = "Theme: Dark",
        ["主题：浅色"] = "Theme: Light",
        ["主题：跟随系统"] = "Theme: System",
        ["当前主题"] = "Current theme",
        ["切换后立即生效"] = "Applies immediately",
        ["当前材质 · "] = "Current material · ",
        [" · 当前系统不支持，会回退深空"] = " · unsupported on this system; falls back to Deep Space",
        ["命令面板 · Ctrl K"] = "Command palette · Ctrl K",

        // 关于页
        ["面向 Windows 的游戏性能调优与系统状态核查工具。所有优化均记录原值，支持一键回滚；数据只在本机采集，不联网、不上传。"] =
            "A Windows tuning and system health tool for gaming. Every change keeps its original value and can be rolled back; data stays on this PC and is never uploaded.",
        ["改动可还原"] = "Reversible changes",
        ["无广告无捆绑"] = "No ads or bundles",
        ["点击赞赏码可放大"] = "Click the QR code to enlarge",
        ["支持作者"] = "Support the author",
        ["如果这个工具帮你省下了折腾的时间，欢迎请我喝杯咖啡。"] = "If this tool saved you some tinkering time, you can buy me a coffee.",
        ["你的支持会用于持续维护优化项、适配新硬件与修复兼容性问题。完全自愿，不影响任何功能。"] =
            "Your support funds ongoing maintenance, new hardware support and compatibility fixes. It is entirely optional and unlocks nothing.",
        ["能力范围"] = "Scope",
        ["优化效果因硬件、系统版本与游戏而异。涉及注册表与服务的改动均在应用前自动备份，可在“备份还原”中回滚。"] =
            "Results vary by hardware, Windows version and game. Registry and service changes are backed up before applying and can be rolled back in Backups.",
        ["© 2026 游戏性能优化中心 · 本工具与 NVIDIA、AMD、Intel、Microsoft 无隶属关系"] =
            "© 2026 Game Performance Center · Not affiliated with NVIDIA, AMD, Intel or Microsoft",
        ["GitHub 主页"] = "GitHub",
        ["最新版本"] = "Latest version",
        ["问题反馈"] = "Report an issue",
        ["使用说明"] = "User guide",
        ["放大查看"] = "Enlarge",
        ["打开原图"] = "Open original",
        ["点击放大"] = "Click to enlarge",

        // 备份页
        ["备份时间线"] = "Backup timeline",
        ["按时间倒序排列，选择任意一份恢复"] = "Newest first; pick one to restore",
        ["还没有备份记录"] = "No backups yet",
        ["应用任意优化项后会自动生成备份"] = "A backup is created after each optimization is applied",
        ["最近一次应用"] = "Last applied",
        ["暂无记录"] = "No records",
        ["应用优化后这里会显示本次改动数量与结果。"] = "After applying, the change count and result appear here.",
        ["备份文件：--"] = "Backup file: --",
        ["安全说明"] = "Safety notes",
        ["备份只包含本应用改动过的注册表值、服务启动类型与电源计划等原值，不复制个人文件。"] =
            "Backups contain only the original registry values, service start types and power plans that this app changed; personal files are never copied.",
        ["恢复前会再次校验项目归属，避免误写无关系统设置。"] =
            "Ownership is re-checked before restoring so unrelated system settings are never touched.",
        ["创建还原点"] = "Create restore point",
        ["恢复全部"] = "Restore all",
        ["定位"] = "Locate",
        ["恢复"] = "Restore",
        ["调用系统还原点功能，耗时较长"] = "Uses Windows System Restore; can take a while",
        ["把所有已记录项目恢复为原值"] = "Restore every recorded item to its original value",
        ["在资源管理器中选中该备份文件夹"] = "Select this backup folder in Explorer",
        ["把该时间点记录的原值写回系统"] = "Write the original values from this backup back to the system",

        // 诊断页
        ["尚未导出"] = "Not exported yet",
        ["导出的报告会保存在 diagnostics 目录"] = "Reports are saved in the diagnostics folder",
        ["还没有诊断结果"] = "No diagnostics yet",
        ["运行一次诊断，确认当前系统的风险与可优化项。"] = "Run diagnostics to check risks and optimization opportunities.",
        ["打开诊断目录"] = "Open diagnostics folder",
        ["导出诊断包"] = "Export diagnostic bundle",
        ["导出报告"] = "Export report",
        ["重新诊断"] = "Run again",
        ["全部"] = "All",
        ["需关注"] = "Attention",
        ["正常"] = "Normal",
        ["打开文件"] = "Open file",
        ["开始诊断"] = "Run diagnostics",
        ["搜索项目、值或说明"] = "Search items, values or descriptions",
        ["打包日志、配置与诊断文本，便于反馈问题"] = "Bundle logs, config and diagnostics for reporting",

        // 驱动页
        ["设备"] = "Device",
        ["可更新"] = "Update available",
        ["需处理"] = "Needs attention",
        ["驱动包"] = "Driver package",
        ["尚未扫描"] = "Not scanned",
        ["设备驱动"] = "Device drivers",
        ["版本取自当前生效的 INF，并与本机驱动仓库逐项比对"] =
            "Versions come from the active INF and are compared against the local driver store",
        ["未检测到可管理的设备"] = "No manageable devices detected",
        ["最近驱动变更"] = "Recent driver changes",
        ["由本应用记录的驱动版本变化，用于排查意外回退"] =
            "Driver version changes recorded by this app, to trace unexpected rollbacks",
        ["暂无驱动变更记录"] = "No driver changes recorded",
        ["首次运行后会自动建立基线"] = "A baseline is created on first run",
        ["设备驱动档案"] = "Driver inventory",
        ["记录每台设备的 INF、版本与日期"] = "INF, version and date for each device",
        ["暂无驱动档案"] = "No driver inventory yet",
        ["页面只读取设备、INF 与驱动仓库，不会自动下载或替换驱动。确需更新时请使用 NVIDIA App、AMD Software 或 Intel 驱动支持助手；发现版本意外回退可查看左侧变更记录。"] =
            "This page only reads devices, INF files and the driver store; it never downloads or replaces drivers. Use NVIDIA App, AMD Software or Intel Driver & Support Assistant to update. Check the change history on the left for unexpected rollbacks.",
        ["刷新本地"] = "Refresh local",
        ["检测更新"] = "Check for updates",
        ["打开设备管理器"] = "Open Device Manager",
        ["管理"] = "Manage",
        ["厂商驱动"] = "Vendor driver",
        ["重新枚举设备与驱动仓库，不访问网络"] = "Re-enumerate devices and the driver store without network access",
        ["查询 Windows Update 中可用的驱动更新"] = "Check Windows Update for driver updates",
        ["重新绑定、切换或清理该设备的驱动包"] = "Rebind, switch or clean this device's driver package",
        ["打开厂商官方驱动页面"] = "Open the vendor's official driver page",

        // 游戏库
        ["本机游戏"] = "Local games",
        ["没有检测到游戏"] = "No games detected",
        ["支持 Steam / Epic / WeGame / Xbox；也可以手动选择任意 exe。"] =
            "Supports Steam / Epic / WeGame / Xbox; you can also add any exe manually.",
        ["本地"] = "Local",
        ["可启动"] = "Launchable",
        ["当前启动方案"] = "Current launch profile",
        ["尚未保存方案"] = "No profile saved",
        ["尚未保存专属方案，启动时使用系统默认策略。"] = "No per-game profile yet; launches use system defaults.",
        ["启动设置"] = "Launch settings",
        ["核心亲和"] = "Core affinity",
        ["CPU 优先级"] = "CPU priority",
        ["全屏独占"] = "Exclusive fullscreen",
        ["高性能 GPU"] = "High-performance GPU",
        ["管理员启动"] = "Run as administrator",
        ["启动参数：—"] = "Launch arguments: —",
        ["方案仅对该游戏生效。修改前会记录原值，可在「备份还原」中恢复系统设置。"] =
            "The profile applies only to this game. Original values are recorded before changes and can be restored in Backups.",
        ["选择左侧的游戏"] = "Select a game",
        ["选中后会显示它的启动方案、路径与快捷操作。双击列表项可直接编辑。"] =
            "The selection shows its launch profile, path and shortcuts. Double-click a row to edit.",
        ["单击固定到右侧详情"] = "Click to pin details on the right",
        ["重新扫描"] = "Rescan",
        ["返回游戏列表"] = "Back to list",
        ["启动游戏"] = "Launch game",
        ["编辑方案"] = "Edit profile",
        ["打开目录"] = "Open folder",
        ["从库移除"] = "Remove from library",
        ["手动添加游戏"] = "Add game manually",
        ["手动添加"] = "Add manually",
        ["搜索名称或路径..."] = "Search name or path...",
        ["选择任意 exe 加入游戏库"] = "Choose any exe to add",
        ["重新扫描 Steam / Epic / WeGame / Xbox 游戏"] = "Rescan Steam / Epic / WeGame / Xbox games",
        ["在资源管理器中定位该游戏的可执行文件"] = "Locate the game's executable in Explorer",
        ["按来源筛选游戏"] = "Filter by source",
        ["按方案状态筛选游戏"] = "Filter by profile status",
        ["游戏列表"] = "Game list",
        ["已生效 0"] = "Active 0",
        ["待优化 0"] = "Pending 0",
        ["不适用 0"] = "N/A 0",
        ["已选 0"] = "Selected 0",
        ["选择"] = "Select",
        ["状态"] = "Status",
        ["操作"] = "Action",
        ["编辑该游戏的启动方案"] = "Edit launch profile",
        ["按该游戏方案启动"] = "Launch with profile",

        // 优化项
        ["已选"] = "Selected",
        ["详情"] = "Details",
        ["收起"] = "Hide",
        ["已生效"] = "Active",
        ["检测中"] = "Checking",
        ["不适用"] = "N/A",
        ["需重启"] = "Restart needed",
        ["目标："] = "Target:",
        ["  目标："] = "  Target: ",
        ["目标值"] = "Target value",
        ["当前状态"] = "Current status",
        ["风险"] = "Risk",
        ["需要重启"] = "Restart required",
        ["需要重启后生效"] = "Takes effect after reboot",
        ["无需重启"] = "No restart needed",
        ["无依赖"] = "No dependencies",
        ["依赖项"] = "Dependencies",
        ["没有符合条件的优化项"] = "No matching optimizations",
        ["试试清空搜索词，或把分类、风险筛选恢复为全部。"] =
            "Clear the search, or reset category and risk filters to All.",
        ["未选择项目"] = "No item selected",
        ["应用前自动生成原值备份 · 预览不会写入系统"] = "Originals are backed up before applying · preview writes nothing",
        ["全选推荐"] = "Select recommended",
        ["清除选择"] = "Clear selection",
        ["载入"] = "Load",
        ["保存"] = "Save",
        ["复制 ID"] = "Copy ID",
        ["应用此项"] = "Apply this item",
        ["恢复最近备份"] = "Restore latest backup",
        ["预览所选"] = "Preview selected",
        ["应用所选"] = "Apply selected",
        ["搜索名称、分类或说明..."] = "Search name, category or description...",
        ["全部分类"] = "All categories",
        ["全部风险"] = "All risk levels",
        ["预设方案"] = "Presets",
        ["选中所有待优化的低风险项目"] = "Select all pending low-risk items",
        ["重新检测全部优化项"] = "Re-scan all optimizations",
        ["将方案中的项目设为选中"] = "Select items in the preset",
        ["把当前勾选项保存为自定义方案"] = "Save the current selection as a preset",
        ["勾选后预览或应用"] = "Check items to preview or apply",
        ["展开原值、目标值、依赖与上次应用时间"] = "Show originals, targets, dependencies and last applied time",
        ["撤销最近一次应用，会覆盖当前对应的系统设置"] = "Undo the last apply; overwrites the corresponding system settings",
        ["优化项列表"] = "Optimization list",
        ["展开或收起该项详情"] = "Expand or collapse details",
        ["查看详情"] = "View details",
        ["收起详情"] = "Hide details",
        ["上次应用"] = "Last applied",
        ["复制"] = "Copy",
        ["复制完整路径"] = "Copy full path",
        ["低风险"] = "Low risk",
        ["中风险"] = "Medium risk",
        ["高风险"] = "High risk",
        ["未知风险"] = "Unknown risk",
        ["尚未通过本工具应用"] = "Not applied by this tool yet",
        ["上次应用 {0}"] = "Last applied {0}",
        ["已生效 —"] = "Active —",
        ["待优化 —"] = "Pending —",
        ["不适用 —"] = "N/A —",
        ["已生效 {0}"] = "Active {0}",
        ["待优化 {0}"] = "Pending {0}",
        ["不适用 {0}"] = "N/A {0}",
        ["已选 {0}"] = "Selected {0}",
        ["显示 {0} / {1} 项"] = "Showing {0} / {1}",
        ["已选 {0} 项 · 低风险 {1} · 中风险 {2} · 高风险 {3}"] =
            "{0} selected · low {1} · medium {2} · high {3}",
        ["正在读取..."] = "Reading...",
        ["正在读取优化项"] = "Reading optimizations",
        ["正在读取当前系统状态，通常需要几秒。"] = "Reading the current system state; this takes a few seconds.",
        ["取消"] = "Cancel",
        ["关闭"] = "Close",
        ["确认应用"] = "Apply",
        ["变更预览"] = "Change preview",
        ["保存自定义方案"] = "Save custom preset",
        ["例如：我的竞技配置"] = "e.g. My competitive profile",
        ["状态读取失败"] = "Failed to read status",
        ["已选择推荐项"] = "Recommended selected",
        ["已勾选全部待优化的低风险项目。"] = "All pending low-risk items are checked.",
        ["请选择方案"] = "Select a preset",
        ["下拉框中没有可载入的预设方案。"] = "There is no preset to load in the list.",
        ["方案已载入"] = "Preset loaded",
        ["已载入「{0}」，共勾选 {1} 项。"] = "Loaded \"{0}\" with {1} item(s) checked.",
        ["没有选中项"] = "Nothing selected",
        ["请先勾选要保存的优化项。"] = "Check the items you want to save first.",
        ["名称不能为空"] = "Name required",
        ["请输入方案名称。"] = "Enter a preset name.",
        ["方案已保存"] = "Preset saved",
        ["「{0}」包含 {1} 项，已保存到本机 profiles.json。"] =
            "\"{0}\" contains {1} item(s) and is saved to profiles.json.",
        ["保存失败"] = "Save failed",
        ["正在刷新"] = "Refreshing",
        ["重新检测全部优化项状态..."] = "Re-checking all optimization states...",
        ["刷新完成"] = "Refresh complete",
        ["优化项状态已更新。"] = "Optimization states are updated.",
        ["刷新失败"] = "Refresh failed",
        ["应用「{0}」"] = "Apply \"{0}\"",
        ["目标：{0}\n风险：{1}\n\n应用前会自动生成原值备份与 .reg 快照，可在「备份还原」中撤销。"] =
            "Target: {0}\nRisk: {1}\n\nOriginal values and a .reg snapshot are backed up before applying; undo in Backups.",
        ["应用"] = "Apply",
        ["已复制 ID"] = "ID copied",
        ["{0} 已写入剪贴板。"] = "{0} copied to the clipboard.",
        ["复制失败"] = "Copy failed",
        ["时间未知"] = "Unknown time",
        ["请先勾选要预览的优化项。"] = "Check the items you want to preview first.",
        ["请先勾选要应用的优化项。"] = "Check the items you want to apply first.",
        ["应用所选优化"] = "Apply selected optimizations",
        ["将应用 {0} 项优化，其中 {1} 项为高风险。\n\n应用前会自动生成原值备份与 .reg 快照，可在「备份还原」中撤销。"] =
            "Will apply {0} optimization(s), including {1} high-risk item(s).\n\nOriginal values and a .reg snapshot are backed up before applying; undo in Backups.",
        ["将应用 {0} 项优化。\n\n应用前会自动生成原值备份与 .reg 快照，可在「备份还原」中撤销。"] =
            "Will apply {0} optimization(s).\n\nOriginal values and a .reg snapshot are backed up before applying; undo in Backups.",
        ["成功 {0} 项 · 失败 {1} 项"] = "{0} succeeded · {1} failed",
        ["已应用 {0} 项 · 失败 {1} 项"] = "{0} applied · {1} failed",
        ["优化已应用"] = "Optimizations applied",
        ["部分项目失败"] = "Some items failed",
        ["操作失败"] = "Operation failed",
        ["所选项目均已处于推荐值，无需变更。"] = "All selected items are already at the recommended values; nothing to change.",
        ["共 {0} 项将发生变更（预览不会写入系统）："] = "{0} item(s) will change (preview writes nothing):",
        ["当前：{0}  →  目标：{1}"] = "Current: {0}  →  Target: {1}",
        ["当前：{0}  →  目标：{1}  · 需重启"] = "Current: {0}  →  Target: {1}  · Restart needed",
        ["恢复最近备份"] = "Restore latest backup",
        ["将把最近一次应用的原值写回系统。此操作会修改注册表/服务/电源设置。\n\n确定继续吗？"] =
            "This writes the original values of the last apply back to the system and changes registry/service/power settings.\n\nContinue?",
        ["恢复完成"] = "Restore complete",
        ["打开主界面"] = "Open main window",
        ["退出"] = "Exit",
        ["刷新状态"] = "Refresh status",

        // 概览
        ["正在读取本机状态..."] = "Reading system status...",
        ["正在采集硬件与优化项状态。"] = "Collecting hardware and optimization status.",
        ["重启状态：读取中"] = "Restart: reading",
        ["安全与存储：读取中"] = "Security & storage: reading",
        ["应用推荐项"] = "Apply recommended",
        ["当前没有待优化项"] = "Nothing pending",
        ["还有可应用的优化项"] = "Optimizations available",
        ["推荐项均已生效。可以打开优化项手动复查，或预览当前配置。"] =
            "All recommendations are applied. Open Optimizations to review manually, or preview the current configuration.",
        ["{0} 项低风险推荐项可直接应用；应用前自动备份原值，可在「备份还原」中撤销。"] =
            "{0} low-risk recommendation(s) can be applied. Originals are backed up first and can be restored in Backups.",
        ["低风险推荐 {0} 项可应用"] = "{0} low-risk recommendation(s) ready",
        ["低风险推荐：暂无待应用项"] = "Low-risk recommendations: nothing pending",
        ["应用 {0} 项"] = "Apply {0}",
        ["暂无推荐项"] = "No recommendations",
        ["重启状态：等待重启后生效"] = "Restart: takes effect after reboot",
        ["重启状态：无需重启"] = "Restart: not required",
        ["安全与存储：未见异常"] = "Security & storage: no issues",
        ["安全与存储：{0} 项提示"] = "Security & storage: {0} notice(s)",
        ["显示设备 · "] = "Display · ",
        ["未识别到显示设备"] = "No display device detected",
        ["交流供电"] = "AC power",
        ["电池供电"] = "Battery",
        ["未知"] = "Unknown",
        ["可用 · 1 秒刷新"] = "Available · 1 s refresh",
        ["不可用"] = "Unavailable",
        ["暂无记录"] = "No record",
        ["{0} 项 · {1}"] = "{0} item(s) · {1}",
        ["检测到系统等待重启：{0}。部分优化需要重启后才会生效。"] =
            "The system has a pending restart: {0}. Some optimizations take effect after reboot.",
        ["记录"] = "Record",
        ["更新于 {0}"] = "Updated {0}",
        ["已生效 {0} / {1} 项可优化"] = "{0} / {1} optimizations applied",
        ["{0} 项不适用"] = "{0} not applicable",
        ["{0} 项检测中"] = "{0} checking",
        ["优化完成度 {0}"] = "Optimization completion {0}",
        ["优化完成度：正在读取本机状态"] = "Optimization completion: reading system status",
        ["专用显卡 3D 引擎"] = "Discrete GPU 3D engine",
        ["GPU 数据不可用"] = "GPU data unavailable",
        ["{0} / {1} GB 已用"] = "{0} / {1} GB used",
        ["更新于 {0} · 0.25 秒采样"] = "Updated {0} · 0.25 s sampling",
        ["无需优化"] = "Nothing to apply",
        ["当前没有处于待优化状态的低风险项目。"] = "There are no pending low-risk items.",
        ["无需预览"] = "Nothing to preview",
        ["应用推荐优化"] = "Apply recommended optimizations",
        ["将应用 {0} 项低风险优化。\n\n应用前会自动生成 JSON 原值备份与 .reg 快照，可在「备份还原」中撤销。"] =
            "Will apply {0} low-risk optimization(s).\n\nOriginal values and a .reg snapshot are backed up first; undo in Backups.",
        ["备份：{0}"] = "Backup: {0}",
        ["GPU 采样"] = "GPU sampling",
        ["实时负载、优化进度与硬件状态。"] = "Live load, optimization progress and hardware status.",
        ["系统等待重启"] = "Restart pending",
        ["部分优化项需要重启后才能生效。"] = "Some optimizations take effect after a reboot.",
        ["引擎错误"] = "Engine error",
        ["游戏"] = "Games",
        ["选中一个游戏，查看它的启动方案；方案只对该游戏生效，可随时还原。"] =
            "Select a game to see its launch profile; the profile applies only to that game and can be restored anytime.",
        ["哪些项值得改：勾选后预览或应用，所有改动都记录原值、可还原。"] =
            "What is worth changing: check items to preview or apply; every change records originals and is reversible.",
        ["这是什么、是否可信：版本、能力范围与支持作者的方式。"] =
            "What this is and whether to trust it: version, capabilities and ways to support the author.",
        ["怎么安全回退：每次应用前都记录原值，可选择任意时间点恢复。"] =
            "How to roll back safely: originals are recorded before every apply, and any point can be restored.",
        ["硬件、电源、驱动、服务与安全状态的一次性核查。"] =
            "A one-shot check of hardware, power, drivers, services and security.",
        ["扫描本机设备与驱动仓库，核对版本与残留；更新判断只读取 Windows Update，不自动安装。"] =
            "Scans local devices and the driver store to check versions and leftovers; update checks only read Windows Update and never install automatically.",
        ["引擎输出与界面操作记录，只留在本机。"] = "Engine output and UI actions, kept on this machine only.",
        ["怎么改变程序行为：外观、托盘与配置文件，修改后立即保存。"] =
            "How to change behavior: appearance, tray and config files, saved immediately on change.",
        ["哪些程序会自启、后台在跑什么：只读展示，不在应用内结束进程。"] =
            "What starts automatically and what runs in the background: read-only, no process termination in the app.",
        ["所选项目均已处于推荐值，无需变更。"] = "All selected items are already at the recommended values; nothing to change.",

        // 日志
        ["等待日志..."] = "Waiting for log...",
        ["打开日志目录"] = "Open log folder",
        ["清理日志"] = "Clear logs",
        ["复制当前视图"] = "Copy current view",
        ["搜索日志内容"] = "Search logs",
        ["暂无日志。执行优化、恢复或诊断后会在此显示引擎输出。"] =
            "No logs yet. Engine output appears here after optimize, restore or diagnostics.",
        ["删除本机运行日志，不影响备份与优化记录"] = "Delete local logs; backups and optimization records are kept",
        ["仅看失败"] = "Failures only",
        ["自动刷新"] = "Auto refresh",

        // 概览
        ["等待首次采样"] = "Waiting for first sample",
        ["CPU 负载"] = "CPU load",
        ["最近 90 秒"] = "Last 90 seconds",
        ["读取中..."] = "Reading...",
        ["网络"] = "Network",
        ["上行 --"] = "Up --",
        ["供电"] = "Power",
        ["正在读取显示设备..."] = "Reading display devices...",
        ["优化进度"] = "Optimization progress",
        ["项待优化"] = "items pending",
        ["已加载 {0} 个优化项 · {1}"] = "Loaded {0} optimizations · {1}",
        ["正在读取硬件与优化项状态..."] = "Reading hardware and optimization status...",
        ["状态读取失败: {0}"] = "Failed to read status: {0}",
        ["已生效 -- 项"] = "-- active",
        ["正在读取本机状态..."] = "Reading system status...",
        ["正在采集硬件与优化项状态。"] = "Collecting hardware and optimization status.",
        ["低风险推荐 -- 项"] = "-- low-risk recommendations",
        ["重启状态：读取中"] = "Restart status: reading",
        ["安全与存储：读取中"] = "Security & storage: reading",
        ["硬件概览"] = "Hardware overview",
        ["正在读取设备信息..."] = "Reading device info...",
        ["安全与存储"] = "Security & storage",
        ["打开优化项"] = "Open optimizations",
        ["预览变更"] = "Preview changes",
        ["应用推荐项"] = "Apply recommended",
        ["完整诊断"] = "Full diagnostics",
        ["重新读取硬件与优化项状态"] = "Re-read hardware and optimization status",
        ["查看全部优化项并手动勾选"] = "View all optimizations and select manually",
        ["只读预演，不写入系统"] = "Read-only preview; writes nothing",
        ["应用全部低风险推荐项，应用前自动备份原值"] =
            "Apply all low-risk recommendations with automatic backup",

        // 设置
        ["外观"] = "Appearance",
        ["主题会同时应用到主窗口与弹窗"] = "The theme applies to the main window and dialogs",
        ["界面主题"] = "Theme",
        ["深色适合游戏场景，浅色适合办公环境"] = "Dark suits gaming; light suits office work",
        ["窗口材质"] = "Window material",
        ["云母、云母 Alt 与液态玻璃直接透出 Windows 11 系统合成层，卡片与导航保持可读；系统不支持或开启高对比度时自动回退深空。"] =
            "Mica, Mica Alt and Liquid Glass reveal the Windows 11 composition layer while cards and navigation stay readable; unsupported systems or high contrast fall back to Deep Space.",
        ["深空"] = "Deep Space",
        ["纯本地渐变"] = "Local gradient",
        ["云母"] = "Mica",
        ["静态磨砂"] = "Static frost",
        ["云母 Alt"] = "Mica Alt",
        ["加深底色"] = "Deeper base",
        ["液态玻璃"] = "Liquid Glass",
        ["实时透光"] = "Live translucency",
        ["行为"] = "Behavior",
        ["控制窗口生命周期与提醒"] = "Window lifecycle and notifications",
        ["关闭时最小化到托盘"] = "Minimize to tray when closed",
        ["保留后台监控，可从托盘图标重新打开"] = "Keeps monitoring in the background; reopen from the tray icon",
        ["驱动变化提醒"] = "Driver change alerts",
        ["检测到驱动版本变化时给出提示"] = "Notify when a driver version changes",
        ["无障碍"] = "Accessibility",
        ["减弱动效"] = "Reduce motion",
        ["跟随系统设置，修改后立即生效"] = "Follows system settings; applies immediately",
        ["关闭数值滚动与入场淡入，界面直接呈现最终状态"] =
            "Disable number rolling and fades; show the final state directly",
        ["高对比度"] = "High contrast",
        ["跟随 Windows 高对比度设置；开启时使用系统色并停用窗口材质。"] =
            "Follows Windows high contrast; uses system colors and disables window materials.",
        ["存储与配置"] = "Storage & config",
        ["程序目录"] = "Program folder",
        ["配置文件"] = "Settings file",
        ["分享与便携包"] = "Share & portable package",
        ["一键导出当前程序为便携 ZIP，自动排除本机设置、备份、诊断与日志。"] =
            "Export the program as a portable ZIP, excluding local settings, backups, diagnostics and logs.",
        ["尚未导出便携包"] = "No portable package exported yet",
        ["版本与更新"] = "Version & updates",
        ["WinUI 3 便携版 · 自包含运行，无需安装 .NET"] = "WinUI 3 portable · self-contained, no .NET install needed",
        ["界面框架 WinUI 3（Windows App SDK） · 引擎 Windows PowerShell 5.1"] =
            "UI WinUI 3 (Windows App SDK) · Engine Windows PowerShell 5.1",
        ["更新通过 GitHub Releases 发布。便携版直接解压覆盖即可，配置与备份会保留在程序目录。"] =
            "Updates ship via GitHub Releases. Unzip over the portable copy; config and backups stay in the program folder.",
        ["重置"] = "Reset",
        ["仅重置外观与行为设置，不会删除备份、日志或游戏库。"] =
            "Resets appearance and behavior only; backups, logs and the game library are kept.",
        ["深色"] = "Dark",
        ["浅色"] = "Light",
        ["系统设置"] = "System",
        ["导出便携包"] = "Export portable package",
        ["打开导出位置"] = "Open export location",
        ["检查更新"] = "Check for updates",
        ["恢复默认设置"] = "Restore defaults",
        ["纯本地渐变背景，不依赖系统合成层"] = "Local gradient background; no system composition",
        ["使用 Windows 11 云母背景"] = "Windows 11 Mica background",
        ["Mica Alt：比云母更深的底色，文字与卡片对比更稳"] = "Mica Alt: deeper base with steadier text and card contrast",
        ["使用系统亚克力与高光层模拟液态玻璃"] = "System acrylic plus highlight layers simulate liquid glass",
        ["打开 Windows 辅助功能中的对比度设置"] = "Open Windows contrast settings",

        // 启动项
        ["个自启项"] = "startup items",
        ["个后台进程"] = "background processes",
        ["Top 进程合计"] = "Top processes total",
        ["数据来自注册表 Run、启动文件夹与进程工作集"] =
            "Data from registry Run keys, Startup folders and process working sets",
        ["开机启动项"] = "Startup items",
        ["来自注册表 Run 与启动文件夹"] = "From registry Run keys and Startup folders",
        ["没有发现自启项"] = "No startup items found",
        ["注册表 Run 与启动文件夹都是空的，通常意味着系统很干净。"] =
            "Registry Run keys and Startup folders are empty, which usually means a clean system.",
        ["内存占用"] = "Memory usage",
        ["按工作集排序 · 条长表示相对最高占用"] = "Sorted by working set · bar length is relative to the largest",
        ["没有读到后台进程"] = "No background processes read",
        ["可能被系统权限拦截。点“刷新”重试，或到任务管理器查看。"] =
            "May be blocked by permissions. Click Refresh to retry, or check Task Manager.",
        ["启动文件夹"] = "Startup folder",
        ["任务管理器"] = "Task Manager",

        // 顶栏筛选 / 通用
        ["刷新"] = "Refresh",
        ["全部风险"] = "All risk levels",
    };
}
