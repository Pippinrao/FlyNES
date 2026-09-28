# 8.1 实施计划与执行检查单

日期：2026-09-28。用户已批准实施；[详细设计](REQ-001-007-baseline-flutter-design.md)为验收依据。
工作树固定codex/flutter-foundation。只提交本任务明确文件；不用reset/stash/clean处理其他工作。

09-29 用户后续执行要求：Mac 暂不验证；其他工作继续推进，先把模拟器上能验证的项目全部完成。OH 页面运行失败必须继续排错，不是本轮停止条件。Android 宿主和独立存档回归可并行准备，不能替代 OH 实际页面通过。真机签名、物理延迟/功耗和实机双机验收单独保留，不等待设备来阻塞模拟器验证，也不以模拟器结果替代它们。

## 顺序与工作包

- [x] 0a 核对并提交现有Flutter基础（3b4fb0fd），重新运行Check-Flutter。
- [x] 0b 合并main@3a2dc426（08eb6823），保留3.0.x，经Sync-Version及hook生成版本；内容门禁通过。
- [x] 1 REQ-001：冻结设计来源、两端实现差异、三端生产调用链和数据/线程所有者；核验文档与源码入口。
- [x] 2a REQ-002：新Android断言复现pending恢复非原子，实际RED→复用recover→GREEN。
- [x] 2b REQ-002：新断言复现有效head仍读坏旧档，实际RED→惰性旧档读取→GREEN；同时修复失败回滚后head与内存不一致。
- [x] 2c 运行独立库11/11、消费者2/2、host132/132、Android unit573项（2skip）与存档instrumentation18/18；区别既有与本次证据。
- [x] 3a REQ-003模拟器采集：Android/OH各2次预热+12次正式原生启动及65秒保存负载，实际AUTO；保留各时钟/目录口径与缺失指标，真机物理指标不在本项通过范围。
- [x] 3b 提交同设备原版数据和具体预算，在候选采集前固定诊断阈值；遵循用户继续完成模拟器验证的授权，不增设额外停工确认。
- [x] 4a REQ-004 Android/OH：锁定SDK/engine/Dart校验值、既有宿主、身份与单一版本；两端匹配Release构建和包内容核验完成。
- [ ] 4b REQ-004 iOS：宿主装配及Mac构建/签名验证；按用户要求延期。
- [x] 5 REQ-005：鸿蒙真实共享目录页→C++查询；固定SDK/API20/x64，命令构建安装与真实目录Hypium 3/3通过。游戏往返组合继续在REQ-006验证。
- [x] 6a REQ-006 Android/OH模拟器：同源码目录、原生游戏往返/后台/重复启动及失败回归；真实双App双方输入、继续、换游戏通过。
- [ ] 6b REQ-006：iOS接线及Mac实测延期；真机QR摄像头与实机双机等待设备，模拟器未认证这些项目。
- [x] 7a REQ-007 Android/OH模拟器：2.1.2→3.0.3覆盖安装保留、texture容器及生命周期验证通过。
- [x] 7b REQ-007 debug性能对照已执行：两端2+12冷启动、65秒实际自动保存、20次往返；两端PSS超预算，Android原生首卡389ms未达200ms，不能勾选性能通过。
- [x] 7c REQ-007 Release补充诊断：两端实际非debug目标同包原生/Flutter各65秒保存负载；PSS增量Android 60.13MiB、Harmony 45.29MiB，均通过预先固定的+128MiB补充阈值，不覆盖debug失败。
- [ ] 7d REQ-007完整放行：iOS、真机及未达标性能仍保留，G1不放行。

REQ004的只读工具链发现可与G0并行；REQ005执行依赖REQ004，REQ006依赖REQ005；不得以Android替代先行鸿蒙验证。
REQ003缺硬件数据仍可记录模拟器软件数据，但不能制造物理指标。8–12人日是风险验证时间盒，不是保证。

09-29早期历史结果（已由下方配对测量接续）：完整列表诊断经真实Home RED→GREEN修正，三批目录初测分别保留，第三批首卡P95 463ms，200ms门槛仍未达标；当时尚无保存负载/受控环境预算。Harmony恢复失败head一致性已实际RED→GREEN，存档9/9、UI1/1、host15/15。

OH1.0.1/API20不兼容记录保留。1.0.0/API20/x64的小栈StackOverflow已由公开独立UI线程参数解决，真实共享目录3/3通过，不改SDK或关闭assert。随后Android与OH均完成真实原生游戏往返和texture子项，但组合测试继续暴露生命周期问题：Android Swappy线程JNI引用泄漏及音频启动前取消已定向修复；OH覆盖页/真正后台的surface生命周期已修正，完整组合9/9及texture4/4通过。单次/单项成功不替代该回归。debug/profile/release工件须匹配模式及校验值，不能混入debug HAR。

Android独立AVD已完成2.1.2→3.0.3覆盖安装，存档/收藏/设置/布局/真实SAF读取全部通过，见[跨版本记录](../verification/2026-09-29-android-upgrade.md)。Harmony独立HVD也已完成2.1.2→3.0.3，含系统FILE picker真实导入、managed source身份/读取及非默认间隔。Android完整17/17、OH组合9/9+texture4/4通过；两模拟器ProductPlay最终两端各1/1，含实际音频消费、双方输入、回房间继续和同连接第二ROM。后续已冻结revision并完成受控原生测量，预先记录数值预算，再依据用户继续模拟器验证的授权采集候选，结果见下方和STATUS。Mac按用户要求跳过；真机项目保留准确限制。

## 09-29 模拟器执行补充

- 已冻结功能提交 `c0511d69`（3.0.4），两端真实覆盖升级、容器与双App玩法均有通过证据；Mac继续按用户要求延期。
- 原生受控保存采集：Android 1/1、OH 1/1，均达到65秒实际模拟并产生AUTO；OH既有音频欠载569次照实记录。Android新一批首卡P95 396ms仍不满足既有200ms。
- 统一全库对照后复现原生选择丢失；`eaafd7d0`（3.0.5）最小修复，定向RED→GREEN、583单测无失败、10UI通过。修复后两端原生启动配对批次均2预热+12正式通过，各完成65秒实际模拟及真实AUTO。Android同ROM软件输入P95 56.8125ms/PSS P95 144316KiB，OH输入上界34ms/PSS 153646KiB；本次OH欠载591次、Android保存附近播放头重置如实保留。旧失败/不同过滤或不同ROM批次是历史资料。
- 同revision的native-only Release控制包及Flutter候选已两端真实构建，保留存档/媒体修复，证据 `.artifacts/ns5/`；双ABI完整包增量Android 30.655MiB、Harmony 41.470MiB，均低于80MiB。未构建独立单ABI完整包，不冒充40MiB单ABI验收。
- [数值预算](../verification/2026-09-29-performance-budget.md)与原生结果已先行提交并固定。用户已明确要求完成模拟器全部可执行验证，继续候选采集，不再添加额外停工确认；候选失败不事后放宽阈值。采集工具已编译，不把“夹具编译成功”记作性能通过。
- 最终两端启动/保存/20往返与Release补充对照已实际执行。debug PSS失败保留；3.0.5原生首卡P95 389ms仍未达200ms。OH Ark快照接口拒绝导出时没有清数据，改用公开指定线程GC观察到两检查点计数增长，堆5→20减少123KiB；rawheap未取得仍作为限制。详细数字与剩余放行项统一见[STATUS](../STATUS.md)。

## 代码与测试边界

Android接续只改HistorySession、MainActivity初始化接线和针对性测试；库C ABI/schema不改。
使用真实NesCore/JNI/SQLite完成核心恢复断言；通过SQLite触发器拒绝head更新，确定性制造恢复提交失败，检查重开后pending/head/backup。此故障注入验证提交失败的原子性，不宣称测过真实断电。
旧档读取测试让loader抛异常，已有head时不应调用它；无head时迁移仍校验核心字节并保留原文件。
桥接和页面新增行为先写失败测试；状态转换测试不以截图替代；golden不能自动批量接受。

主要命令（工作树根）：

```powershell
pwsh -File tools/flutter/Check-Flutter.ps1
./gradlew.bat :app:testDebugUnitTest :app:assembleDebug :app:assembleDebugAndroidTest
pwsh -File tools/content/verify-builtin-content.ps1
```

Android安装/测试用新建任务专用AVD，明确serial，install -r后直接am instrument；不用会卸载App的UTP做数据保留验收。
独立库按libs/save_history/README构建、CTest、install和C/C++外部消费者；所有产物置于本工作树.artifacts/flutter-g0。
Harmony/iOS命令沿docs/DEVELOPMENT；Mac构建后再run_simulator_tests.py，不用旧测试包冒充新版本。

## 文档接续与阶段输出

更新STATUS、README和roadmap：存档已在main，REQ017复用已交付库；iOS/公共编排/Flutter历史页仍未完成。
历史references保留出处并标明非现状权威，不再维护第二份存档设计。
验证记录必须给出实际revision、变化文件、命令/结果、环境和未测项。完成状态由证据决定，不由复选框自行证明。
真机/签名/SDK/Mac阻塞需写清具体失败和下一动作；任何阻塞不授权降低G1门槛。
