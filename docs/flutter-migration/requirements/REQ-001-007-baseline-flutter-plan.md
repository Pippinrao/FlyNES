# 8.1 实施计划与执行检查单

日期：2026-09-28。用户已批准实施；[详细设计](REQ-001-007-baseline-flutter-design.md)为验收依据。
工作树固定codex/flutter-foundation。只提交本任务明确文件；不用reset/stash/clean处理其他工作。

## 顺序与工作包

- [x] 0a 核对并提交现有Flutter基础（3b4fb0fd），重新运行Check-Flutter。
- [x] 0b 合并main@3a2dc426（08eb6823），保留3.0.x，经Sync-Version及hook生成版本；内容门禁通过。
- [x] 1 REQ-001：冻结设计来源、两端实现差异、三端生产调用链和数据/线程所有者；核验文档与源码入口。
- [x] 2a REQ-002：新Android断言复现pending恢复非原子，实际RED→复用recover→GREEN。
- [x] 2b REQ-002：新断言复现有效head仍读坏旧档，实际RED→惰性旧档读取→GREEN；同时修复失败回滚后head与内存不一致。
- [x] 2c 运行独立库11/11、消费者2/2、host132/132、Android unit573项（2skip）与存档instrumentation18/18；区别既有与本次证据。
- [ ] 3a REQ-003：独立测试设备采原生冷启动至少10次，分离首屏/全目录/native时间，计入SQLite和保存开销。
- [ ] 3b 提交同设备原版数据和具体预算，请用户确认后冻结；未确认不做候选性能判定。
- [ ] 4 REQ-004：锁定OH与上游SDK/engine/Dart/插件校验值；三端既有宿主装配和签名/身份/版本单一来源。
- [ ] 5 REQ-005：鸿蒙真实共享目录页→C++查询；命令构建安装、页面断言和退出码；无设备不得通过。
- [ ] 6 REQ-006：Android/iOS同源码接线、三端原生游戏往返/后台/重复启动/失败；Mac实测；含OH真实双机。
- [ ] 7 REQ-007：旧档/新历史覆盖安装保留、texture优先容器实验、同预算性能对照；形成G1结论。

REQ004的只读工具链发现可与G0并行；REQ005执行依赖REQ004，REQ006依赖REQ005；不得以Android替代先行鸿蒙验证。
REQ003缺硬件数据仍可记录模拟器软件数据，但不能制造物理指标。8–12人日是风险验证时间盒，不是保证。

09-29更新：3a已有两批12次Android目录初测，但无历史负载/自动保存成本，首卡200ms未达标，故仍不勾选。4已排除OH1.0.1/API20，1.0.0 HAR成功，继续真实宿主验证。Mac现有SSH超时后，用户要求先不验证Mac，本轮不继续iOS执行。Harmony恢复失败head一致性须补定向验证；Android已通过不代替它。

09-29执行结果追加：完整列表诊断来源经真实Home RED→GREEN修正，第三批12次数据另存（首卡P95 463ms，仍不达标）。OH1.0.0的HAR、真实宿主和测试HAP成功，Harmony host15/15通过；但任务API20/x64上纯MaterialApp最小应用也触发StackOverflow，REQ-004/005不能放行。默认原生入口保留，实验页仅debug Want进入；非debug打包现在明确拒绝使用debug HAR。REQ-006/007依赖本轮尚未成立，不跳过鸿蒙先行条件。

下一步先解决可运行的OH组合：保留1.0.0/API20/x64最小复现，区分engine/系统版本与应用问题；用可用arm64设备验证同候选，或在独立环境验证具备所需新API的编译SDK与1.0.1，均须实际页面断言后才锁定。不得为消除红页关闭assert或篡改维护方SDK功能。随后补目录封面与现有head能力/原生启动返回，再推进Android同源码宿主。先补原生保存负载、受控设备测量和用户确认预算，再测Flutter候选性能。

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
