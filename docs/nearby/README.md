# 附近联机当前入口

2026-09-25 当前方向：Android、HarmonyOS NEXT、iOS 均可建房或扫码加入；局域网优先，没有可用 LAN 时 Android 房主尝试本地专用热点，其他房主在原页面获得热点设置指引。扫码后进入空房间，房主从游戏大厅选游戏，本机 ROM 匹配后自动开局；同一连接内可换游戏。产品只保留一条 QR 配对路径。好友、蓝牙发现、配对码、ROM 传输、STREAM 与自动恢复不在本轮范围。

当前工作区以 `main@fe12f9ac604a` 为基线，实现三端页面与现有对等后端的接线，并修复画面、声音、输入采样、调度与回滚呈现。[三端对等 UX 设计](../superpowers/specs/2026-09-23-nearby-three-platform-ux-design.md)是交互依据；[9 月 25 日模拟器复测](../verification/2026-09-25-nearby-selection-simulator.md)、[9 月 24 日背景记录](../verification/2026-09-24-nearby-three-platform-simulator.md)和[当前状态](STATUS.md)区分代码、自动测试与实机验收。上述代码于 9 月 27 日整理进入主干提交；真机验收正在进行，尚未签收。

本目录是唯一现行入口；[历史文档](../archive/nearby-2026-09-21/README.md)仅供追溯。[最小可玩基线设计](DESIGN.md)保留原 Android 房主/P1 到 Harmony 客机/P2 的设计来历，其固定角色与热点范围已被本轮替代。[执行计划](PLAN.md)保留实机签收顺序；不能用模拟器、编译或合并结果代替真机画面、声音和延迟验收。
