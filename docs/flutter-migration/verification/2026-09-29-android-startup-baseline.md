# Android 原生目录冷启动初测（REQ-003，未完成验收）

日期：2026-09-29（Asia/Shanghai）。本记录是目录负载的原生基线初测，**不构成 REQ-003 完成或 G1 通过**。

审阅更正：以下两批 `fullListFirstCardVisibleMs` 生产标记当时仅检查 RecyclerView 数量，可能把 StartupRowList 的占位行当作完整投影；该字段的原始值保留供追溯，**不能作为完整列表首卡预算依据**。其余独立 marker 不受此来源判断影响。修正投影来源后须另采新批次，不能重写旧记录为已修正数据。

## 结果与范围

任务专用 AVD `emulator-5582`，Android SDK built for x86_64，API 35 / x86_64。安装版本 3.0.2（3000002），debug 构建由构建任务确认且包标记 DEBUGGABLE。源码基础 `08eb682335ce2003f7776c39908507141f5f3656`，采集时 tracked/untracked 工作树 dirty，包含本阶段存档回归修复和启动诊断 marker；不是未修改的历史基线 APK。采集器记录的是当前 checkout revision，不会由此推断安装包的精确源码身份。

每批均 2 次预热 + 12 次 process-cold 启动（逐次 force-stop 后启动 HomeActivity）；预热不进入统计。P95 使用 nearest-rank `ceil(0.95 * N)`，12 次时取最大值。每项缺失值保留 null，样本数不足则独立门槛为 blocked，不补零。

首批 first-visible P95 **398 ms**；显式请求 speed 后第二批 **232 ms**。两批均超过现有 GAME_CENTER_VISIBLE 的 200 ms 独立门槛。其他指标数值预算仍待用户确认，不自动批准超标。

显式执行 `cmd package compile -m speed -f` 返回 Success，但随后的 `dumpsys package` 和 `pm art dump` 都观察到 `[status=verify] [reason=cmdline]`，因此**未验证 speed AOT**。报告的 compileMode=unknown / debugSpeedAotComparable=false 是刻意保守的结论；第二批目录名 run-speed-12 只记录请求的操作，不证明其实际编译模式。不能把第二批与历史 debug+speed 的 170 ms 直接等同比较，也不把两批差异解释成已证明的编译优化收益。

## 测量口径

| 输出字段 | 精确来源和边界 |
| --- | --- |
| firstPaintMs | GAME_CENTER_VISIBLE；首次缓存卡片 pre-draw，不是首交互，也不是完整目录全部卡片绘制完成 |
| startupCacheDecodedMs | CACHE_DECODED；启动 sidecar 解码，不能冒充完整目录投影可用 |
| fullProjectionAvailableMs | CATALOG_PROJECTION_AVAILABLE；完整 lazy 目录投影已可访问，未强制物化全部行 |
| fullListFirstCardVisibleMs | GAME_CENTER_FULL_LIST_VISIBLE；完整列表的首卡 pre-draw，不是所有 2231 卡片都已渲染 |
| nativeReadyMs | NATIVE_READY status=OK；原生初始化完成，不等于首帧或首交互 |
| amStartTotalTimeMs | `am start -W` 的 TotalTime；单列，不混入应用进程起点指标 |
| amStartWallMs | host monotonic 的 adb am start -W 墙钟耗时，含命令往返 |
| settledPssKb | nativeReady 后等待 2 秒再读 dumpsys meminfo；仅延迟后采样，不证明内存已稳态 |

应用 marker elapsedMs 统一源自 `Process.getStartElapsedRealtime()` 与 elapsedRealtime 的差值。采集前取设备 epoch，启动后取当前 app PID；logcat 使用该 PID，解析再同时过滤 PID 和时间边界。没有 logcat clear，不把其他/旧进程事件纳入当前 run。启动至 marker 等待总预算 15 秒。原始启动/marker 日志与逐次 JSON 留在忽略的 `.artifacts`。

## 负载与保留数据边界

使用已授权任务 AVD 上的 `seedDisposable2224GameSnapshot`，真实 instrumentation 结果 `OK (1 test)`。该 fixture 是 2224 个合成目录条目 + 7 个内置条目，总 **2231** 行；所有采样的初始 count、完整投影 count 和 full-list count 均为 2231，cache=HIT。初始 UI 仅绘制最多 4 张卡片，count 不证明 2231 张可见卡片。

未构造代表性的历史/存档/封面大负载，故只能证明目录初测；REQ-003 的完整负载基线仍欠缺。没有测量首交互、进入游戏、保存/恢复、帧时间、物理输入延迟、功耗或热稳定性。AVD 数据不能认证真机刷新率、功耗、温度或延迟。PSS 样本波动明显，2 秒延迟不构成稳定内存预算的依据。

采集器只操作预安装应用：force-stop / start / read-only 查询。没有安装、卸载、清数据、导入、播种、清日志或隐式编译。fixture 播种和第二批前的显式 compile 是本次外部准备步骤，单独授权并留有日志。正常应用启动仍可能更新自身缓存。两批原始结果独立保留，没有覆盖失败批次。

## APK 与证据

本机实际 APK：`app/build/outputs/apk/debug/app-debug.apk`，41220742 bytes，SHA-256 `b89147bee5235bfdc08bc74d43269615f98da976ece029d1e6840eafeebe42dd`。两批使用同一本机文件；采集器不安装它，也未自行证明该文件与设备 base.apk 完全相同，因此 installedArtifactMatch 保持 unverified。

- 首批：[report.json](../../../.artifacts/flutter-g0/baseline/run-12/report.json)、[collector.log](../../../.artifacts/flutter-g0/baseline/collector.log)。
- 显式请求 speed 后批次：[report.json](../../../.artifacts/flutter-g0/baseline/run-speed-12/report.json)、[collector-speed.log](../../../.artifacts/flutter-g0/baseline/collector-speed.log)。
- 准备：[seed.log](../../../.artifacts/flutter-g0/baseline/seed.log)、[compile-speed.log](../../../.artifacts/flutter-g0/baseline/compile-speed.log)、[package-after-speed.log](../../../.artifacts/flutter-g0/baseline/package-after-speed.log)、[art-after-speed.log](../../../.artifacts/flutter-g0/baseline/art-after-speed.log)。
- 工具离线 red/green：[red-parser.log](../../../.artifacts/flutter-g0/baseline-tool/red-parser.log)、[green.log](../../../.artifacts/flutter-g0/baseline-tool/green.log)。parser 初始红灯为 4 个断言失败，例如 `None != 92`；最终 15/15 通过，包含 PID/时间隔离、缺失值、精确 marker、nearest-rank、超时与命令范围检查。

以上原始证据路径在本工作树的忽略目录，未作为发布包或产品签名证明。

## P95 汇总

| 指标 | 首批 | 请求 speed 后批次 | 单位 |
| --- | ---: | ---: | --- |
| firstPaintMs | 398 | 232 | ms |
| shellVisibleMs | 398 | 232 | ms |
| startupCacheDecodedMs | 283 | 100 | ms |
| fullProjectionAvailableMs | 386 | 223 | ms |
| fullListFirstCardVisibleMs | 1065 | 821 | ms |
| nativeReadyMs | 2336 | 2570 | ms |
| amStartTotalTimeMs | 801 | 640 | ms |
| amStartWallMs | 853.487 | 707.261 | ms |
| settledPssKb | 114810 | 109760 | KB |

每项均有 12/12 个测量样本；两批采集状态 collected 只表示证据收集完成，独立 200 ms 门槛均为 fail，G1 acceptance=not_evaluated。

## 首批逐次值

| 样本 | firstPaint | cacheDecoded | projection | fullListFirstCard | nativeReady | am TotalTime | am wall | PSS KB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| warmup-1 | 359 | 211 | 307 | 990 | 2249 | 707 | 753.517 | 113895 |
| warmup-2 | 363 | 241 | 337 | 1034 | 2214 | 729 | 783.733 | 110199 |
| measured-1 | 363 | 240 | 328 | 979 | 2161 | 732 | 785.598 | 112603 |
| measured-2 | 377 | 242 | 311 | 1018 | 2221 | 737 | 797.694 | 109778 |
| measured-3 | 363 | 250 | 331 | 987 | 2170 | 737 | 786.874 | 112418 |
| measured-4 | 386 | 248 | 337 | 1010 | 2121 | 764 | 812.36 | 114810 |
| measured-5 | 360 | 250 | 344 | 1001 | 2219 | 757 | 812.491 | 110672 |
| measured-6 | 365 | 247 | 330 | 989 | 2336 | 744 | 797.138 | 111715 |
| measured-7 | 391 | 283 | 355 | 944 | 1988 | 801 | 853.487 | 108135 |
| measured-8 | 378 | 263 | 347 | 991 | 2170 | 745 | 796.431 | 108619 |
| measured-9 | 349 | 246 | 333 | 1015 | 2077 | 727 | 789.857 | 110798 |
| measured-10 | 354 | 244 | 316 | 931 | 2336 | 721 | 774.367 | 113066 |
| measured-11 | 398 | 253 | 386 | 1065 | 2324 | 782 | 848.594 | 111344 |
| measured-12 | 368 | 235 | 317 | 989 | 2118 | 728 | 778.344 | 107686 |

## 显式请求 speed 后逐次值（实际 verify）

| 样本 | firstPaint | cacheDecoded | projection | fullListFirstCard | nativeReady | am TotalTime | am wall | PSS KB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| warmup-1 | 172 | 72 | 141 | 659 | 2246 | 568 | 623.829 | 66083 |
| warmup-2 | 175 | 79 | 164 | 654 | 2327 | 540 | 601.387 | 109556 |
| measured-1 | 197 | 100 | 177 | 663 | 2357 | 559 | 611.153 | 106805 |
| measured-2 | 208 | 93 | 209 | 684 | 2269 | 580 | 630.174 | 81452 |
| measured-3 | 177 | 91 | 162 | 664 | 2351 | 551 | 605.339 | 109702 |
| measured-4 | 181 | 72 | 147 | 685 | 2404 | 575 | 624.41 | 106963 |
| measured-5 | 232 | 81 | 148 | 821 | 2296 | 637 | 690.275 | 106269 |
| measured-6 | 192 | 74 | 155 | 738 | 2318 | 569 | 626.404 | 66362 |
| measured-7 | 182 | 75 | 151 | 754 | 2306 | 565 | 624.068 | 109760 |
| measured-8 | 202 | 73 | 223 | 754 | 2422 | 638 | 707.261 | 88155 |
| measured-9 | 211 | 85 | 167 | 734 | 2570 | 640 | 699.41 | 66534 |
| measured-10 | 212 | 83 | 170 | 705 | 2367 | 612 | 660.518 | 66240 |
| measured-11 | 190 | 79 | 168 | 694 | 2209 | 558 | 632.653 | 66271 |
| measured-12 | 174 | 73 | 205 | 676 | 2313 | 559 | 605.886 | 81631 |

除 PSS 外上述值均为 ms；warmup 行仅供核查，不进入 P95。

## 复现命令

在本 Flutter 工作树运行；目标必须是明确隔离且允许 fixture 播种的任务 AVD。collector 本身不会替操作者准备/清理数据。

```powershell
$baselineAdb = "$env:LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe"
& $baselineAdb -s emulator-5582 shell am instrument -w -r -e flynes.disposablePerformanceFixture true -e class 'com.flynes.emu.catalog.android.AndroidLargeCatalogPerformanceTest#seedDisposable2224GameSnapshot' com.flynes.emu.test/com.flynes.emu.test.SingleDeviceCertificationRunner
python tools/flutter/collect_android_baseline.py --serial emulator-5582 --output .artifacts/flutter-g0/baseline/run-12 --runs 12 --warmups 2 --apk app/build/outputs/apk/debug/app-debug.apk --build-mode debug
# 独立授权的编译请求；检查实际 dexopt，不把 Success 等同 speed。
& $baselineAdb -s emulator-5582 shell cmd package compile -m speed -f com.flynes.emu
& $baselineAdb -s emulator-5582 shell dumpsys package com.flynes.emu
& $baselineAdb -s emulator-5582 shell pm art dump com.flynes.emu
python tools/flutter/collect_android_baseline.py --serial emulator-5582 --output .artifacts/flutter-g0/baseline/run-speed-12 --runs 12 --warmups 2 --apk app/build/outputs/apk/debug/app-debug.apk --build-mode debug
python -m unittest discover -s tools/flutter/tests -p test_collect_android_baseline.py -v
```

复跑时使用新的空 output 目录，采集器拒绝覆盖现有证据。--runs 默认 12、最少 10；--warmups 默认 2；--apk 可省略，省略后包体测量为 null。未确认的构建模式保持 unknown；不要依据 APK 文件名推断 debug/release 或把未验证的编译模式强行填为 speed。


## 审阅修正后的第三批

`GameCenterSnapshot.fullProjection` 现在区分 startup sidecar 占位行与完整 lazy projection；Home 捕获本次 adapter 提交的投影来源和列表身份，迟到提交不能抢占完整列表 marker。磁盘缓存 schema 未改，未强制解码全部行。真实 Home 新测试先 RED（startup 不应发布 full marker）后 GREEN；相关 instrumentation 5/5，Android unit 574 项、0失败/错误、2跳过，codec 11项通过。证据在 `.artifacts/flutter-g0/android-projection-marker/`。

第三批为该修复后 APK，仍为 debug、API35/x86_64、2预热+12测量、2231行；没有额外 speed 请求。所有 marker 12/12 完整，collector 状态 collected。P95 首卡463ms、完整投影372ms、完整列表首卡1108ms、native就绪2422ms，现有首卡200ms门槛仍失败。修复只校正诊断边界；不同批次的启动变化不应归因于此改动或 Flutter，未控制整机背景负载，且本轮同机在进行其他构建/模拟器工作。

APK 41221021字节，SHA256 `aef365942a45e7048d7adfecec4ffb5beb2b737f0527ccf87ace0815a2a453fd`。采集后只读计算设备 base.apk 哈希，与本机文件相同（`installed-apk-match.json`）；这是外部附加核验，未重写采集器原始报告的 unverified 字段。测试包版本仍3.0.2；后续正常提交的版本递增不等于已重新测过新包。

证据：[report.json](../../../.artifacts/flutter-g0/baseline/run-provenance-12/report.json)、[collector-provenance.log](../../../.artifacts/flutter-g0/baseline/collector-provenance.log)、[包哈希核对](../../../.artifacts/flutter-g0/baseline/installed-apk-match.json)。复现沿前述命令，将output改为新的目录并使用修复后的APK，不覆盖前两批。

| 样本 | firstPaint | projection | fullListFirstCard | nativeReady | PSS KB |
| --- | ---: | ---: | ---: | ---: | ---: |
| warmup-1 | 412 | 349 | 1067 | 2243 | 107934 |
| warmup-2 | 370 | 331 | 1000 | 2181 | 113492 |
| measured-1 | 398 | 330 | 1012 | 2267 | 113051 |
| measured-2 | 350 | 325 | 934 | 2305 | 72605 |
| measured-3 | 395 | 336 | 1017 | 2175 | 115757 |
| measured-4 | 429 | 315 | 1037 | 2268 | 112291 |
| measured-5 | 358 | 314 | 1041 | 2217 | 72511 |
| measured-6 | 385 | 331 | 1029 | 2422 | 112251 |
| measured-7 | 463 | 341 | 1108 | 2342 | 112943 |
| measured-8 | 389 | 343 | 1051 | 2207 | 112227 |
| measured-9 | 418 | 320 | 1011 | 2285 | 113368 |
| measured-10 | 424 | 351 | 1048 | 2221 | 113411 |
| measured-11 | 415 | 372 | 1047 | 2419 | 112985 |
| measured-12 | 372 | 332 | 1020 | 2258 | 113594 |
