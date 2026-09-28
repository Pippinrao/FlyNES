# 存档合入与 Android 接续验证

日期：2026-09-28～29。范围：REQ-001/002 的源码基线和 Android 定向修复；不是 G1 放行报告。

## 版本与范围

现有 Flutter 工作树的基础、文档、3.x 版本由 `3b4fb0fd` 单独提交；随后合入本地主干 `3a2dc426`，形成 `08eb6823`。合并仅版本文件冲突，保留 Flutter 3.x 并经 Sync-Version/hook 生成 3.0.2。没有从旧存档工作树复制文件，没有改 main 或新建分支。当前代码验证基于该合并提交加本报告所述差异；后续提交的 PATCH 变化不等于重新构建过这些测试 APK。

当前 UX/调用图/数据所有者已记录在 [8.1 设计](../requirements/REQ-001-007-baseline-flutter-design.md)，包括可点击的原始设计、批准修订和三端代码入口。历史 references 已标注资料年代；路线的 REQ-017 改为接续已有成果。新库 schema、ABI、存档格式及 key 未改。

## 实际 RED → GREEN

| 故障 | 原版失败证据 | 最小修复及回归 |
| --- | --- | --- |
| 中断恢复先 cancel 再 setHead | SQLite 触发器拒绝 head 更新；旧实现已清 pending，断言 expected 1 / actual 0 | 初始化读取保护点后调用已有 `HistoryStore.recover` → `sh_recover_restore`；失败保留 pending，关闭重开后移除故障可重试 |
| 新 head 有效却先读取坏旧档 | MainActivity 启动时把旧档路径设为目录，实际 FileNotFoundException/EISDIR；历史对话框缺失 | 把 IOException 可传播的 LegacyLoader 延迟到确认无 head 后调用；已有 head 不碰旧档；无 head 仍验证并幂等迁移 |
| 恢复失败后内存与持久继续位置不同 | 原版回滚到实时进度，但 head 仍指向更早记录，新增字节比较失败 | 回滚内存后用 recover 发布相同保护点，更新 parent/session/clock；发布失败保留 pending；回滚本身失败不清操作 |

故障注入是确定性的数据库写失败与核心无效状态，不宣称实测了物理断电。真实 JNI、私有 SQLite 和 NesCore 参与测试；没有用 mock 替代持久化断言。旧文件保留、恢复选中 head、重开保留 SRAM 等已有测试同时回归。

## 本轮运行结果

| 检查 | 结果 |
| --- | --- |
| Flutter 基础 Check-Flutter | format、analyze、widget 1/1 通过；本轮未改变 Dart 产品页 |
| 内容唯一来源门禁 | 7 款内置游戏检查通过 |
| 独立 save_history | Release CTest 11/11 通过，含 kill-transaction；这是本轮重跑 |
| 外部消费者 | 安装独立库后 C、C++ 消费者 2/2 通过 |
| shared host | Release CTest 132/132 通过；本轮运行，不替代两个真实 App 联机验收 |
| Android 单元 | 573 项，0 failure、0 error、2 skipped（其余 571 通过） |
| Android 新回归 RED | 3 项全部按预期失败 |
| Android 存档 instrumentation GREEN | 18/18 通过 |
| Android 目录既有性能回归 | 1/1 通过；coldLibrary 470/453/440ms，20 次导航 1/0/0ms；不是启动首屏口径 |
| 独立复核 | 规范与代码质量各一次只读审阅，未发现阻断问题；审阅未重跑测试 |

Android 使用新建的任务专用空白 AVD `FlyNES_FlutterG0_20260928` / `emulator-5582`；未对用户已有设备卸载、清数据或迁移文件。构建采用 JDK 21.0.11 + Gradle 8.14.3，因为本机未找到指南所述 JDK17。实际包以构建日志和 APK 哈希为准，不称为生产签名。

在仓库工作树内构建后，使用明确 serial 安装本任务 APK，并直接运行 instrumentation，避免 UTP 默认卸载破坏后续升级证据。可重复命令：

```powershell
./gradlew.bat :app:testDebugUnitTest :app:assembleDebug :app:assembleDebugAndroidTest
adb -s emulator-5582 install -r app/build/outputs/apk/debug/app-debug.apk
adb -s emulator-5582 install -r app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk
adb -s emulator-5582 shell am instrument -w -r -e package com.flynes.emu.save `
  com.flynes.emu.test/androidx.test.runner.AndroidJUnitRunner
adb -s emulator-5582 shell am instrument -w -r -e class `
  'com.flynes.emu.catalog.android.AndroidLargeCatalogPerformanceTest#coldLibraryAndRepeatedNavigationWith2224Games' `
  com.flynes.emu.test/androidx.test.runner.AndroidJUnitRunner
```

仅凭 adb 退出码不能认为 instrumentation 通过；本轮读取 `OK (18 tests)` / `OK (1 test)` 和失败断言。原始日志在忽略目录 `.artifacts/flutter-g0/android-save/`：`red-regressions.log`、`red-logcat.log`、`green-save-suite.log`、`green-build-unit.log`、`unit-counts.json`、`catalog-performance.log`、`home-start-markers.log`。host 日志在 `.artifacts/flutter-g0/host/`。

## 剩余验收

本次使用空白测试设备验证接续故障，**不等于**从 2.1.2 用户安装覆盖到 Flutter 的数据/来源授权保留验收。Android 旧档保留与恢复测试不能替代三端覆盖矩阵。Harmony 当前初始化已 lazy + recover，但恢复失败后的 head 一致性还需定向验证；iOS 仍为旧单槽，本轮没有执行机证据。

REQ-003 目录启动采集见单独报告；自动保存停帧、音频、输入、真机容器、同连接双机游戏和 iOS 均未由这些测试证明。REQ-002 的 Android 接续子项可关闭，整体 G1 继续保持未通过。
