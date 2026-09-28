# OH API20 20 次往返内存诊断方案

状态：独立 opt-in harness 已真实执行20次往返和Dart 5/20握手。内存纯逻辑Node **7/7**，
与性能helper合计11/11。最新测试包B3CA86A9…编译通过；`memory-loopback`及
`memory-public-gc`两批Hypium均1/1通过。后者公开hidumper补采观察到同主线程GC计数
增长，Ark堆5→20由9427降至9304 KiB；rawheap空间错误仍保留，不假称完整快照可得。
完整失败历史及数字见[候选记录](2026-09-29-ohos-flutter-candidate-performance.md)。
实际执行遵循用户“模拟器可测全部完成”的继续授权、已固定预算及主任务分配的独占窗口。
本方案不修改 SDK，也不把已有 20 次 `coreClosed` 功能通过等同于内存验收。

## 公开接口与本机依据

本机 API20 声明：

`D:/soft/DevEco Studio/sdk/default/openharmony/ets/api/@ohos.hidebug.d.ts`

- 425 行：`getAppNativeMemInfoAsync(): Promise<NativeMemInfo>`，API20。
  `pss`、`rss`、`privateDirty` 的单位为 KB；PSS 包含 SwapPss。
- 445–478 行：`getAppVMMemoryInfo(): VMMemoryInfo`，API12；`heapUsed`、
  `totalHeap`、`allArraySize` 是**当前 Ark VM** 的 KB 值，不包含 Dart 堆。
- 767–794 行：`getVMRuntimeStats(): GcStats`、`getVMRuntimeStat(item: string): number`。
  `ark.gc.gc-count` 等统计对应当前线程；快照记录 PID/TID，要求调用在主线程。
- 848–871 行：`dumpJsRawHeapData(needGC?: boolean): Promise<string>`，API18，
  `true` 请求快照前 GC。返回 `.rawheap` 沙箱路径；配额、fork、超时、重复转储等
  错误必须保存。此公共声明不提供独立、保证全进程回收的 `forceGC()`。

官方[HiDebug 文档](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-performance-analysis-kit/js-apis-hidebug.md)
还注明该转储入口需要 Developer options；API20 只使用单参数重载，不调用新版本
API24 的 `needClean` 重载。SDK 提供的转换器是
`D:/soft/DevEco Studio/sdk/default/openharmony/toolchains/rawheap_translator.exe`。

`@kit.PerformanceAnalysisKit` 公开导出 `hidebug` 和 `jsLeakWatcher`。
后者的 `enable/watch/check/dump` 声明位于
`ets/api/@ohos.hiviewdfx.jsLeakWatcher.d.ts`，可后续定位特定 Ark 对象的保留链，
但其“疑似泄漏”列表不代替字节指标。本 harness 未接入对象 watcher。

不要用 `OH_JSVM_MemoryPressureNotification(JSVM_Env, ...)` 冒充 Ark 主 VM 或
Flutter 的 GC：该 API 要求调用方持有自己的 JSVM 环境，并且也只是可选触发。

## Harness 边界

新增 `harmony/entry/src/ohosTest/ets/test/G1MemoryRoundTrips.test.ets`，默认导出
`g1MemoryRoundTripsTest()`。它只在两个参数同时成立时注册：

```text
-s memoryRoundTripsOnly true -s g1CandidateApproved true
```

`List.test.ets` 分流由集成任务注册；本次没有编辑已有 Foundation 或 List 测试。
`g1CandidateApproved`是显式运行保护，不意味着预算已通过。当前用户继续验证授权已覆盖
候选执行，不再额外创建用户预算确认停工点；仍必须保留冻结预算及独占窗口。

同一进程、同一 Flutter 页、manifest 同一许可 ROM，完成 20 次共享目录按钮启动
原生游戏 → 验证核心帧增长 → 真实暂停 → 原生菜单回目录。每轮断言暂停和音频停止，
返回后断言核心 owner 关闭，并记录 renderer 的两次 `presentedFrames` 原值，在 100 ms
内没有继续增长。现有 `RenderStatusDto` 没有 paused 字段，因此这是“停止呈现观察”，
不是读取 renderer paused 状态。设置不修改，实际设置 JSON 随报告保存。
真实返回路径可能保存该许可 ROM 的进度；不清数据或重置存档。

首轮前和每轮返回固定等待 500 ms 后采样 PSS/RSS/privateDirty、Ark heapUsed/capacity、
GC 计数和 allocator 原值。第 5、20 次分别记录 `dumpJsRawHeapData(true)` 前后完整
采样及请求起止、文件路径、文件大小、错误；GC 判断仅来自有效的当前线程计数增长。
第五次为预热后的比较点，第二十次为终点，两者差值必须注明是 5→20 的观察窗口。

报告写入实际 EntryAbility 的 `filesDir/g1-memory-roundtrips-<epoch>-<pid>.json`，
拒绝覆盖已有文件；rawheap 由系统生成并保留待显式拉取。主机证据拉取应写入本工作树
ignored `.artifacts/`。不自动清除旧报告、快照或应用数据。

报告将以下状态分开：

- `roundTripsComplete`：20 次真实往返功能完成。
- `memoryCaptureComplete`：所需进程/Ark指标与两份 rawheap 转储有实际值。
- `arkGcObservedAtBothCheckpoints`：两次请求窗口 Ark GC 计数均增长；不保证由该
  请求独占触发，也不表示 Dart/native/GPU 都已回收。
- `dartVmServiceMeasured`：默认 false；只在显式握手模式收到两份匹配的外部采集确认后
  为 true。Dart 字节值和 GC 证据仍在外部 JSON 中，按确认文件 SHA-256 关联。
- `nativeAllAllocationsMeasured=false`：明确未测全部 native allocation。

零或无效的 allocator/used-heap 读数保留原值并标记不可用，不把 0 解释为无残留。
测试可完成往返但转储因配额失败，此时数据字段不完整，不得用测试 PASS 代替内存门禁。
堆快照耗费资源，这个场景不测帧时长或输入延迟，也不能与相应预算采样并跑。
PSS 与两个 VM heap 有重叠，不能相加；PSS 增量还可能来自 allocator/cache/映射，
仅凭它不能认定泄漏。报告对象和 UiTest 自身也有观测开销。

## Dart VM 后续独立采集

本机固定 Flutter-OH SDK 的
`packages/flutter_tools/lib/src/ohos/ohos_device.dart:601` 实现公开 `hdc fport`
转发，724 行标明 Dart VM Service 日志 URI 格式。需要使用明确设备、当前进程的实际
URI 和公开 WebSocket VM Service，选择实际 Flutter isolate，不能复用旧进程的地址。

先前接口静态调查使用的本机客户端：
`E:/workspace/lib/flutter/oh-pub/hosted/pub.flutter-io.cn/vm_service-15.3.0/lib/src/vm_service.dart`

- 762–786 行：`getAllocationProfile(isolateId, gc: true)`。
- 1057 行：`getMemoryUsage(isolateId)`；6541–6550 行：`heapUsage`、`heapCapacity`、
  `externalUsage` 单位为 bytes。externalUsage 只包含 embedder 向 Dart 登记的外部内存。
- 383 行 `onGCEvent`；2672 行 `dateLastServiceGC` 可用于核对 GC 是否实际发生。

实际独立CLI使用固定SDK `flutter_tools/.dart_tool/package_config.json` 解析到已存在的
**vm_service15.0.2**，没有为了执行改依赖或pub get。15.3.0路径只是最初API阅读来源。

该 RPC 的[公开契约](https://api.flutter.dev/flutter/vm_service/VmService/getAllocationProfile.html)
仅保证尝试 GC，不保证实际执行。外部采集应保留请求前后的 `dateLastServiceGC` 或 GC
事件及 heapUsage；无 GC 证据时只能报告请求后的采样值。Release 不承诺提供 VM
Service；记录实际构建模式。

现已加入最小 test-only 握手：`-s g1WaitForDartHeap true` 时，第 5/20 次完成 Ark 转储
后生成唯一 runToken/round/PID 的 `.ready.json`，保持 Flutter 返回页，最多等待 180 秒。
外部 [Dart CLI](../../../tools/flutter/README-VM-Heap.md) 读取本地复制的 ready 文件、校验
VM PID，在成功写入带哈希证据后生成 `.ack.json`。实际HVD的公开hdc -b沙箱写入
permission denied，因此ready同时发布仅绑定127.0.0.1的动态ackPort。操作者使用独占
hdc fport，向该端口发送真实CLI确认的单行紧凑ASCII JSON+LF；测试验证后自行写入沙箱。
最多4连接、16KiB、原180秒截止，finally关所有连接和listener。测试只接受匹配确认；
无效/过期或超时不得当成同点数据，也不自动继续。
建议 Hypium 总超时至少 600000 ms。确认后补充 `afterDart` 的 Ark/PSS 观察。
默认不等待，仍可单独做 Ark 诊断。两个 VM 的数据是在同一停留节点**顺序采集**，
不是同时采集。没有长期服务、生产埋点或 Android 握手；不手工伪造 ack 绕过采集。

纯逻辑复现：

```powershell
node --test harmony/tests/g1_memory_observations_test.cjs
```

Node测试还覆盖BigInt GC原值无损转字符串（0n为有效计数）和TCP分片/长度边界。
这些单测及编译本身均不证明设备接口或实际GC成功；上述真实结果来自独立Hypium/VM记录。

## rawheap失败后的公开定向GC

API20 HVD `/data`仍有4.1GiB可用，`dumpJsRawHeapData(true)`仍两次返回
`Disk remaining space too low`；没有删除应用数据或未知文件。当前设备`hidumper -h`
以及[官方命令说明](https://raw.githubusercontent.com/openharmony/docs/master/zh-cn/application-dev/dfx/hidumper.md)
支持`hidumper --mem-jsheap <pid> -T <tid> --gc`只触发指定Ark线程GC、不导出快照。
补采在5/20 ready期间执行此命令；PID/TID由本轮ready日志、夹具主线程断言以及最终report
交叉核实均23988。真实计数从3→5及5→7，随后afterDart读取主Ark堆9427/9304 KiB。
这是独立公共命令窗口的GC数值证据；原始report中仅raw请求窗口的
`arkGcObservedAtBothCheckpoints=false`和`memoryCaptureComplete=false`保持原值，不篡改。
