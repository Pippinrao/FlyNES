# OH 候选串行采集协议

状态：Debug启动2+12、同ROM65秒、20次往返与真实Dart5/20握手已执行；PSS预算失败保留，公共Ark GC补采增长-123KiB通过数值门槛，rawheap仍不可得。实际结果见[候选记录](2026-09-29-ohos-flutter-candidate-performance.md)。根据用户“先在模拟器把能测试的都测试完毕”的授权及总任务决定，沿用 [固定预算](2026-09-29-performance-budget.md) 执行，不另加预算确认停工点。`g1CandidateApproved=true` 仍作为防误跑的显式参数，不能替代设备窗口协调；各批都在总任务明确交接后串行执行。

## 固定配对与顺序

生产修订 `eaafd7d0 / 3.0.5`，设备仅任务 `127.0.0.1:5557`。不操作用户 5555 或升级任务 HVD。保留已测生产主包：

- `.artifacts/flutter-g0/performance-eaafd7d0/entry-default-unsigned.hap`，SHA-256 `C2B45DF0A36E71D2FAD8A7222DA91E03EC5BD2A8E193B1E22006757E9A2C73F6`。
- 初始仅覆盖安装 `.artifacts/oh/a55c850c/packages/entry-ohosTest-unsigned.hap`，SHA-256 `B71B3C5FE18F315BD90C6DA97D70F217520B0DA5A77386C8BA5BC0815964072C`。后续真实夹具失败所需test-only重建及SHA均列在候选记录，Debug主包保持C2B45不变。

两个文件已离线复核哈希；不会把重新生成的 A58E… 主包换进对照。无卸载、清数据、ROM 更换或 SDK 修改。每批使用新 ignored 输出目录，所有失败均保留。

### 1. Flutter 启动（2 次预热 + 12 次正式）

使用现有 `Collect-OhosStartup.ps1 -Route flutter -CandidateApproved -Warmups 2 -Samples 12 -OutputDirectory <新目录>`。每个样本先 force-stop，再单独 aa test，核对不同 PID、完整 JSON、Hypium 结果、真实偏好恢复与规范时刻。入口是原有 debug Want，原生与 Flutter 均为 ALL、空搜索，投影应同为 7 条。请求→UiTest enabled 主按钮 P95 对照 1598 ms，固定阈值 3098 ms；首卡另列。不冒充进程首帧或物理呈现。

### 2. 同 ROM 65 秒自动保存

参数 `-s g1NativePerformance true -s g1Entry flutter -s g1CandidateApproved true -s timeout 240000`。夹具通过真实 Flutter 卡片与主按钮进入既有 RunGame，保留 Flutter engine，不能直接 native route 替代。

固定原生身份：contentKey `6F80D56CE0B242A4FACEAFAFEA321FEB1C364AB8E7937646E8580AE9289A4EC3`，来自许可清单默认首项，PAL sourceFPS `50.0069789081886`；60,000 ms 保存，音频开启，20 ms 计数 / 1000 ms 内存采样，原生开始前历史 90 条。候选报告须核对相同身份、间隔及近似记录规模，且实际模拟进度至少 65 秒、真实 AUTO/head 改变。不得重置历史来得到匹配。

公开 `summarize_ohos_performance.py` 复算：PSS P95≤284718 KB；源/显示增长观察 P95≤27.3/49.3 ms，保存上下文源/显示最大≤81/86 ms，输入软件上界 P95≤54 ms。音频欠载按实际模拟时长归一到 65230.895 ms 后≤650.1 次，不向上取整、不忽略原生已有欠载。指标属于仪器化模拟器观察，非逐帧呈现。

### 3. 20 次往返与 Ark/Dart 第 5/20 次握手

独立于启动/帧延迟批次，参数：

```text
-s memoryRoundTripsOnly true -s g1CandidateApproved true -s g1WaitForDartHeap true -s timeout 600000
```

夹具保持同一进程和同一 Flutter 页，每轮真实主按钮启动→帧增长→暂停→原生菜单返回，断言音频停止、core owner 关闭、renderer 呈现计数停止。先保留无 GC 的 PSS/Ark 轨迹；第 5/20 次分别请求 Ark rawheap 并保留 GC 计数，随后生成唯一 ready 文件并最多等待 180 秒。

外部配合流程：

1. 只读取当前任务 PID 的实际 Dart VM Service 日志 URI，保存到 ignored 私有文件，不在聊天、命令参数或 tracked 文件输出认证 token。建立一个任务专用 loopback `hdc fport`，记录无 token 的 PID/端口归属；不用旧进程地址，不使用 `flutter attach` 自动恢复/重启 isolate。
2. 拉取本轮第 5 次 `.ready.json`，核对 PID、runToken、round、有效期。CLI 使用固定 SDK Dart 和已存在 flutter_tools package config，无安装或 pub get。
3. `collect_vm_heap.dart --vm-uri-file <私有文件> --checkpoint-file <ready> --ack-output <新ack> --output <新证据> --request-gc`。仅 exit 0 且完整非缺失堆值时，通过独占hdc fport向ready.ackPort发送CLI真实ack的单行紧凑ASCII JSON+LF；fixture验证后自行写sandbox ack。公开hdc -b写入实测permission denied，原失败保留；不手工构造确认。第20次使用同进程且已核对的isolate id和全新文件重复。
4. 保留Ark原始报告、可取得的rawheap及不能取得的真实错误、两份ready/ack、Dart before/after heap与GC证据及SHA。采集完成后移除仅本任务创建的端口转发，停止仅本任务helper，保留模拟器和应用数据。rawheap不可得时，公开hidumper指定本轮PID/TID的--gc补采必须另记请求与实际计数，不篡改原rawheap状态。

CLI 位于 `tools/flutter/collect_vm_heap.dart`，完整契约见 [VM 堆说明](../../../tools/flutter/README-VM-Heap.md) 和 [OH 内存方案](2026-09-29-ohos-memory-protocol.md)。缺失/负堆值、过期握手、PID 不符、无 GC 证据必须如实失败或标缺项，不能用 Hypium PASS 代替内存门禁。

Ark 第 5→20 次有 GC 证据的 used heap 增长阈值为 16 MiB；Dart heap/external/native/PSS 独立报告，不相加也不宣称全部已回收。两个 VM 在相同返回节点顺序采集，非同时；heap/GC 操作不与帧延迟测量并跑。

## 本轮不改变的边界

固定预算不按候选结果调整。若采集失败，先保留原始日志和状态，再最小定位夹具/产品问题，与总任务协调是否需要构建；不替换主包后继续冒称同字节比较。原生 200 ms 首卡门槛、原生音频欠载、真机与 iOS 缺项仍独立列出。仅完成模拟器诊断不等于 G1/三端迁移放行。

## 独立Release诊断

Debug PSS失败后，经主任务明确授权建立同Release主包/匹配Release测试包的native与Flutter对照；不覆盖Debug结论。标准`Build-Ohos.ps1 -Mode release`构建后，单独公开hvigor以`buildMode=release`构建ohosTest，不放宽脚本默认debug测试守卫。测试HAP自身debug元数据仍true，但各ABI的libapp/libflutter必须与Release主逐字节匹配，安装后的真实EntryAbility debug=false是硬门槛。测试以显式`g1BuildMode=release`从真实UI router进既有FlutterFoundation；产品Release debug Want gate不改。若系统禁止运行，不修改debug标志绕过。两路之间不换主包/测试包，native后、Flutter前冻结同模式实际数字门槛。
