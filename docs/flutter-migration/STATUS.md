# 工作区进度与协作登记

更新日期：2026-09-29。工作区 `.worktrees/flutter-foundation`，分支 `codex/flutter-foundation`。
原生基线 `main@3a2dc426`（2.1.2）；Flutter基础 `3b4fb0fd`；合并提交 `08eb6823`。
当前版本以根VERSION为准（3.0.x，hook正常递增）；创建起点78057350保留为历史。

## 当前授权与进度

用户已批准执行[8.1设计](requirements/REQ-001-007-baseline-flutter-design.md)及[执行计划](requirements/REQ-001-007-baseline-flutter-plan.md)。未授权把其余REQ一次性全部实现。

| 需求/工作 | 状态 | 证据/限制 |
| --- | --- | --- |
| 基础骨架与main同步 | 已提交 | 3b4fb0fd、08eb6823；本次Check-Flutter格式/analyze/widget 1/1；内容门禁7游戏通过 |
| REQ-001 UX/调用图/兼容基线 | 已冻结本轮源码基线 | 设计有原始来源、三端链路/所有者、key/格式、已知差异；不是实机验收 |
| REQ-002 存档接续 | Android定向子项完成 | [接续验证](verification/2026-09-29-save-handoff.md)：RED 3→GREEN 18、unit 573项/2skip；库11/11、消费者2/2、host132/132；Harmony失败一致性仍待验证 |
| REQ-003 测量基线 | 目录初测完成，整体未完成 | [测量记录](verification/2026-09-29-android-startup-baseline.md)：三批首卡P95 398/232/463ms，200ms均失败；第三批修正完整投影标记，旧两批该字段作废；未含保存负载/冻结预算 |
| REQ-004 OH工具链 | 运行组合未锁定 | [工具链记录](verification/2026-09-29-ohos-toolchain.md)：1.0.1/API20编译失败；1.0.0实际HAR/HAP成功但MaterialApp在API20/x64上StackOverflow |
| REQ-005 Harmony共享页+C++ | 运行阻塞，未通过 | [Dart目录页](verification/2026-09-29-flutter-catalog-client.md)24测试通过；Harmony host15/15、宿主/测试HAP通过；5557正式包Hypium 2通过/1失败，纯MaterialApp最小复现StackOverflow |
| REQ-006 三端往返+双机 | 未通过 | 无当前三端真机闭环；用户要求本轮先不验证Mac，iOS标记未测 |
| REQ-007 升级+容器+性能 | 未通过 | 数据/授权/真实媒体触控/预算必须全部有证据 |
| G1总体 | 未通过 | 缺少项不得由Hello World、构建或既有存档测试代替 |

## 存档当前事实

实现0c11750c已由main@3a2dc426交付并合入本工作树，不再依赖外部save-history工作树。
公开契约看libs/save_history/include/save_history/save_history.h及README；证据看docs/verification/2026-09-28-save-history-android-harmony.md。
已交付Android/Harmony原生历史与独立库；公共SaveCoordinator、iOS历史接入、Flutter历史页面仍未完成。
references仅保留早期调研；不覆盖现有schema/ABI/用户菜单修订。

## 当前协作登记

| 范围 | 所有者/目录 | 状态 |
| --- | --- | --- |
| 主干合并、详细设计、STATUS/roadmap、host回归 | 当前任务主代理；文档/版本/集成 | 本批实现与证据已整理；后续首先解决REQ-005阻塞 |
| Android恢复接续 | 当前任务子代理；HistorySession/MainActivity及相关instrumentation | 已完成并独立复核；新建任务专用空白AVD，不使用用户原安装 |
| OH SDK/宿主工具链 | 当前任务子代理；独立SDK、忽略探针、Build-Ohos、Harmony实验入口及验证记录 | 阻塞及最小复现已归档；正式包恢复并复测；调试helper/转发已结束 |
| 原生性能采集工具 | 当前任务子代理；tools/flutter/collect_android_baseline.py及测试 | 已完成15测试及两批目录初测；无卸载/清数据 |
| Flutter目录实验页 | 当前任务主代理负责client；子代理负责页面/主题/widget测试 | Dart实现/24测试已完成；无Dart数据库或伪目录；当前鸿蒙桥仅目录 |

同一文件仍需协调；登记不等于文件锁。所有生成物在ignored目录，代码和文档提交使用明确路径。
阶段证据包含revision/工作区改动、命令/断言、SDK/设备、限制与后续依赖；阶段通过不以复选框代替证据。
