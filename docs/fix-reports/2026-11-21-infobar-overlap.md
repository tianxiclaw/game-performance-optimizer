# Fix Report - 顶部操作提示与页面标题重叠

## Bug 描述

在多个板块（概览、启动项、设置、备份还原等）触发一次会弹提示的操作后（刷新状态、切换主题/材质、恢复设置等），窗口顶部的 InfoBar 会以完整高度直接压在页面标题上：

- 「状态已刷新 · 优化项状态与硬件快照已更新。」与「启动项与后台」标题叠在一起，文字互相穿插；
- 页面副标题、右上角操作按钮也被提示条遮住；
- 提示条消失后布局恢复正常，再次触发又复现。

概览页「一键应用」后的提示相对稳定，其他页面的 `PageInfo` 和窗口级 `EngineInfoBar` 都能复现。

## 问题根因

InfoBar 放在 `Grid` 的 `Auto` 行里，平时 `IsOpen=False`，其模板内部把内容折叠为 0 高。弹提示时只改了 `InfoBar.IsOpen = true`：

```csharp
PageInfo.Title = ...;
PageInfo.Message = ...;
PageInfo.Severity = severity;
PageInfo.IsOpen = true;   // ← 只切模板状态
```

`IsOpen` 只驱动 InfoBar 模板的视觉状态，父级 `Auto` 行没有收到一次可靠的「重新测量」，行高保持在 0。InfoBar 自身仍按完整高度绘制，于是从行内溢出，覆盖在后面的页面内容上。`ContentFrame` 在 XAML 中声明在 InfoBar 之后，绘制层级更高，所以两边文字交错出现。

运行时通过 UI Automation 取到的矩形可以确认：

| 阶段 | EngineInfoBar | 页面 TitleText |
| --- | --- | --- |
| 重叠时 | y=289, h=100 | y=305, h=67 |
| 正常时 | y=289, h=100 | y=429, h=496 |

正常状态下标题应当整体下移 100px 左右；重叠时标题仍在原位，说明 Auto 行没有让出空间。

概览页的 `ActionInfo` 之所以稳定，是因为它额外做了 `Visibility = Collapsed → Visible`，可见性变化会强制父级重新测量。这就是本次修复的落点。

## 尝试记录

### 尝试 1：调整 InfoBar 的 Margin / 页面顶部间距
- 结果：失败
- 原因：不是间距问题。行高仍为 0，加大 Margin 只会让溢出的提示条更靠下，依然压住标题。

### 尝试 2：只调用 `InvalidateMeasure()`
- 结果：不充分
- 原因：如果 InfoBar 自身的测量没有失效，父级重新测量时仍会复用子元素的旧期望尺寸；仅失效父级不足以让 Auto 行拿到新高度。

### 尝试 3：先切 `Visibility` 再打开（最终采用）
- 结果：成功
- 原因：`Collapsed → Visible` 是确定的布局失效信号，父级 Auto 行会重新测量并让出 InfoBar 的高度；配合 `InvalidateMeasure()` 覆盖已经可见、只是重复弹提示的场景。

## 最终方案

新增 `Helpers/InfoBarPresenter.cs`，所有 InfoBar 统一走一个入口：

```csharp
public static void Show(InfoBar bar, string title, string message, InfoBarSeverity severity)
{
    bar.Title = title;
    bar.Message = message;
    bar.Severity = severity;
    SetOpen(bar, true);
}

public static void SetOpen(InfoBar bar, bool open)
{
    if (!open)
    {
        bar.IsOpen = false;
        bar.Visibility = Visibility.Collapsed;
        return;
    }

    CollapseOnClose(bar);
    if (bar.Visibility != Visibility.Visible) bar.Visibility = Visibility.Visible;
    bar.IsOpen = true;
    bar.InvalidateMeasure();
    if (bar.Parent is UIElement parent) parent.InvalidateMeasure();
}
```

配套改动：

- 全局 `EngineInfoBar`、7 个页面的 `PageInfo`、概览页 `PendingBar` 的 XAML 都加上 `Visibility="Collapsed"`，保证第一次打开就是一次真实的可见性变化；
- 各页 `ShowInfo` 与 `MainWindow.ShowError/ShowInfo` 改为调用 helper；
- 关闭时统一折叠，避免空 InfoBar 在顶部留下一条高度；
- `--shot` 自检新增 `--info` 开关（仅 DEBUG），用于离屏复现「提示条是否推开页面内容」。

## 检查清单

- [x] 对比官方文档：WinUI `InfoBar.IsOpen` 只控制信息条展开状态，控件本身应参与布局、不应悬浮覆盖内容；`Visibility` 变化会触发父级重新测量。
- [x] 检查模块：`MainWindow.xaml` 顶部行、`MainWindow.Status.cs`、7 个页面的 `PageInfo` 与 `ShowInfo`、`OverviewPage.PendingBar/ActionInfo`、`InfoBarPresenter`。
- [x] 性能检查：helper 只做属性赋值与一次布局失效，无额外分配；`Closed` 订阅通过 `ConditionalWeakTable` 保证每个 InfoBar 只订阅一次，页面被缓存复用也不会重复挂载。
- [x] 构建验证：Release x64 `0 警告 0 错误`。
- [x] 测试验证：功能测试 52 项全部通过。
- [x] 语言审计：10 个页面 0 残留中文、0 未翻译，退出码 0。
- [x] 运行时验证（离屏截图）：
  - 修复前 `dist/.build/shot-startup-overlap.png`：绿色提示条盖住「启动项与后台」标题；
  - 修复后 `dist/.build/shot-info-startup.png`：提示条独占一行，标题完整下移，两者无重叠。

## 经验教训

- WinUI 的 `Auto` 行不会因为子控件内部视觉状态变化就必然重新测量；`IsOpen` 这类模板级开关必须配一次真实的布局失效。
- 同一个控件在多处重复实现时，最容易出现「有的页面正常、有的页面异常」。这次把 InfoBar 展示收敛到一个 helper，问题不可能再按页面漏改。
- 视觉类 Bug 不能只看代码，离屏截图 + UI Automation 矩形能直接给出「是否让出空间」的硬证据。