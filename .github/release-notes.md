## 游戏性能优化中心 v6.0.3 便携版

本次更新修复“系统等待重启”误报。

- 旧版只要注册表存在 `PendingFileRenameOperations` 就判定为待重启
- Xbox Gaming Services 会写入一条无效记录（`*1\??\...gamingservicesproxy_16.dll.0`），系统无法执行，重启多少次都不会消失
- 现在只统计来源路径合法且来源文件仍存在的记录，无效记录会被忽略
- 诊断信息显示“否 (已忽略 N 条无效记录)”，不再弹出误导性的重启警告
- 本程序不会主动重启或关机；日志中的重启均由 Windows Update 或用户本人发起

验证：在本机确认修复前 `Pending=True`，修复后为 `Pending=False, Ignored=1`；解压后的便携包自测十个页面全部通过。

包内包含主程序、引擎、赞赏码、使用说明与 SHA256 校验；不含本机设置、备份和日志。

完整说明见 [README](https://github.com/tianxiclaw/game-performance-optimizer#readme)。
