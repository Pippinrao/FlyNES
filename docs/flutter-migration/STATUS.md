# 工作区进度与协作登记

更新日期：2026-10-01。工作区 `.worktrees/flutter-foundation`，分支 `codex/flutter-foundation`。
原生基线 `main@3a2dc426`（2.1.2）；Flutter基础 `3b4fb0fd`；合并提交 `08eb6823`。
当前版本以根VERSION为准（3.0.x，hook正常递增）；创建起点78057350保留为历史。

## 当前授权与进度

2026-10-01 iOS 接续：用户已恢复 iOS G0/G1/G2 授权。macOS 13.7.8 无法启动 Flutter 3.41.7；iOS 独立固定 Flutter 3.38.10 / Dart 3.10.9，Android/OH 工具链不变。Mac Dart 197/197、analyze、旧 SDK 语义 6/6；最终方向边沿修正后受影响原生 29/29。普通启动 Flutter，大厅/游戏、暂停/设置及暂停/布局各 20 次，后台与进程重建、同局语言刷新均有真实所有者断言。真实 Files、目录、ZIP、权限拒绝与重新授权、扫描离页/返回可见状态均通过；旧单槽、收藏、设置、布局及来源授权覆盖安装保留。199 静态+81 动画及完整语义严格比较通过；iOS 同环境 62 图审阅与独立复采通过，五个原生交接窗口 126 帧另行审阅。双 App 最终正反角色各两项真实 UI 通过；两轮各 30 张截图及 15 组严格更晚帧释放记录经独立审阅，确认 HUMAN 擂台、双方输入、回房继续和同连接换 ROM。最终 3.0.8 模拟器包已覆盖安装至两台任务模拟器，普通启动均显示 Flutter 大厅，78 个包内文件与冻结清单一致，持久文件和旧档保留。iphoneos arm64 Release 原生/Flutter 包均已构建且未签名；单架构压缩增量 6.31 MiB。成对 Debug 诊断采集完成，但首屏交互、Release PSS、可验证 GC 后残留及真机时延仍未测，性能门禁 **not_evaluated**，故**不宣称 iOS G0/G1/G2 整体验收**。iOS 仍使用旧单槽，没有历史 head/pending。详细证据见 [iOS 实施记录](verification/2026-09-30-ios-migration.md)及 [UX/动画追溯](verification/2026-10-01-ios-ux-traceability.md)。以下 iOS 延期为历史状态。

2026-09-30：用户已批准实施 [G2 设计](requirements/REQ-008-012-030-031-g2-design.md) 与 [执行清单](requirements/REQ-008-012-030-031-g2-plan.md)。G2 产品实现基线提交为 `c27cc7fc`（3.0.7）；当前版本始终以根 `VERSION` 为准。**G2 两端模拟器尚未整体验收**：本机只有 HarmonyOS API20 手机镜像，系统不支持手机目录选择／重新授权的真实验证，不能用文件导入替代。iOS 延期，G1 首卡 200ms 和 debug PSS 历史失败不变。

当前收尾证据：Flutter 格式、analyze、192/192 widget 通过；199 张经审阅静态金标与 81 张受控动画帧重采严格比较通过。Android 相关 unit 目标成功，quiet-04 的成对 Release 启动、65 秒 AUTO、PSS 与 20 次可验证 GC 往返均通过冻结预算。Harmony Release 产品回归 4/4（含两组 20 次往返）、Debug 专用故障注入 1/1、host CTest 17/17、Node 108/108、工具 Python 88/88；同包配对 Release 启动、AUTO、PSS、输入／帧／音频及堆增长均通过预先冻结预算。两端 U26 进程重建和 U04/U24 历史返回、新封面证据已完成独立复核；原整数封面匹配失败及亚像素几何解释均保留。G1→G2 覆盖升级与双向模拟器联机的既有记录仍有效。包体和最终包安装须以最终提交修订的 `.artifacts/flutter-g2/final-handoff.json` 为准；本文件不把预提交包哈希冒充最终工件。未支持的系统目录流程及 iOS 继续列为缺项。

以下分段保留当时的 RED、修正与阶段结论；以上最新状态优先，旧段落的“待采集”不表示后续未采集。

两端普通启动已经进入同一份 Flutter 大厅；来源、五分区基础设置、许可与原生布局/游戏返回已接线。Android 20次大厅/游戏及20次暂停/设置/布局回归通过；Harmony最新 Hypium 5/5也含两组20次循环、同引擎/View、核心/音频/暂停计时断言。它们是功能证据，尚非 Release 内存放行。Android暂停切换语言重建ROM、呈现旧设置/黑帧已实际RED→GREEN；最新呈现回归5/5及录像审阅通过。

最新整套 Flutter 192/192；静态分析无问题。受影响 Release host8/8、适配器边界5/5；Android最新unit639项/0失败/2历史skip。Harmony来源取消/补偿21/21 Node通过，涵盖重复目录UUID、失效授权、部分成功、取消保留旧库、提交边界及真实目录选择能力。Harmony最新Debug host17/17通过，取消清库修复已安装；实际400个测试ZIP的扫描取消及离页返回继续观察通过，取消前后目录、来源映射、内容key和用户状态相等，测试副本已定向清理。

194张固定场景图已逐张独立审阅，并按批准哈希冻结到 `ui/flutter/verification/goldens/`，独立重采严格比较：页面108/108、状态42/42、伪本地化18/18、补充状态26/26。通道8/超差0.5%/边界1px未放宽；字体准备脚本校验SDK与模拟器字体哈希。54张动画帧另有审阅。真实Harmony核心28图（大厅、五设置、许可×zh/en×100/200）和来源能力/扫描取消/离页观察图已打开审阅；Android此前真实核心图另有审阅。完整原生交接动画、剩余状态和操作证据仍在补齐。

[Android G1 Release→G2数据保留](verification/2026-09-30-g2-android-upgrade.md)已实际seed2/2、verify2/2；[Harmony G1→G2覆盖升级](verification/2026-09-30-g2-harmony-upgrade.md)seed/verify各1/1通过，两端均未卸载/清数据规避。双向真实联机四角色均已通过并独立审阅（含真实Flutter两次选游戏、双方输入、暂停回房间和同连接换ROM）。Harmony真实系统文件/ZIP导入、重复导入、取消、移除及身份/收藏保留已验证；API20手机镜像不支持真正的目录选择/重授权，不能以文件导入替代此缺项。Release成对性能/包体、最终精确revision工件安装仍未完成。详细事实与失败记录见 [G2实施记录](verification/2026-09-30-g2-implementation.md)。

Android 首轮 G2 Release 配对（`release-paired-quiet-01`）已有独立原始数据复核：两组启动各2次预热+12次正式；native-ready P95 1007ms 超过原生推导844.7ms，失败。两组65秒均实际产生AUTO，PSS P95增量67575KiB（约66MiB）在128MiB内，输入/帧P95/音频计数门槛通过；保存窗口最大间隔108.1483ms超过103.9547ms，失败。原生交互约6.2秒含ActivityScenario等待上界，不能当真实首屏延迟；后续需修正夹具重新配对，原批次保留。往返第10次输入早于宿主转场结束，只有9次和第5次GC，不能认证残留；夹具就绪条件修正后正单独补采，尚不放行。

后续 Android `release-memory-quiet-02` 同主包20/20通过，可验证GC后ART堆增长1,853,136B（1.77MiB），旧宿主和音频线程无残留。`release-paired-quiet-03` 使用修正可见性观察夹具及默认关闭的保存阶段诊断，新主包 SHA256 `1BA90729B74393B65F3E65BCD4FBD660A16F01FC9F9C481E939BBA188B6B7630`；两组2+12启动有效，Flutter请求后2492ms、进程后2697ms、owner-ready759ms均通过本批预冻结预算。两组65秒均有效且产生AUTO，保存窗口97.5791ms仍超过88.7473ms，失败；20次往返GC后ART增长915,168B（0.87MiB）通过。没有生产启动优化，不把旧ready失败消失归因于优化；旧批次全部保留。新的保存阶段数据用于定位，不能豁免超标。

OH实际compositor帧复现暂停→设置时旧大厅闪现；已接入当前宿主token+raster握手和短期原暂停截图遮罩，17条相关Node通过，旧大厅在最新采样中消失且经独立逐图审阅。门禁初版真实功能回归5/5（315.883秒）含两组20次；随后snapshot→Resume竞争修正另有2业务RED和最新采样证据。当前Release主包 `9396ce204df0089ba5539e7429295da2c170cd37bdeb32605f1267eec2494c0a` 已实际安装，但新增发现**游戏回大厅有空白过渡、Release原生游戏黑屏/异常像素**，系统截图已交叉确认，呈现计数未报错。正在分层诊断，不能把构建、循环或计数成功写成Release可玩/视觉通过；OH性能尚未采集。Android已实施AUTO暂停区间最小修正，643 JVM、15设备、28Python通过。quiet-04已完成31次instrumentation并独立核对107原始文件哈希：Flutter启动P95 2725≤2987ms、请求后2518≤4000ms、owner-ready767≤1079ms；两组65秒真实AUTO，保存窗口78.6277≤84.6017ms，PSS增量64390KiB；20次GC后ART增长870128B（0.83MiB），均通过本批冻结门槛。首core回调仍晚于store结束，不能宣称IO/核心实测重叠或单轮因果。Android包体对照配方15测试与独立审阅通过，最终同revision包体未测。

追加验证：许可异步淡变、设置分区/许可列表及正文滚动恢复均有业务RED→GREEN；按下中的按钮被禁用触发Flutter树锁异常已最小修正，动画中点返回/后台/销毁回归通过。受控动画扩到81帧（含路由真正settled语义），新增5个许可/部分重置错误状态；新金标仍须完成独立差异审阅后冻结，旧194图不冒充新增覆盖。

OH黑屏已定位为上传纹理正确但最终采样异常：保留CPU、纹理FBO及默认帧缓冲原始像素，重绑、uniform切换及sampler解绑均无效，同纹理换最终呈现unit1恢复。移除全部诊断读回后，最小unit1候选完成20次真实游戏往返、每次实屏颜色断言和独立逐图/数值复核；设置→游戏及暂停→设置各36张实际采样也恢复正常。未宣称底层驱动根因或连续所有显示帧通过。当前刷新Release主包SHA256 `63859C986FC0E6472C244A4FE8581DB7B2C871F47B61CD96704BF6FF904CC799` 已覆盖安装，完整G2循环回归在执行，性能尚未采集。相关host17/17、产品Node68/68、像素校验器5/5通过；旧9396/80c4及黑屏证据保留。

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
| REQ-006 三端往返+双机 | Android/OH 模拟器功能与双机通过；iOS 模拟器功能通过；三端整体未放行 | [Android17/17](verification/2026-09-29-android-foundation.md)含20次往返；OH完整9/9+texture4/4；[真实跨App ProductPlay](verification/2026-09-29-nearby-simulators.md)含双方输入、音频、回房继续和同连接换ROM；[iOS接续](verification/2026-09-30-ios-migration.md)含两组20次往返、正反双App实际擂台及最终包普通启动。三端真机／性能门禁未完成 |
| REQ-007 升级+容器+性能 | 本轮Android/OH模拟器验证完成；性能仍有未达标项 | [Android跨版本](verification/2026-09-29-android-upgrade.md)及[Harmony跨版本](verification/2026-09-29-harmony-cross-version-upgrade.md)均为2.1.2→3.0.3真实覆盖。两端候选启动、65秒自动保存、20往返已实际执行。Android/OH debug PSS P95分别335645/350956KiB，均超固定阈值；启动、保存上下文、软件输入在阈值内。Android ART GC后增长72KiB；OH公开指定线程GC后Ark增长-123KiB，快照导出失败单列。[Android Release对照](verification/2026-09-29-android-release-pss.md)同模式增量60.13MiB、[OH Release对照](verification/2026-09-29-ohos-flutter-candidate-performance.md)增量45.29MiB均通过补充诊断，不覆盖debug失败 |
| G1总体 | 未通过 | Android/OH 保留 debug PSS 和原生首卡历史失败；iOS 模拟器功能及覆盖安装已补验，iOS Debug RSS 为诊断、性能门禁未评估。三端真机签名覆盖、摄像头 QR 与物理媒体指标仍按设备条件待验；OH 堆快照导出不可用，公开 GC 后数值另列 |

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
