# Repository instructions

These instructions apply to the whole repository.

## 当前工作区：Flutter 3.0 迁移基础分支

- **用途**：本 worktree 是用户明确授权的 Flutter 三端统一迁移工作区，分支 `codex/flutter-foundation`，目录 `.worktrees/flutter-foundation`，源基线 `main@78057350c12b`。当前只搭迁移骨架，详细功能由用户后续按需求编号分块指派；不要看到总路线就自行执行全部需求。
- **版本**：用户已明确授权从 2.x 迁到 **3.0.0**，当前 `VERSION_MAJOR=3`，Android/Harmony versionCode 为 `3000000`。继续遵守下方版本规则，不再改 major。正常提交会由 hook 递增 PATCH；不要为保持 3.0.0 绕过 hook。本次基础改动尚未提交。
- **先读入口**：[重构文档索引](docs/flutter-migration/README.md) → [总路线 / REQ-001～045](docs/flutter-migration/roadmap.md) → [当前进度与协作登记](docs/flutter-migration/STATUS.md)。用户最初指定的 `docs/superpowers/plans/2026-09-28-flutter-architecture-and-delivery-roadmap.md` 保留为跳转入口；只维护集中目录中的正文。
- **已完成的基础**：`ui/flutter/` Flutter module、最小 App/主题/启动页、原生客户端边界说明、widget smoke test、`tools/flutter/Check-Flutter.ps1`；Flutter 3.41.7 / Dart 3.11.5 下格式、静态检查和组件测试通过，版本脚本测试 5/5。详见 [验证记录](docs/flutter-migration/verification/2026-09-28-foundation.md)。
- **尚未完成**：三端生产宿主嵌入、Flutter-OH SDK/插件配套、真实 C ABI 接线、游戏页面、目录/存档/联机 UI 迁移，以及三端安装/游戏验收。上游生成的 `.android/` / `.ios/` 是忽略的开发宿主，不能当生产 App；当前无已验证的鸿蒙 Flutter 宿主。不要把骨架测试算作 G1 或三端迁移通过。
- **选型与边界**：Flutter 已定；公共业务、输入、运行与媒体契约留 C++，Nearby 和 save_history 独立。页面不访问核心/SQLite/QUIC；不在 Dart 建另一份目录、存档 head 或房间状态机。详细模块边界以总路线为准。
- **关联存档任务**：`codex/save-history` 在另一个 worktree 开发，最新已知范围 Android/鸿蒙优先、iOS 后续；本 worktree 没有合入它的代码。`docs/flutter-migration/references/` 是设计参考快照，不能作为该任务当前完成情况。按 REQ-002 核对实际交付 revision/测试后再集成；不修改另一 worktree 的文件。

### 多会话协作方式

1. 开工先确认 `git branch --show-current`、`git status --short` 和 STATUS，识别已有未提交改动；本授权是下方旧“从 main 工作”规则的明确例外，不要切回 main 或另建分支，除非用户再次要求。
2. 只认领用户指派的 REQ 或明确基础工作。将任务链接、涉及目录/共享接口、状态与依赖登记到 STATUS。STATUS 是协作记录，不是自动互斥锁；同文件/同 ABI 已有在做任务时先协调归属，不覆盖其工作。
3. 共享热点包括 `AGENTS.md`、STATUS、总路线、应用 ABI、Flutter pubspec/lock、根 CMake 和版本文件。按最小范围编辑，不做无关格式化/移动；不要批量 stage、reset、stash 或清理其他会话的变更。
4. 新增详细设计和执行计划放在 `docs/flutter-migration/requirements/REQ-xxx-*.md`，证据放 `docs/flutter-migration/verification/`；引用稳定 REQ 编号，不另起竞争总路线。具体需求未指派时不预建空文档/空实现。
5. 完成后更新 STATUS：实现范围、验证命令与结果、未测项、版本/提交信息、后续依赖；阶段验收不足时保持“部分完成/待验证”，不能仅凭代码或构建转为完成。
6. 当前入口检查：仓库根目录运行 `pwsh -File tools/flutter/Check-Flutter.ps1`。原生功能修改再按下方平台规则和 DEVELOPMENT 运行受影响测试；不以 Flutter widget test 替代原生或实机验收。

## What this repository is

FlyNES is an offline NES/Famicom emulator for **Android, HarmonyOS NEXT, and
iOS**: one shared C++ core (NestopiaUE) plus a shared product layer, with a
native UI per platform. It bundles seven licensed homebrew games declared once in
`content/assets/builtin-games.json`; users import their own ROMs.

Layout: `core/` (platform-free emulation + `nes_*` ABI), `shared/`
(cross-platform product layer + `fly_*` app ABI), `app/` Android, `harmony/`
HarmonyOS, `ios/` iOS, `content/` bundled-game source of truth,
`tools/content|versioning|quality/`, `docs/`.

**Read [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) before platform work.** It
holds the per-platform build, test, and debug commands, the toolchain versions,
the traps that have already cost this repo time, and the invariants the gates
enforce (no product source may name a bundled game; no platform may keep its own
ROM copy; the retired bundled game must stay deleted, binary assets included).

Local-only helper scripts that operate on a private ROM collection live in
`ios/scripts/local/` and are git-ignored on purpose: never commit them, and
never move their inputs into `content/`.

## Preserve local state

- Keep unrelated user changes and untracked evidence. Never clean, reset, stash, move, or delete another worktree's files.
- Never print or commit signing profiles, keystores, passwords, device credentials, private ROMs, or generated packages.
- Build outputs and local evidence belong under ignored directories.

## Version policy

- `VERSION` is the single semantic version source. `VERSION_MAJOR` is the protected major line.
- Only the user may authorize a major-version change. Agents and automation must keep the major unchanged unless the current conversation contains that explicit instruction.
- Install the repository hook with `tools/versioning/Install-GitHooks.ps1`. The pre-commit hook increments PATCH once for every new commit and synchronizes Android and HarmonyOS metadata.
- Create worktrees only with `tools/versioning/New-VersionedWorktree.ps1`; do not call `git worktree add` directly. The allocator serializes access through the shared Git directory and reserves a unique MINOR line.
- Do not hand-edit platform `versionName` or `versionCode`. Run `tools/versioning/Sync-Version.ps1` after an authorized version change.
- Version codes use `major * 1,000,000 + minor * 1,000 + patch`; MINOR and PATCH are limited to 0–999.

## Change and verification policy

### Current nearby direction (2026-09-23 user direction)

- Work from the consolidated `main`; do not reopen retired worktrees or start parallel branches without a new user request.
- Read `docs/nearby/README.md` first. It is the only current nearby design/plan entry; `docs/archive/nearby-2026-09-21/` and old task prompts are historical references, not instructions.
- The Android host/P1 to HarmonyOS guest/P2 hotspot flow is the existing playable baseline, not the target role restriction. The next nearby UX and implementation target allows Android, HarmonyOS NEXT, and iOS each to host or join, over a shared router LAN or a hotspot. Prefer an available LAN; if none is available, Android hosts automatically attempt a local-only hotspot through the public API, while unsupported or other-platform hosts receive inline hotspot setup guidance. Use one QR pairing path only. Remove friends, Bluetooth discovery, and pairing-code product features rather than keeping placeholder controls. Read the current target in `docs/superpowers/specs/2026-09-23-nearby-three-platform-ux-design.md`. STREAM, ROM transfer, and automatic recovery remain later work.
- First consolidate repository state, then design from that baseline. Repository/document cleanup does not require full product test runs.
- During implementation fix the current playable-path blocker and run the affected checks. Expand testing only for a concrete regression risk; do not start unrelated full-platform sweeps or exhaustive edge-case projects.
- Report progress by two real apps connecting, loading the same ROM, accepting both players' input, and playing. A mock/loopback test, ABI declaration, build or merged branch is not that outcome.

- Use test-driven development for product behavior and bug fixes: demonstrate the failing assertion, implement the smallest fix, then run the relevant regression suite.
- Android shared/native changes require host tests and Android unit tests; UI changes require the emulator instrumentation suite.
- Harmony changes require host CTest, Hypium, and a signed-device install when a compatible device is connected. Emulator results never certify physical refresh rate, power, temperature, or latency.
- Do not enable Extreme or other hardware-qualified modes without matching device evidence. Unsupported paths must expose a reason and fall back safely.
- Nearby multiplayer is outside ordinary emulator/rendering work unless the user explicitly includes it.

## Release policy

- Release from `main` with a clean tracked tree and a version-matching tag.
- Sideload packages may use a documented local test signature. Never describe that signature as a store or production certificate.
- Publish source revision, package hashes, test results, and any device-specific install restriction with the artifacts.
