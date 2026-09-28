# Save History Implementation Plan

> **For agentic workers:** Use subagent-driven-development for bounded implementation and independent reviews. Use TDD: run the failing assertion before production changes.

**Goal:** Ship an independently consumable SQLite-backed save history library, integrate automatic/manual saves, history restore and protected restart into the three single-player apps, and pass relevant simulator tests.

**Architecture:** `libs/save_history` owns opaque bytes, metadata, transactional history/head/protection/retention. It has no FlyNES or platform dependencies. Platform adapters serialize the existing core on its owning executor; UI and lifecycle trigger those adapters. Existing single-slot files migrate without deletion. Stage detection and multiplayer restore remain excluded.

**Tech Stack:** C++17, C ABI, vendored pinned SQLite amalgamation, CMake/CTest; Java/JNI, ObjC++/Swift, ArkTS/N-API.

## Task 1: Independent store

Files: `libs/save_history/CMakeLists.txt`, `include/save_history/save_history.h`, `src/*.cpp`, `tests/*`, `examples/*`, `vendor/sqlite/*`.

- [ ] Write C ABI contract and runnable failing behavior test. An open/create/read/list API initially reports unsupported so `CHECK(sh_open(...) == SH_OK)` fails as an assertion, not a missing compiler symbol.
- [ ] Implement SQLite open, immutable opaque record insert/read/list, metadata, protected flags and persistent resume head. Test bytes before/after close/reopen and content/format isolation.
- [ ] Add failing tests for 60-record retention excluding pinned/manual/head/protection references, byte quotas with rollback, deletion protections, label updates and integrity mismatch; implement transactions and validation.
- [ ] Add failing tests for prepare/finish/cancel restore and idempotency; preserve pre-restore backup and original head until success. Test a killed writer transaction, database migration and failed commit.
- [ ] Configure/build/test using host CMake under `.artifacts/save-history-host`; install under `.artifacts/save-history-install`, build and run an external C/C++ consumer through `find_package`. No NES headers/libraries may be available to that consumer.
- [ ] Document vendored source URL/checksum/license and API lifetime/error contracts. Independently review spec then code quality before integration.

## Task 2: Shared integration contract and timing

Files: `shared/include/flynes/product/save_history_policy.hpp`, `shared/tests/test_save_history_policy.cpp`, affected CMake target wiring and pause action contracts.

- [ ] Failing assertions: `advance(59000)` not due, another `1000` due; paused elapsed contributes zero; save acknowledges elapsed; duplicate frame identity does not create another automatic record; 30/60/120/300-second selection and off are deterministic.
- [ ] Implement a header-only policy without system clock or platform dependencies; callers supply elapsed milliseconds and frame/session identity. Build a focused host test.
- [ ] Expand single-player pause menu model for save/history/restart while retaining the existing multiplayer three-command projection. Update existing assertions through red/green.

## Task 3: iOS adapter and interface

Files: `ios/app/run/SaveHistoryAdapter.*`, `RunSurfaceViewController.*`, history UI files, `CatalogGameDetailView.swift`, `CatalogLibraryView.swift`, strings/CMake, `ios/tests/SaveHistory*Tests.mm`.

- [ ] Write XCTest assertions using isolated store and real runtime: save progressed state, advance, restore and compare next frame; preserve old legacy file; restart then reopen resumes fresh round; cancel leaves current state.
- [ ] Observe failure on rebuilt simulator test target; implement thin adapter over C ABI, content/format keys and protected restore/restart.
- [ ] Add visible manual save/history/rename/protect/delete/restore/restart controls with screenshots and metadata, confirmation and failure states. Game detail exposes history/fresh launch; never call store from audio callback.
- [ ] Add timed and lifecycle capture, interval settings, migration and selected-head resume. Test running-time accounting and failure/retry behavior.
- [ ] Build on isolated Mac source directory using repository scripts. Run relevant runtime and UI XCTest suites on an isolated iPhone simulator. Preserve existing app data elsewhere.

## Task 4: Android adapter and interface

Files: `app/src/main/cpp/save_history_jni.cpp`, native CMake, `app/src/main/java/com/flynes/emu/save/*`, `MainActivity.java`, `HomeActivity.java`, strings and Android tests.

- [ ] Write Android unit/instrumentation tests for isolated store, migration, real core restore/restart and visible history workflow; capture red output.
- [ ] Implement JNI bridge, adapter and controls matching iOS behavior while keeping current single-threaded core ownership and battery save semantics.
- [ ] Run host tests and `:app:testDebugUnitTest`; build both APKs, install/run directly on isolated AVD, assert runner result and actual play/restore/restart navigation.

## Task 5: Harmony adapter and interface

Files: `harmony/entry/src/main/cpp/save_history_napi.*`, CMake/typings, `ets/service/SaveHistoryService.ets`, `pages/RunGame.ets`, `pages/GameCenter.ets`, settings/resources, Hypium and host tests.

- [ ] Write failing host/Hypium cases for real save history, protected restore/restart, legacy migration and pause/back/background saving.
- [ ] Implement adapter and parity UI using opaque checkpoint format; wire lifecycle at safe frame boundaries.
- [ ] Run CTest, build Hypium module and execute on isolated Harmony simulator; check assertion report. Check connected compatible physical device and install signed build if available, without clearing existing data.

## Task 6: Integration and review

- [ ] Verify independent consumer, library failure tests, shared policy tests and affected platform suites; no unrelated rendering certification sweeps.
- [ ] Spec review followed by quality review; fix each actionable finding using failing regression test.
- [ ] Record exact commands, red/green results, simulator targets and limitations in `docs/verification/2026-09-28-save-history-implementation.md`.
- [ ] Commit cohesive changes with repository hook/version increment, keep worktree/branch available for user review; do not merge or release automatically.

## Execution notes

2026-09-28: User authorized feature branch/worktree and implementation with TDD plus simulator acceptance. Worktree allocator created `codex/save-history` at `.worktrees/save-history`, version line 2.1. No untracked source-workspace documents outside this feature were copied or changed.

## 执行范围更新（2026-09-28）

用户明确先做鸿蒙、安卓。当前隔离分支 `codex/save-history`，worktree `.worktrees/save-history`，版本由仓库分配器分配为 2.1.0。iOS 步骤保留为后续工作，不属于本轮完成判定。新建模拟器使用隔离数据，不覆盖已有模拟器或用户存档。关卡识别没有通用信号，本轮实现按实际模拟运行时间自动保存及手动历史回退。

用户最新 UI 反馈：移除 Android、HarmonyOS 游戏中心的“存档记录”“从头开始”两个按钮，仅在游戏内暂停菜单保留。已按新的不存在断言完成红灯与绿灯验证。最初共享时钟头文件原型未成为产品依赖，已移除；平台适配器分别按核心实际帧数计时，独立库只处理存储与保留策略。完成状态与限制见 docs/verification/2026-09-28-save-history-android-harmony.md。
