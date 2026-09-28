# REQ-001～007：Harmony 原生自动保存性能基线

## 当前状态

2026-09-29 已完成 opt-in 采集夹具、纯计算 RED/GREEN 与 API 20 ArkTS 构建；**尚未开始受控设备测量，无性能通过结论**。等待两模拟器联机、独立覆盖升级和其他编译任务结束后，由总任务统一分配安静窗口。Mac 本轮按用户要求不验证。

测量对象是现有原生 `GameCenter → RunGame`，保持同一产品包身份。Flutter 性能候选在用户确认原生数值预算前不执行，夹具明确拒绝 `g1Entry=flutter`。新增夹具不进入默认 Hypium 套件，不改产品实现。

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

**以下测量命令尚未运行**，仅在总任务确认安静窗口且归还任务 HVD 5557 后执行。不得操作用户的 5555 或独立升级任务的 5559：

```powershell
$perfHdc = 'D:/soft/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe'
& $perfHdc -t 127.0.0.1:5557 install -r .artifacts/flutter-g0/ohos-native-performance/entry-ohosTest-unsigned.hap
& $perfHdc -t 127.0.0.1:5557 shell aa test -b com.flynes.emu -m entry_test `
  -s unittest OpenHarmonyTestRunner -s g1NativePerformance true -s g1Entry native -s timeout 240000
```

JSON 写到运行应用的 `context.filesDir/g1-native-save-performance.json`；根据测试日志返回的真实沙箱路径导出，记录实际命令、完整断言结果、主/测试包哈希和采样前设备状态。测试 shell exit 0 本身不是 Hypium 通过证明。
