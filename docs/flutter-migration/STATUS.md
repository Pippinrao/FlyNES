# 工作区进度与协作登记

更新日期：2026-09-29。工作区 `.worktrees/flutter-foundation`，分支 `codex/flutter-foundation`。
原生基线 `main@3a2dc426`（2.1.2）；Flutter基础 `3b4fb0fd`；合并提交 `08eb6823`。
当前版本以根VERSION为准（3.0.x，hook正常递增）；创建起点78057350保留为历史。

## 当前授权与进度

用户已批准执行[8.1设计](requirements/REQ-001-007-baseline-flutter-design.md)及[执行计划](requirements/REQ-001-007-baseline-flutter-plan.md)。未授权把其余REQ一次性全部实现。
后续明确要求继续完成验证：Mac 暂不验证；先完成模拟器可执行的全部项目。真机项目独立保留，工具链失败继续排查。

| 需求/工作 | 状态 | 证据/限制 |
| --- | --- | --- |
| 基础骨架与main同步 | 已提交 | 3b4fb0fd、08eb6823；本次Check-Flutter格式/analyze/widget 1/1；内容门禁7游戏通过 |
| REQ-001 UX/调用图/兼容基线 | 已冻结本轮源码基线 | 设计有原始来源、三端链路/所有者、key/格式、已知差异；不是实机验收 |
| REQ-002 存档接续 | Android/Harmony定向子项完成 | [Android接续](verification/2026-09-29-save-handoff.md)：RED 3→GREEN 18、unit 573项/2skip；库11/11、消费者2/2、host132/132；[Harmony接续](verification/2026-09-29-harmony-save-handoff.md)：真实RED→GREEN 9/9、UI1/1、host15/15 |
| REQ-003 测量基线 | 两端模拟器原生配对启动及保存采集完成；诊断预算已固定 | `eaafd7d0/3.0.5` 的 [Android配对基线](verification/2026-09-29-android-native-paired-baseline.md)及[OH基线](verification/2026-09-29-ohos-native-performance.md)各有2次预热+12次正式启动、65秒+真实AUTO数据。另补同3.0.5直接启动，首卡P95 389ms，200ms门槛仍失败；本次OH原生欠载591、Android保存附近播放头重置均保留。[固定预算](verification/2026-09-29-performance-budget.md) |
| REQ-004 工具链 | Android Release及OH三模式构建通过 | 固定上游/OH SDK；[3.0.5匹配Release](verification/2026-09-29-matched-release-builds.md)双ABI/AOT/版本内容检查及完整包增量均通过；Android另以兼容本地测试签名覆盖安装Release并实测，不是生产证书。[OH模式证据](verification/2026-09-29-ohos-build-modes.md)含模式/哈希守卫及debug恢复。OH profile原生宿主仍Debug，不能直接用于整体性能放行 |
| REQ-005 Harmony共享页+C++ | Debug共享目录页已通过 | 5557真实Hypium 3/3：宿主、manifest首卡、选卡详情；小栈问题由公开独立UI线程选项解决，未改SDK/关闭assert |
| REQ-006 三端往返+双机 | Android/OH模拟器功能与双机通过；三端未放行 | [Android17/17](verification/2026-09-29-android-foundation.md)含20次往返；OH完整9/9+texture4/4；[真实跨App ProductPlay](verification/2026-09-29-nearby-simulators.md)最终两端各1/1，含双方输入、音频消费、回房间继续、同连接换ROM；iOS宿主未接线/实测（Mac按用户要求延期） |
| REQ-007 升级+容器+性能 | 本轮Android/OH模拟器验证完成；性能仍有未达标项 | [Android跨版本](verification/2026-09-29-android-upgrade.md)及[Harmony跨版本](verification/2026-09-29-harmony-cross-version-upgrade.md)均为2.1.2→3.0.3真实覆盖。两端候选启动、65秒自动保存、20往返已实际执行。Android/OH debug PSS P95分别335645/350956KiB，均超固定阈值；启动、保存上下文、软件输入在阈值内。Android ART GC后增长72KiB；OH公开指定线程GC后Ark增长-123KiB，快照导出失败单列。[Android Release对照](verification/2026-09-29-android-release-pss.md)同模式增量60.13MiB、[OH Release对照](verification/2026-09-29-ohos-flutter-candidate-performance.md)增量45.29MiB均通过补充诊断，不覆盖debug失败 |
| G1总体 | 未通过 | 模拟器执行已收尾，测试完成不等于性能达标。保留debug PSS和原生首卡失败；Mac/iOS按用户要求延期，真机签名覆盖、摄像头QR与物理媒体指标待设备。模拟器缺精确呈现时间；OH堆快照导出不可用，公开GC后的数值证据另列 |

## 存档当前事实

实现0c11750c已由main@3a2dc426交付并合入本工作树，不再依赖外部save-history工作树。
公开契约看libs/save_history/include/save_history/save_history.h及README；证据看docs/verification/2026-09-28-save-history-android-harmony.md。
已交付Android/Harmony原生历史与独立库；公共SaveCoordinator、iOS历史接入、Flutter历史页面仍未完成。
references仅保留早期调研；不覆盖现有schema/ABI/用户菜单修订。

## 当前协作登记

| 范围 | 所有者/目录 | 状态 |
| --- | --- | --- |
| 主干合并、详细设计、STATUS/roadmap、host回归 | 当前任务主代理；文档/版本/集成 | shared132/132、Harmony host15/15；两端跨版本及双机通过，原生/候选对照完成；PSS摘要读取失败误报已RED→GREEN并独立复核 |
| Android恢复接续 | 当前任务子代理；HistorySession/MainActivity及相关instrumentation | 已完成并独立复核；新建任务专用空白AVD，不使用用户原安装 |
| OH SDK/宿主工具链 | 当前任务子代理；独立SDK、忽略探针、Build-Ohos、Harmony实验入口及验证记录 | 三模式构建已验证；正式surface生命周期组合9/9+texture4/4通过，不使用SDK私改 |
| 原生性能采集工具 | 当前任务子代理；tools/flutter/collect_android_baseline.py及测试 | 工具21测试通过、三批目录初测及自动保存采集夹具就绪；无卸载/清数据 |
| Flutter目录实验页 | 当前任务主代理负责client；子代理负责页面/主题/widget测试 | Dart实现/28测试完成，两端已实现目录/恢复能力/原生游戏和页面桥；无Dart数据库或伪目录 |

同一文件仍需协调；登记不等于文件锁。所有生成物在ignored目录，代码和文档提交使用明确路径。
阶段证据包含revision/工作区改动、命令/断言、SDK/设备、限制与后续依赖；阶段通过不以复选框代替证据。

收尾检查：OH采集逻辑Node 11/11、native-only导出工具8/8、OH摘要7/7、内容门禁7游戏通过。摘要工具原先仅判断内存列表非空，读取失败仍可能误报完成；新增失败断言复现后，要求全部PSS有效且无读取错误，独立复核通过。用新工具复算OH debug候选及Release原生/候选，均67个有效PSS、无读取错误，既有数字和失败结论不变。Dart VM CLI另有7项离线测试及静态分析通过；真实OH数据由第5/20轮握手关联，二者不混为一种验证。

测量生产修订固定为 `eaafd7d0 / 3.0.5`；后续采集工具、报告及hook版本提交不冒充重新测过的新生产构建。收尾时任务Android/OH应用与采集器均已停止、临时转发已撤销，任务模拟器保留本地测试Release安装和原数据；没有恢复旧debug包或清数据。
