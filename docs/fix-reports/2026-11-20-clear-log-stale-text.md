# Fix Report - 清理日志后正文仍显示清理前内容

## Bug 描述

在「运行日志」页点击「清理日志」，确认对话框后：

- 日志文件 `data\winui.log` 与 `winui.log.1` 确实被删除；
- 行数显示变为「暂无记录」，状态提示变为「日志已清理 · 新的记录会自动写入」；
- 但右侧日志正文区域仍停留在清理前的内容，3 秒自动刷新也不会消失。

用户看到的效果就是「清理日志没反应 / 清理不干净」。

## 问题根因

`LogPage.Clear_Click` 在调用 `Render()` 之前手动执行了 `_lastText = ""`：

```csharp
_cleared = true;
_lines.Clear();
_lastText = "";   // ← 根因
Render();
```

而 `Render()` 只在文本与缓存不一致时才写入文本框：

```csharp
var text = string.Join(Environment.NewLine, shown);
if (text != _lastText)
{
    LogText.Text = text;
    _lastText = text;
}
```

清理后 `_lines` 为空，`text` 为 `""`；此时 `_lastText` 已被提前置空，`text == _lastText` 成立，赋值分支被跳过，`LogText.Text` 保留清理前的旧内容。之后 `Reload()` 读到文件不存在，同样走 `text == _lastText` 的跳过分支，界面一直无法恢复。

文件删除逻辑本身没有问题，问题出在视图缓存被提前改写，导致“差异渲染”失效。

## 尝试记录

### 尝试 1：检查 `AppLog.Clear` 是否删不掉文件
- 结果：排除
- 原因：`AppLog.Clear` 在 `lock (Gate)` 内删除 `winui.log`、`winui.log.1`，运行时验证确认文件已被删除。

### 尝试 2：检查确认对话框与 `XamlRoot`
- 结果：排除
- 原因：运行时自动化点击「清理日志」后对话框正常出现，确认按钮可正常执行。

### 尝试 3：检查引擎日志是否立即回填
- 结果：不是主因
- 原因：`engine-bridge.ps1` 每次请求前清空 `$script:LogBuf`，只有新产生的 `Write-Host` 才会回传；回填只发生在快照/优化等操作期间，与“清理后旧内容仍在”无关。

### 尝试 4：定位到 `_lastText` 提前置空
- 结果：成功
- 原因：删除该行后，`Render()` 能检测到 `"" != 旧文本`，正常把 `LogText.Text` 置空。

## 最终方案

删除 `Clear_Click` 中的 `_lastText = ""`，只清空数据源 `_lines`，由 `Render()` 统一负责视图刷新：

```csharp
_cleared = true;
_lines.Clear();
// 不要提前清空 _lastText：Render 依赖它与旧文本的差异来刷新文本框，
// 提前置空会让 text == _lastText 成立，界面继续显示清理前的日志。
Render();
```

## 检查清单

- [x] 对比官方文档：WinUI `TextBox.Text` 为直接赋值属性，无数据绑定；UI Automation `ValuePattern` 读取的是实际文本。
- [x] 检查模块：`LogPage.Clear_Click` / `Render` / `Reload` / `Copy_Click`、`AppLog.Clear` / `Write`、`EngineBridge.ReadStdoutAsync`、`engine-bridge.ps1` 的 `$script:LogBuf`。
- [x] 性能检查：修复不新增任何 IO 或分配；`Render` 仍是 O(n) 拼接，`ReadTail` 仍是单次顺序读取。
- [x] 构建验证：`dotnet build GamePerfCenter.sln -c Release` 0 警告 0 错误。
- [x] 测试验证：功能测试 46 项全部通过。
- [x] 运行时验证：清理前文本框 379 字符且包含测试标记；确认清理后文本框长度为 0、行数「暂无记录」、状态「日志已清理 · 新的记录会自动写入」、`winui.log` 不存在。

## 经验教训

- 使用「缓存 + 差异渲染」模式时，不要在调用渲染函数前手动篡改缓存值；缓存只能由渲染函数自身更新。
- 清理类操作的验证不能只看文件系统结果，还要确认界面状态是否同步；这次文件删对了，但视图没有刷新。
- 与日志相关的多份状态（`_lines`、`_lastText`、`LogText.Text`、行数、状态提示）必须收敛到一个渲染入口，避免各自为政。
