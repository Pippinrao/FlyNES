# Flutter 3.0 重构工作区

从 [总路线 roadmap.md](roadmap.md) 开始，再读 [STATUS](STATUS.md) 和仓库 [AGENTS.md](../../AGENTS.md)。
用户已确定 Flutter，并授权创建分支/worktree、迁移版本到 3.0.0、搭建基础骨架；
详细需求后续分块指派。总路线不是一次性实施全部需求的授权。

| 文档 | 用途 / 权威范围 |
| --- | --- |
| [roadmap.md](roadmap.md) | 当前架构总入口；44 模块、REQ-001～045、阶段与验收 |
| [STATUS.md](STATUS.md) | 当前工作区状态、任务归属、完成证据与待接续事项 |
| [architecture-analysis.md](architecture-analysis.md) | 原代码耦合证据、底层/联机/输入/存档边界讨论；选型已由 roadmap 收敛 |
| [technology-research.md](technology-research.md) | 框架、引擎与输入组件调研过程；旧候选结论不是当前选型 |
| [references/save-history-proposal.md](references/save-history-proposal.md) | 关联存档任务设计快照；实现状态去对应任务核对 |
| [references/save-library-research.md](references/save-library-research.md) | 独立存档库与 SQLite 取舍参考 |
| [references/gameplay-usability-audit.md](references/gameplay-usability-audit.md) | 当时游戏体验静态审阅，不能冒充已复现或已修复 |
| [verification/2026-09-28-foundation.md](verification/2026-09-28-foundation.md) | 本次骨架的实际检查与明确未验收范围 |

后续详细需求/实施计划按需放 `requirements/REQ-xxx-*.md`，验证记录放 `verification/`；
这里不提前生成 45 份空文件。现行附近产品方向仍由 [nearby 入口](../nearby/README.md) 管理，
平台操作与测试见 [DEVELOPMENT](../DEVELOPMENT.md)。

文档已在本 worktree 内集中整理；原 main 和其他 worktree 的文档没有移动。
最初的 [路线入口](../superpowers/plans/2026-09-28-flutter-architecture-and-delivery-roadmap.md) 保留跳转。
后续修改只写这里的权威正文，不同步维护多份副本。
