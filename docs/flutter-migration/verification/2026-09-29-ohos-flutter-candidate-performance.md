# HarmonyOS Flutter 候选：模拟器实测

启动及65秒原生游戏候选采集完成；**Debug PSS超过预先冻结的预算**。后续20次往返及真实Dart5/20握手已完成，公开hidumper补采的Ark堆增长满足16MiB门槛；rawheap转储仍不可得。同包Release PSS补充诊断完成，增量46374 KiB≤128MiB；它不覆盖Debug失败，不代表G1整体放行。

## 对照身份与证据

- 生产源码 `eaafd7d0a38d3a60ffe7d2db8aad8f04857d6370`，3.0.5 / 3000005。
- 下述Debug启动、65秒及往返批次的实际主包始终是原生基线同字节 `C2B45DF0A36E71D2FAD8A7222DA91E03EC5BD2A8E193B1E22006757E9A2C73F6`。这些批次没有换成后来重建的主包；末节Release补测有独立包身份。
- 固定 Flutter-OH 3.41.10-ohos-1.0.0 / Dart 3.11.5 / API20 / task HVD `127.0.0.1:5557`；先行批次为Debug，末节为Release，均不代表物理设备。
- 证据根：`.artifacts/flutter-g0/candidate-eaafd7d0/`。`budget-before.md` 是运行前预算快照；`frozen-input-hashes.json` 固定初始主包、测试包与预算。
- 启动最初测试包 B71B3C5F…；保存清理修复测试包 `7341E9F522AA994322FE0539868DF4B0093FB386F6B5203EC1A6173B5069DDEC`；内存初始化修复测试包 `729A5A15EBF0246CC6731E161C57C9753AC81678D6BA0C5D589C49447DB4E013`。变动仅在测试夹具。

## 已完成的同口径比较

启动分别 force-stop，无旧PID，2预热 + 12正式；全部14个单样本断言通过。计时是 delegator 请求到 UiTest 观察 enabled 主按钮/首卡的软件上界，不是首帧时间。两路均 ALL、空搜索、实际投影7项、底层导入目录0项；偏好按夹具 finally 恢复。

| 指标 | 同包原生 | Flutter候选 | 冻结门槛 | 结果 |
|---|---:|---:|---:|---|
| 主按钮可交互 P95 | 1598 ms | 2146 ms | ≤3098 ms 且 ≤4000 ms | 通过 |
| 首张可见卡 P95 | 1616 ms | 2159 ms | 观测项 | 保留 |
| PSS P95 | 153646 KiB | 350956 KiB | ≤284718 KiB | **失败** |
| 源帧计数增长间隔 P95 | 23 ms | 23 ms | ≤27.3 ms | 通过 |
| present计数增长间隔 P95 | 43 ms | 43 ms | ≤49.3 ms | 通过 |
| 保存上下文源帧/present最大间隔 | 61/66 ms | 57/57 ms | ≤81/86 ms | 通过 |
| 软件输入到首次appliedButtons上界 P95 | 34 ms | 35 ms | ≤54 ms | 通过 |

候选保存 GREEN Hypium 1/1，70.550秒；实际模拟 `65030.92310316323 ms`、墙钟65390ms，2989计数样本、67内存样本、13输入样本。两路同 manifest canonical、contentKey `6F80D56CE0B242A4FACEAFAFEA321FEB1C364AB8E7937646E8580AE9289A4EC3`、PAL 50.0069789081886 FPS、60秒自动保存、20ms计数和1000ms内存采样、起始90条记录。候选真实 AUTO head250→251；源帧增长3252、present增长3238、presentFailures增量0。

候选PSS median342803/max353332 KiB。全程源帧/present最大增长间隔均350ms，不能用P95通过掩盖该值。音频 produced2649073、consumed2645802、callback3211；underflows591按原生时长归一为`591 * 65230.895 / 65030.92310316323 ≈ 592.818`，≤650.1门槛，通过。native allocator返回0，公开汇总工具将其标为 unavailable，不能解释为零本地占用。

原始 `save-complete.json` 由公开 `tools/flutter/summarize_ohos_performance.py` 重算 `save-summary.json`；完整报告中 captureComplete=true、reportedFailure为空，并有真实AUTO与足够模拟进度。模拟器计数增长间隔包括观察线程调度成本，不认证物理刷新率、触屏延迟、音频听感、功耗或温度。

后续汇总器审阅发现“全部PSS读取失败仍complete”的独立P2并RED→GREEN修复；最终重算
`save-complete-reviewed-summary.json`与`release-paired/{native,flutter}-reviewed-summary.json`，
三份均67个有效PSS、0读取错误，P95 350956/135379/181753不变。原汇总保留，新判断使用
校验全部PSS正有限、非bool且无memory.error的公开工具，不依赖CLI exit0单独断言。

## 保留的测试夹具 RED

1. `save-hypium.log` / `save-first-failed.json`：首轮真实65秒已执行，但 cleanup 缓存了 debug Want 替换 WindowStage 前的 router，finally 导航 URI失败。原JSON的 complete=true 不可靠，Hypium失败优先；该样本不作为成功比较。最小修正重取当前 top Ability/window router，cleanup失败必须先写 failure/complete=false，再持久化JSON。修复后独立重跑成功，未重复已通过启动批次。
2. `memory/hypium.log`：startAbility完成不代表 top Ability可用，round0失败。改为等待真实Flutter host再取UIAbilityContext。
3. `memory/retry-hypium.log`：host出现不代表异步目录owner已打开，settingsGet报app未打开，仍是round0。改为等待并选择真实manifest卡片后再读取设置。
4. `memory/ready-hypium.log`：第三次真实完成5个往返后进入180秒Dart检查点。Dart CLI已取得PID7501真实main isolate数据，但公开hdc沙箱写入失败，ACK未交付，窗口超时。finally的JSON.stringify又遇到GC统计中的BigInt错误，完整report未落盘；完整Hypium错误及独立Dart JSON仍保留。不得以CLI退出码0或Dart complete=true代替整个往返夹具成功。

第5轮独立Dart证据 `memory/dart-round5.json`：heapUsage102931120→76758528 bytes、capacity125837312不变、external38256→3712。确实请求了公开 `getAllocationProfile(gc:true)`；首次dateLastServiceGC为null，保守记录gcObserved=false（timestamp-unavailable），不更改判定制造通过。没有第20轮配对值。

## ACK传输修正边界

公开 [hdc文件传输说明](https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/dfx/hdc.md) 支持 `-b` 调试应用；实测 `shell -b com.flynes.emu` 能 stat `data/storage/el2/base/haps/entry/files`，但 `file send -b` 对该目录写独立探针仍返回permission denied。没有使用root daemon、私有SDK或VM evaluate写文件。

修正仅测试夹具接收有界loopback TCP ACK：127.0.0.1动态端口，原180秒期限，最多4连接/单行16KiB，同runToken/round/PID及真实CLI evidence哈希校验，finally关闭全部连接与监听。主包、SDK与产品入口不变。GC原始统计保留十进制字符串，count单独安全转换，0n是有效计数。11项Node helper测试通过；SDK端口可空的编译RED及显式检查后的GREEN均保留。测试包SHA`B3CA86A922D240C5BFCBB398D3BC4AFF2D33AA113FEAF70E958724ADE3CC09C8`。

## 20次往返与独立公共GC补采

`memory-loopback/`：Hypium1/1、133.777秒，20次真实往返完成，两次Dart ACK都成功、0拒绝/0传输错误。Dart同PID23942/同isolate；采样后heap76771744→77756464 bytes。Ark两次rawheap请求均报`Disk remaining space too low`，没有GC计数增加；故本批`memoryCaptureComplete=false`，没有把功能PASS当内存PASS。

检查`/data`剩余4.1GiB，未发现可证明本任务生成的rawheap，因此没有删除任何应用数据或文件。使用API20已公开支持的`hidumper --mem-jsheap <pid> -T <tid> --gc`补采；具体依据见[内存协议](2026-09-29-ohos-memory-protocol.md)。

`memory-public-gc/`：同测试包、同主包再执行必要20次，Hypium1/1、126.444秒，PID/TID都为23988（本轮日志、主线程断言、最终report交叉核对）。第5/20轮ready期间只对该线程发公共GC命令，再顺序执行真实Dart CLI和ACK。

| 同一停留节点 | 第5轮 | 第20轮 | 差值/判定 |
|---|---:|---:|---|
| Ark GC count（请求前→外部采集后） | 3→5 | 5→7 | 两次均实际增加 |
| Ark heapUsed | 9427 KiB | 9304 KiB | -123 KiB，≤16 MiB门槛 |
| 进程PSS | 310833 KiB | 309506 KiB | -1327 KiB，独立观测 |
| Dart请求后heapUsage | 76869456 B | 77846192 B | +976736 B，独立观测 |
| Dart heapCapacity | 109060096 B | 100671488 B | -8388608 B |
| Dart externalUsage | 3712 B | 3712 B | 0 B |
| Dart gcObserved | false | true | 首次timestamp缺失仍保守false |

两种VM是顺序采集，PSS不可与堆相加，不认证无泄漏。原始rawheap仍失败，报告中仅描述raw请求窗口的`arkGcObservedAtBothCheckpoints=false`及`memoryCaptureComplete=false`完整保留；Ark门槛依据是独立公共命令窗口及`afterDart`真实计数/字节，不能冒称原API快照成功。每批结束均关闭task app和仅本批创建的VM/ACK forward。

## 同包Release PSS补充诊断

同生产源码/固定SDK另建Release HAR+主包，并以公开hvigor `buildMode=release`构建测试包；两路采集期间主/测试均不变化。主SHA`32C907FC28AC61D75FD11B4045D290D717BFC1C24D3984422A5BE99D4D81D9B5`、测试SHA`4DCEBAF5D483B960BAF92B12FF293562403B66A28191378CB0B168E8E882BE12`。测试包全部四份`.so`仅为两ABI的libapp/libflutter，与主包逐字节一致；没有测试版libentry替换生产库。实际目标debug=false。测试HAP自身debug=true/buildMode=debug的工具生成元数据照录，它是对Release生产目标的测试模块，并未改主包debug标志绕过策略。

证据`release-paired/`含包、metadata、库哈希、install、每路Hypium、原始JSON及公共summary。显式`g1BuildMode=release`要求真实EntryAbility.applicationInfo.debug=false；Flutter从测试侧真实UI router进入既有共享目录，点击同许可游戏的主按钮，生产debug Want gate不改。原生Hypium1/1、69.512秒，Flutter1/1、68.812秒；实际模拟65030.923/65210.898ms，两路complete=true、failure为空、实际debug=false。

两路同contentKey/PAL FPS/60秒auto/20ms计数/1000ms内存、开始均90条历史、67个有效PSS样本；真实AUTO原生head297→298、Flutter299→300。

| PSS | Release原生 | Release Flutter |
|---|---:|---:|
| median | 120289 KiB | 170216 KiB |
| P95 | 135379 KiB | 181753 KiB |
| max | 135418 KiB | 184385 KiB |

P95增量**46374 KiB**≤运行前固定的**131072 KiB（128MiB）**，补充PSS诊断通过。`mode-budget-before.txt`在两路前冻结公式，`candidate-limits-before.json`在native后、Flutter前冻结同模式PSS上界266451 KiB。该文件还保留沿原公式算出的媒体观测数字，但它们不是新增G1放行预算，不用于改写原Debug结果。

媒体数据仅另列观察：source/present增长P95为原生22/43、Flutter23/43ms；全程最大间隔原生677/493、Flutter82/82ms；保存窗口最大原生74/74、Flutter82/82ms；输入P95原生33、Flutter32ms；underflows581/556（时长不同）。这些含调度和仪器成本，不能外推真机延迟或用Release补充观察消除原生200ms门槛失败。

结束5557保留上述Release主/测试3.0.5；app已force-stop、pidof为空、fport为空，无常驻采集器。所有Debug冻结包及失败证据保留。当前HAR staging是release，后续debug测试应显式恢复模式；没有静默用新生成包替换已测Debug基线。
