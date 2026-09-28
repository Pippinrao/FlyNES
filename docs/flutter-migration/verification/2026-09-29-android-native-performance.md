# Android 原生性能基线（受控模拟器窗口）

本页保留 `c0511d69 / 3.0.4` 历史批次及200ms门槛失败证据。当前候选应使用[3.0.5同入口、同ROM配对基线](2026-09-29-android-native-paired-baseline.md)，不能将本页不同过滤条件、不同ROM的数据直接相减。

2026-09-29，代码 `c0511d69`，版本 3.0.4。两端构建、覆盖升级和联机测试结束后串行测量；未并行运行构建或其他设备测试。Windows 宿主及闲置模拟器仍可能产生系统噪声，本记录不认证真机性能。

## 工件与场景

- 任务 AVD `emulator-5582`，API 35 / x86_64，debug。APK SHA-256 `76F73DF423F413804E54ACABB3E1F9291A2524E99274CD08123F358E1FAB6E31`；设备实际 base.apk SHA 已独立核对一致。
- 测试 APK SHA-256 `35301086660C81A089FA0D9CF86FC86467CF27527B5030409A8E04E9CF9B39D7`。同一个生产 APK 的原生入口按需创建 FlutterEngine，本次没有打开 Flutter 页面；存档实现与后续候选共用。
- 原生大厅保留已有 2231 行任务目录，未清除数据或重新播种；当时保留 BUILTIN 导航，完整过滤列表为 7 卡。后续同入口对照须统一 ALL/空搜索，不能把不同过滤条件当作同口径对比。进程冷启动（不是首次安装）：2 次预热 + 12 次测量，各次 force-stop 后启动 HomeActivity。未将 dexopt 推断为历史 speed AOT。
- 游戏负载采用清单中的真实许可 ROM，实际内容 key `44B6EDDE58C039DD24C6F78B792555531101CD1E`；历史 2→3 条，60 秒自动保存保持开启。测试退出恢复用户原设置，真实新增历史保留。

## 原始结果

启动使用进程启动时钟及生产诊断标记，P95 为 nearest-rank：

| 指标 | P95 |
| --- | ---: |
| 缓存首卡 pre-draw | 396 ms |
| 首个可见、enabled、有点击监听的主操作 | 1174 ms |
| 完整目录投影可用 | 339 ms |
| 完整列表首卡 pre-draw | 1174 ms |
| 原生服务就绪 | 2030 ms |
| 启动后短暂稳定 PSS | 166252 KiB |

首卡原有 200ms 门槛 **失败**。完整目录可用不等于所有卡片已渲染；主按钮交互标记不等于原生启动校验已完成。首卡 396ms 与主按钮 1174ms 是不同边界，不能混用。

原生自动保存采集 instrumentation **1/1 通过**，67.803 秒；有效模拟运行 65640ms，测量墙钟 65583ms，新增 AUTO 记录 1 条。两种时钟的轻微差别来自模拟时钟采样边界。

| 指标 | P95 | 最大值 |
| --- | ---: | ---: |
| 核心帧回调间隔 | 62.480 ms | 67.465 ms |
| 保存记录时间前后各 2 秒内的核心帧回调间隔 | 62.001 ms | 63.555 ms |
| 软件触控分派到核心采样 | 57.333 ms | 65.186 ms |
| 游戏 PSS | 136724 KiB | 138154 KiB |
| Java 已用堆 | 41178320 bytes | 42615568 bytes |
| Native 分配堆 | 33897872 bytes | 33999136 bytes |

1 秒采样观察到音频欠载增量 0、计数重置 0。该计数仍是观测下界，不能代替听感或硬件音频质量验收。核心回调以音频驱动批次推进，其间隔不是屏幕逐帧呈现间隔，不应拿 62ms 解释为显示 FPS。保存窗口只表示时间相关，不证明所有停顿由 SQLite 导致。本次每秒观测的 actualPresentationCount 均为 0；模拟器的 EGL 呈现时间查询报不支持/无效 surface，因此没有可信的逐帧呈现时间样本，不能补零或宣称屏幕帧节奏通过。

## 命令与证据

证据均在 ignored `.artifacts/flutter-g0/performance-c0511d69/`：`android-native-save-test.log`、`android-native-save.json`、`android-native-logcat.log`、`android-native-summary.json`、`native-startup/report.json`、`android-installed-sha.txt`、`android-package.txt` 和 `revision.txt`。

```powershell
$perfAdb = "$env:LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe"
& $perfAdb -s emulator-5582 shell am instrument -w -r -e g1NativePerformance true -e g1Entry native -e class com.flynes.emu.G1NativeSavePerformanceTest com.flynes.emu.test/com.flynes.emu.test.SingleDeviceCertificationRunner
py -3 tools/flutter/collect_android_baseline.py --serial emulator-5582 --output <new-empty-evidence-directory> --runs 12 --warmups 2 --apk app/build/outputs/apk/debug/app-debug.apk --build-mode debug
py -3 tools/flutter/summarize_save_performance.py --input <pulled-native-json> --logcat <epoch-logcat> --output <new-summary-json>
```

采集时单独运行持续 epoch logcat，按 JSON 内 PID 和时间窗过滤软件输入事件；不清空共享日志。JSON 从应用 external files 导出。采集器原报告的 installedArtifactMatch=unverified 保持原值，独立设备哈希作为补充证据。

## 后续比较边界

本记录是原生测量，不是性能放行。Flutter 候选尚未测量，预算尚待确认。候选采用同内容、60 秒间隔及相近历史规模。FlutterActivity 保持非导出；若通过 instrumentation 冷启动它，必须增加同样入口的原生配对样本，不能与本记录 `am start` 的时间直接相减。精确呈现时序、物理延迟/功耗、发布构建与真机签名仍须独立证据。
