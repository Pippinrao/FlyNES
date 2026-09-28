# Flutter 3.0 重构工作区

从 [总路线 roadmap.md](roadmap.md) 开始，再读 [STATUS](STATUS.md) 和仓库 [AGENTS.md](../../AGENTS.md)。
用户已确定 Flutter，并授权创建分支/worktree、迁移版本到 3.0.0、搭建基础骨架；
当前已批准实施8.1（REQ-001～007）；总路线其余需求不因此自动进入本轮。

| 文档 | 用途 / 权威范围 |
| --- | --- |
| [roadmap.md](roadmap.md) | 当前架构总入口；44 模块、REQ-001～045、阶段与验收 |
| [STATUS.md](STATUS.md) | 当前工作区状态、任务归属、完成证据与待接续事项 |
| [architecture-analysis.md](architecture-analysis.md) | 原代码耦合证据、底层/联机/输入/存档边界讨论；选型已由 roadmap 收敛 |
| [technology-research.md](technology-research.md) | 框架、引擎与输入组件调研过程；旧候选结论不是当前选型 |
| [当前存档契约](../../libs/save_history/README.md) | main@3a2dc426已交付库；Android/Harmony已接入，iOS未接入 |
| [8.1详细设计](requirements/REQ-001-007-baseline-flutter-design.md) | 已批准的UX、基线、接口与G1门槛 |
| [8.1执行计划](requirements/REQ-001-007-baseline-flutter-plan.md) | REQ-001～007任务检查单 |
| [references/save-history-proposal.md](references/save-history-proposal.md) | 历史设计快照，不代表当前实现 |
| [references/save-library-research.md](references/save-library-research.md) | 独立存档库与 SQLite 取舍参考 |
| [references/gameplay-usability-audit.md](references/gameplay-usability-audit.md) | 当时游戏体验静态审阅，不能冒充已复现或已修复 |
| [verification/2026-09-28-foundation.md](verification/2026-09-28-foundation.md) | 本次骨架的实际检查与明确未验收范围 |
| [存档接续验证](verification/2026-09-29-save-handoff.md) | main同步、Android失败复现/修复及本轮host/设备回归 |
| [Android原生目录初测](verification/2026-09-29-android-startup-baseline.md) | 逐次数据、未达标门槛和未测量范围 |
| [OH工具链探针](verification/2026-09-29-ohos-toolchain.md) | 固定SDK、API兼容失败/成功证据及Mac阻塞 |
| [Flutter目录页/客户端](verification/2026-09-29-flutter-catalog-client.md) | 真实投影边界、迟到结果处理、UX断言与未接线能力 |
| [Android跨版本升级](verification/2026-09-29-android-upgrade.md) | 2.1.2→3.0.3真实覆盖安装、存档和目录授权保留 |
| [Harmony跨版本升级](verification/2026-09-29-harmony-cross-version-upgrade.md) | 2.1.2→3.0.3、真实文件选择导入、存档/来源/设置保留 |
| [Flutter容器](verification/2026-09-29-flutter-texture.md) | Android external texture、输入与生命周期证据 |
| [Harmony容器](verification/2026-09-29-harmony-texture.md) | OH同源码texture页、原生媒体和20次附着释放 |

后续详细需求/实施计划按需放 `requirements/REQ-xxx-*.md`，验证记录放 `verification/`；
这里不提前生成 45 份空文件。现行附近产品方向仍由 [nearby 入口](../nearby/README.md) 管理，
平台操作与测试见 [DEVELOPMENT](../DEVELOPMENT.md)。

文档已在本 worktree 内集中整理；原 main 和其他 worktree 的文档没有移动。
最初的 [路线入口](../superpowers/plans/2026-09-28-flutter-architecture-and-delivery-roadmap.md) 保留跳转。
后续修改只写这里的权威正文，不同步维护多份副本。

- [Android ↔ Harmony 模拟器联机闭环](verification/2026-09-29-nearby-simulators.md)

- [受控 Android 原生性能基线](verification/2026-09-29-android-native-performance.md)
- [Android 3.0.5 同入口、同 ROM 配对基线](verification/2026-09-29-android-native-paired-baseline.md)
- [Harmony 3.0.5 原生启动和自动保存基线](verification/2026-09-29-ohos-native-performance.md)
- [Harmony 往返内存采集协议](verification/2026-09-29-ohos-memory-protocol.md)
- [同修订双端 Release 构建](verification/2026-09-29-matched-release-builds.md)

- [全目录选择保留修复](verification/2026-09-29-android-selection-retention.md)
- [本轮固定模拟器性能预算](verification/2026-09-29-performance-budget.md)
- [Android Flutter 候选性能](verification/2026-09-29-android-flutter-candidate-performance.md)
- [Android Release 内存对照](verification/2026-09-29-android-release-pss.md)
- [Harmony Flutter 候选性能](verification/2026-09-29-ohos-flutter-candidate-performance.md)
