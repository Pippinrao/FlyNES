# REQ-001～007：Harmony 原生自动保存性能基线

## 当前状态

2026-09-29 已在最终产品修订 `eaafd7d0 / 3.0.5` 完成 **2 次预热 + 12 次正式原生启动（全部通过）**，以及原生自动保存采集 **1/1 通过，69.123 s**。使用下文 C2B45… 主包与 9874… 最终测试包；pilot 不计入正式结果。Android 采集、其他构建与设备测试结束后才执行，未并行运行其他测试。采集有效性通过不等于性能预算通过，尤其原生音频欠载不能省略。Flutter/内存往返候选尚未测量，仍等待预算批准。Mac 本轮按用户要求不验证。3.0.4 首轮历史数据在下方保留。

测量对象是现有原生 `GameCenter → RunGame`，保持同一产品包身份。Flutter 性能候选在用户确认原生数值预算前不执行；后续准备的候选入口同时要求 `g1Entry=flutter` 与 `g1CandidateApproved=true`，默认拒绝。新增夹具不进入默认 Hypium 套件，不改产品实现。

## 受控原生结果（3.0.4）

设备为任务 HVD `127.0.0.1:5557`，API 20、debug 模式。测量墙钟 65.275 s，实际源帧累计 **65.031 s / 3252 帧**，PAL 50.00698 FPS。显示计数增加 3248，presentFailures 增量 0。共 3001 次计数观察、67 次内存/head 读取、13 次真实 A 键输入。分位数为 nearest-rank；这些是单次仪器化模拟器结果，不是设备性能认证。

| 指标 | 中位数 | P95 | 最大值 |
| --- | ---: | ---: | ---: |
| PSS（KB） | 137467 | 152193 | 154541 |
| Ark VM 已用堆（KB） | 10581 | 17000 | 18047 |
| 计数轮询间隔（ms） | 21 | 23 | 175 |
| 源帧计数增长观察间隔（ms） | 21 | 23 | 195 |
| 显示计数增长观察间隔（ms） | 21 | 43 | 195 |
| PCM 消费计数增长观察间隔（ms） | 105 | 111 | 387 |
| A 注入请求到首次观察 appliedButtons（ms） | 22 | 26 | 26 |
| 内存/head 读取自身耗时（ms） | 27 | 34 | 40 |

PSS 最小 113212 KB。采样数组和 JSON 序列化也使用应用内存，因此此峰值包含夹具成本；不能将其直接当作无采集版本的驻留内存。`getNativeHeapAllocatedSize` 本轮所有值为 0，没有报错，**不能据此声称原生堆为零**；原始 API 值保留，预算不采用此项。

真实自动记录新增 ID 246（kind=0），head 从 245 变为 246。最后一次旧 head 观察开始于 58.016 s，首次新 head 观察结束于 59.021 s；测量开始前等待 UI 已运行约两秒，因此相对测量起点不足 60 s 不代表将产品自动保存周期缩短。其前后各扩 2 s 的上下文窗口为 56.016–61.021 s：源帧和显示计数增长观察间隔最大均为 68 ms，PCM 消费计数增长间隔最大 387 ms。**这是保存附近的观察值，不是精确保存耗时或每帧停顿因果证明。**

音频 PCM 生产增加 2,650,585 samples、消费增加 2,647,688 samples，回调增加 3187；**underflows 与 shortReads 各增加 569**，postFallbackUnderflows 增加 569，lockMisses 增加 2，droppedSamples 增加 1643。状态为 normal-latency fallback（fast audio path unavailable）。这轮基线已有明显软件音频欠载，不能设置或宣称“零欠载已通过”；需作为原生基线缺陷/环境限制单列，候选比较也不能忽略。

13 次输入均观察到按下和释放；上表 26 ms 是含 UiTest 调用和 10 ms 轮询的软件上界，不是物理输入到声音/像素时间。各次注入调用返回时间为 103–109 ms。

## 本轮固定产物与证据

目录 `.artifacts/flutter-g0/performance-c0511d69/`：

| 文件 | SHA-256 / 结果 |
| --- | --- |
| `entry-default-unsigned.hap` | `2766CFA6746ACEBC647D8FCF70FC8C4ADAEF4F81415856A591A8494091A0406D` |
| `entry-ohosTest-unsigned.hap` | `DB2CB3E1D4D35A724EFC3BA699B91440A00E09AFF05BD3757D7A7864CCDEEF5E` |
| `g1-native-save-performance.json` | `E6C0700E9E8DA8C617E04C71D2D50A148CBFCBE3DF95A7001E91ED8EA35C37EF`；原始 5,195,847 bytes |
| `native-hypium.log` | Tests run 1 / Pass 1 / Failure 0 / Error 0，69.166 s |
| `native-summary.json` / `summarize-ohos.py` | 可复算上述 nearest-rank 汇总，保留原始计数与 head 边界 |
| `main-build.log` / `test-build.log` | 增量 hvigor exit 0，30.167 s / 7.709 s |
| `install.log` / `install-test-retry.log` | 首同批 hdc 倒序先装测试而遇旧主版本不兼容；主安装成功后测试单独 install-r 成功 |
| `bundle-installed.json` / `preparation.json` | 安装后 versionCode 3000004 / versionName 3.0.4，含 entry_test |

公开可审阅汇总工具为 `tools/flutter/summarize_ohos_performance.py`，小型 fixture 测试 `tools/flutter/tests/test_summarize_ohos_performance.py` RED 4 项失败 → GREEN 5/5。失败或不完整报告 CLI exit 2，allocator 全零标 unavailable，布尔值不充当数字，`--output` 使用独占创建拒绝覆盖。`native-summary-final.json` 用公开工具复算，替代仅存在于忽略目录的初版脚本作为正式复现入口：

```powershell
python tools/flutter/summarize_ohos_performance.py `
  .artifacts/flutter-g0/performance-c0511d69/g1-native-save-performance.json `
  --output .artifacts/flutter-g0/performance-c0511d69/new-summary.json
```

真实执行的测试参数为 `-s g1NativePerformance true -s g1Entry native -s timeout 240000`。JSON 从 `/data/app/el2/100/base/com.flynes.emu/haps/entry/files/g1-native-save-performance.json` 使用 `hdc file recv` 导出；没有卸载/清数据。无签名包仅在任务模拟器上覆盖安装，不能替代签名真机验收。

## 采集范围与限制

- 将现有设置临时设为音频开启、自动保存开启，`save_history.intervalMs=60000`；退出恢复原设置和原偏好值（含原本不存在的 key）。真实新增的 AUTO 历史记录保留，不清除数据。
- 从单一许可游戏清单读取默认首项，可用 `g1CanonicalId` 指定清单内游戏。通过现有 `PlayService.readRom` 与 `historyContentKey` 获取真实内容身份，记录前后 history head 和完整行元数据。
- 使用 `systemDateTime.getUptime(STARTUP)` 单调时钟。源帧差除以实际 source FPS 累积有效模拟进度；必须达到至少 65,000 ms，最长墙钟 150,000 ms。不能以等待 65 秒冒充模拟运行 65 秒。
- 请求每 20 ms 读取 runtime/render counters，含源帧、上传/显示帧、显示失败、GPU timing（由对应 valid 字段约束）、PCM 生产/消费、回调、欠载、short read、队列等原始值。保留每次调用的开始/结束时刻。
- 请求每秒读取 PSS/VSS（KB）、native allocated（bytes）、Ark VM heap（KB）以及真实 head；内存 API 不可用时记录 error 与 -1，不能解释为 0。内存与 DB 查询自身耗时单独记录。
- 每 5 秒通过原生游戏触摸布局计算真实 A 键位置并注入 UiTest 点击；10 ms 稀疏 `playStep` 观察 appliedButtons 与释放。此期间会复制 frame/PCM，属于采集开销。记录注入开始、首次观察到输入、注入返回和释放观察时刻；这是含 UiTest 和轮询延迟的软件上界，不是物理触摸延迟。
- 自动保存必须产生新的 kind=0 记录、head 必须变化、真实 PCM 消费和画面显示计数必须前进；上述是采集有效性断言，不是预设性能预算。
- 所有采样完成后写 JSON，避免测量过程中持续文件输出。即使断言失败也在 finally 导出部分记录并恢复设置。

**不能由这些数据得到**精确每帧呈现时间、精确存档开始/结束、物理刷新率、触摸到显示、功耗或温度。可报告轮询间隔、计数增长间隙以及 head 变化前后观测窗口；必须同时考虑采样、输入和内存查询开销，不能将所有长间隔归因于保存。保存提交时刻最多由相邻 head 采样约束。

## 已执行验证

工作树 `codex/flutter-foundation`，沿用固定 Flutter-OH 3.41.10-ohos-1.0.0 与 DevEco 6/API 20。生产主包保持先前通过 9 项 Foundation + 4 项 Texture 的冻结副本。

1. `node --test harmony/tests/g1_performance_observations_test.cjs`：先缺少 helper，2 项失败；实现后 2/2 通过。覆盖默认禁用、仅 exact opt-in、拒绝未批准 Flutter 候选、真实帧进度、暂停/计数重置不膨胀、无效 FPS。
2. API 20 `ohosTest assembleHap` exit 0，8.099 s；包含同期稳定的 SaveHistoryUpgrade 夹具。厂商 SDK 原有 warnings 与未配置签名提示保留，没有将无签名包称为签名设备验证。
3. 新增/修改本 slice 文件 `git diff --check` exit 0。

忽略证据目录：`.artifacts/flutter-g0/ohos-native-performance/`。

| 文件 | 作用 |
| --- | --- |
| `helper-red.log` | 2 个真实失败 |
| `helper-green.log` | 2/2 通过 |
| `test-build.log` | API 20 测试包编译通过 |
| `entry-ohosTest-unsigned.hap` | 冻结测试包，SHA-256 `BCD45AA43E67DE5F897E46907F8EA1C4520558EC4857F57219F205C2B15BD6F4` |

冻结生产主包 `.artifacts/flutter-ohos-probe/final-packages/entry-default-unsigned.hap`，SHA-256 `FC1694F3C48CE0E0D2F5E84BCD1D3425FE7D568DEC70B881625D1F6EA8470FD2`。不要覆盖这些证据文件。

## 可复现命令

从仓库根目录执行 helper：

```powershell
& 'D:/soft/DevEco Studio/tools/node/node.exe' --test harmony/tests/g1_performance_observations_test.cjs
```

在 `harmony/` 中执行增量测试包构建（需已有匹配 debug HAR stage）：

```powershell
$env:DEVECO_SDK_HOME = 'D:/soft/DevEco Studio/sdk'
& 'D:/soft/DevEco Studio/tools/node/node.exe' 'D:/soft/DevEco Studio/tools/hvigor/bin/hvigorw.js' `
  --mode module -p product=default -p module=entry@ohosTest -p buildMode=debug assembleHap --no-daemon
```

以下为准备阶段的命令模板；本轮实际执行使用上方 `performance-c0511d69` 的同版本包。重跑仍需总任务确认安静窗口且归还任务 HVD 5557。不得操作用户的 5555 或独立升级任务的 5559：

```powershell
$perfHdc = 'D:/soft/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe'
& $perfHdc -t 127.0.0.1:5557 install -r .artifacts/flutter-g0/ohos-native-performance/entry-ohosTest-unsigned.hap
& $perfHdc -t 127.0.0.1:5557 shell aa test -b com.flynes.emu -m entry_test `
  -s unittest OpenHarmonyTestRunner -s g1NativePerformance true -s g1Entry native -s timeout 240000
```

JSON 写到运行应用的 `context.filesDir/g1-native-save-performance.json`；根据测试日志返回的真实沙箱路径导出，记录实际命令、完整断言结果、主/测试包哈希和采样前设备状态。测试 shell exit 0 本身不是 Hypium 通过证明。

## 后续测试入口准备（尚未执行）

`G1StartupObservation.test.ets` / `Collect-OhosStartup.ps1` 已编译。每次外部 force-stop 后确认无残留 PID，再独立 `aa test`；默认 2 次预热、12 次正式样本。计时明确从 `delegator.startAbility` 请求到 UiTest 可见且 enabled/clickable 主按钮、可见首卡，不包含请求前测试 runner 初始化，不伪造物理首帧时刻。记录 PID、debug/mode、原生底层和现有服务投影目录数。

原生和 Flutter 均为新页面 ALL / 空查询；生产模块 `entry` 的 multiplayerOnly 偏好临时 false。**pilot 实测纠正了模块 context 的假设**：静态 `application.createModuleContext` 拒绝 Hypium wrapper；实例 Context 方法虽可调用，其目录仍为应用级 base，并非页面使用的 `base/haps/entry`。两个失败均保留，路径不匹配断言没有被跳过。最终使用 test-only `AbilityMonitor.onAbilityCreate` 取得本次冷启动的真实 Ability context，同步规范偏好，并记录规范时间先于 `onWindowStageCreate`。这段测试成本包含在请求→UI 上界内。finally 恢复真实偏好原值/原缺失状态并断言，JSON 保留所有实际目录。没有为了获取 context 提前启动一次 UI。启动 runner 拒绝覆盖输出目录，保留 warmup 与正式样本，不会把错误/缺 JSON 当成功。

当前测试包 `.artifacts/flutter-g0/performance-c0511d69/startup-entry-ohosTest-unsigned.hap`，SHA-256 `10969BC4063F5562A394426C79DED3A7FF451A35052EDACCDE4822C11D86B06C`，增量编译 exit 0 / 6.402 s。生产包未更改。原生样本待总任务分配安静窗口；Flutter 不得因夹具可用就提前运行。

自动保存候选也仅准备：通过已有 debug Want 打开真实 Flutter 目录，点击同 canonicalId 卡片，再点击共享页主按钮，经既有桥进入原生 RunGame。不会以直接打开 RunGame 冒充候选路径。候选仍需明确批准 flag，并检查 contentKey、sourceFPS、采样间隔与近似记录数后才能与原生比较。

## 3.0.5 同修订产物与启动 pilot

提交 `eaafd7d0 / 3.0.5` 的 OH 产品源码与上一轮一致，仅版本元数据同步。已重新增量构建主包（7.008 s）和测试包（最初 6.588 s；夹具最终 6.409 s），均 exit 0，分别 install-r；`bundle-installed.json` 确认 3000005 / 3.0.5。证据目录 `.artifacts/flutter-g0/performance-eaafd7d0/`：

| 文件 | SHA-256 |
| --- | --- |
| `entry-default-unsigned.hap` | `C2B45DF0A36E71D2FAD8A7222DA91E03EC5BD2A8E193B1E22006757E9A2C73F6` |
| `entry-ohosTest-unsigned.hap`（初版夹具） | `B042D71C459A5EDDFB1A7CB4FD684E172F10D3F414CDFAA8C33F5C1001305FC1` |
| `final-entry-ohosTest-unsigned.hap`（最终 pilot 与已注册 memory opt-in） | `9874AEFC48C796759748F6D4C570FAEC08912D18DE7D1E71F567ADB275B26DA5` |

原生单次 pilot 从真实 RED 到 GREEN，**仅检查夹具可用，不计入性能预算**：

1. `startup-native-pilot`：静态 context API 拒绝 wrapper，未启动页面；失败。
2. `startup-native-pilot-fix` / `startup-native-pilot-diagnostic2`：API 20 UiTest `findComponents` 在树未就绪时返回 null（SDK 类型声明为 Array），for-of 抛错；精确堆栈保留。增加空结果等待，不改变 UI 断言。
3. `startup-native-pilot-null`：真实主按钮和首卡可见，但模块/真实 Ability 偏好路径不一致，被断言拒绝。
4. `startup-native-pilot-monitor`：**1/1 PASS**，真实规范时间 3788934 ms < windowStageCreate 3788948 ms，`preferencesRestored=true`。真实 nativeSnapshotCount=0、现有产品服务投影目录=7，后续同端 native/Flutter 应保持相同目录口径。请求→主按钮 2791 ms / 首卡 2803 ms 是该非受控 pilot 的软件观察上界，仅原样留档，不用于定预算。

现有构建已包含 `memoryRoundTripsOnly=true` 专用测试分支，内部仍要求候选批准 flag；未运行 memory/Flutter 候选。编译阶段发现 renderer API 没有 paused 字段，修正为返回后 presentedFrames 跨 100 ms 无增长的真实观察，配合 coreClosed 断言；不冒充不存在的暂停状态。

## 3.0.5 正式受控原生结果（当前比较基线）

总任务明确交接安静窗口后，首先调用 `Collect-OhosStartup.ps1 -Route native -Warmups 2 -Samples 12`，输出新目录 `performance-eaafd7d0/startup-native-controlled`。全部 14 个不同 PID 的 JSON 均 complete、无 failure，真实偏好规范时刻都早于 WindowStage 创建，且 finally 恢复成功。原生底层目录快照均为 0 条，现有产品服务补入许可游戏后的投影均为 7 条；这与 Android 的大目录不同，不能跨平台强行比较原始耗时。后续 OH 候选必须保持相同 7 条投影。

正式 12 个样本（排除 2 次预热和所有 pilot）：

| 指标 | 最小 | 中位数 | P95 / 最大 |
| --- | ---: | ---: | ---: |
| 请求→可见且可点击主按钮（ms） | 1547 | 1563 | 1598 |
| 请求→可见首卡（ms） | 1559 | 1574 | 1616 |
| 目录就绪 PSS（KB） | 103743 | 103832 | 104359 |

每个样本均为 debug=true / buildMode=debug。时间包含 Ability 创建期测试侧偏好规范、UiTest 和轮询开销，排除 startAbility 请求前的测试 runner 初始化；不是进程首条指令→物理首帧。分位数 nearest-rank，偶数样本中位数取下中位。

随后停止任务 app，并用同冻结包运行原生保存采集。Hypium **1/1 PASS / 69.123 s**；有效测量 wall **65.265 s**、源帧累计 **65.231 s / 3262 帧**，显示增加 3260、失败 0。采样 3010 次、内存/head 67 次、输入 13 次。contentKey 与 3.0.4 相同，PAL 50.0069789 FPS，60 秒保存周期、20 ms 计数/1000 ms 内存采样不变；开始前历史记录 90 条，head **247→248**，新增 kind=0 AUTO 记录 248。

| 保存采集指标 | 中位数 | P95 | 最大 |
| --- | ---: | ---: | ---: |
| PSS（KB） | 139523 | 153646 | 155858 |
| Ark VM 已用堆（KB） | 10548 | 16912 | 17972 |
| 轮询间隔（ms） | 21 | 23 | 65 |
| 源帧计数增长观察间隔（ms） | 21 | 23 | 66 |
| 显示计数增长观察间隔（ms） | 21 | 43 | 83 |
| PCM 消费增长观察间隔（ms） | 105 | 110 | 371 |
| 输入注入→观察 appliedButtons（ms） | 23 | 34 | 34 |
| 内存/head 查询成本（ms） | 29 | 40 | 43 |

head 提交时刻由 **58.013–59.051 s** 的相邻观察约束；向前后各扩 2 s 的上下文为 **56.013–61.051 s**，源增长间隔最大 61 ms、显示最大 66 ms、PCM 消费最大 371 ms。仍只能称观察窗口，不能算成精确保存耗时。

**音频原生限制继续存在**：underflows、postFallbackUnderflows、shortReads 各增加 **591**；lockMisses 0、droppedSamples 823、生产 2,659,558 samples、消费 2,657,835 samples、回调 3214，无计数重置。所有输入观察到按下和释放。nativeAllocated 仍全零，公开汇总工具明确输出 unavailable，不能作为 0 字节内存使用。

本轮证据均在 `.artifacts/flutter-g0/performance-eaafd7d0/`：

- `startup-native-controlled/`：每个样本的 force-stop、Hypium、原始 JSON、SHA-256，`samples.json` 与 `summary.json`；runner 日志 `startup-native-controlled-runner.log`。
- `native-hypium.log`：完整 1/1 断言；`g1-native-save-performance.json` 原始 5,211,296 bytes，SHA-256 **`4ABEC11D3965AF700DFD90DF4B7A2BC3F2CEF8CE4BF1383432D4C6F53A5D609D`**。
- `native-summary.json` / `summary-cli.log`：公开汇总工具复算，CLI exit 0、captureComplete=true。
- `native-save-stop.log` / `controlled-finish-stop.log`：采集前后仅停止任务 app，没有卸载、清数据或停止用户 HVD。

完成后已停止任务应用并归还设备/构建窗口。未运行 Flutter 启动、Flutter 保存、memory 往返或 Release 候选。
