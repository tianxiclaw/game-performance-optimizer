## 游戏性能优化中心 v5.0.7 便携版

本次更新：

- 驱动中心的 Intel 设备更新判定改为读取本机“Intel 驱动支持助手（DSA）”的本地记录，不再只看 Windows Update；未安装 DSA 时自动回退
- 新增“Intel 驱动被回退”检测：当 DSA 记录已成功安装新版本、但系统当前实际版本更旧时标红提示
- 驱动详情新增 DSA 卡片，显示是否最新、记录安装时间与目标版本，并提供官方下载页入口
- 驱动列表的长说明文本支持省略号，避免撑破卡片布局
- 其余功能与 v5.0.6 一致

包内包含 GUI、引擎、启动器、赞赏码、使用说明与 SHA256 校验；不含本机设置、备份和日志。

完整说明见 [README](https://github.com/tianxiclaw/game-performance-optimizer#readme)。
