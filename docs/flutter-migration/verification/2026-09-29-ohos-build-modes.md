# OH profile/release 构建模式验证

范围：REQ-004 / REQ-007，Windows主机，固定`Flutter-OH 3.41.10-ohos-1.0.0`、提交`244a0e8abb3085e8675589b13e219af8c41cb7aa`、Dart3.11.5、DevEco API20。早期章节仅验证构建；最新Release实际运行结果如下，不能将构建成功当作运行证据。

## 最新：同模式Release真实PSS诊断

用户继续完成模拟器可测项后，标准`Build-Ohos.ps1 -Mode release`再次通过，run
`.artifacts/oh/09a2462a/`。随后独立公开hvigor命令`--mode module -p product=default
-p module=entry@ohosTest -p buildMode=release assembleHap --no-daemon`通过。
未放宽Build-Ohos的debug测试默认守卫，未改生产debug Want gate或SDK。

冻结证据`.artifacts/flutter-g0/candidate-eaafd7d0/release-paired/`：

- main SHA256 `32C907FC28AC61D75FD11B4045D290D717BFC1C24D3984422A5BE99D4D81D9B5`。
- test SHA256 `4DCEBAF5D483B960BAF92B12FF293562403B66A28191378CB0B168E8E882BE12`。
- 测试HAP两ABI的libapp/libflutter共4份库与Release主逐字节匹配；它不包含另一份libentry。
- 测试HAP自身app.debug固定true，但Release主false；同批install-r之后真实bundle及
  EntryAbility的applicationInfo.debug仍false，两路JSON均记录release/false。
- 同包原生/Flutter各一次真实65秒Hypium1/1通过，PSS P95 135379→181753 KiB，
  增量46374 KiB≤事先确定的128MiB。详细范围见[候选结果](2026-09-29-ohos-flutter-candidate-performance.md)。

这是独立Release内存补充诊断，不覆盖Debug PSS失败，不扩充原G1媒体性能放行预算。
结束时5557保留上述Release主/测试3.0.5，app已force-stop、PID为空、fport为空；
**当前HAR staging是release**。下一次默认debug测试必须显式恢复模式并选择冻结包，不能
用此处当前生成包替代已测C2B45 Debug主。以下“未安装/未运行/恢复debug”均为先前阶段历史。

## 同修订 3.0.5 Release 再验证

产品修订 `eaafd7d0a38d3a60ffe7d2db8aad8f04857d6370` / 3.0.5，运行 `pwsh -NoProfile -File tools/flutter/Build-Ohos.ps1 -Mode release` 完整通过，run `.artifacts/oh/535d3f60/`：双 ABI HAR 28.9 s、主 HAP 15.145 s，阶段 exitCode 均为 0。构建前后 OH 生产源码、共享 Dart、core/shared 与该修订 diff 为空；固定 SDK 工作目录 clean。仅测试侧/文档的并行工作不进入生产包。

独立冻结 `.artifacts/flutter-g0/release-eaafd7d0/entry-default-release-unsigned.hap`，SHA-256 **`5C266B5FE41A2C9B2F75CDE5B02066A1F167CA402EF9D806EF03DFC86CA68CA8`**。`package-content-abi.json` / `verify-package.py` / `package-verification.log` 验证：

- HAP 内实际 metadata 为 com.flynes.emu / 3.0.5 / 3000005、buildMode=release、debug=false、target API20、compileSdkVersion=6.0.0.47，宿主原 min API12 保持不变。
- arm64-v8a 和 x86_64 均有 ELF64 `libentry.so`、`libflutter.so`、`libapp.so` 与 libc++，machine 分别 183/62；两份 libapp 含 AOT isolate snapshot data/instructions 符号。
- HAP 的两份 libflutter 与该次 release 架构 HAR 内引擎逐字节一致；包内没有 debug kernel_blob。
- 单一清单逐字节一致，7 个 ROM SHA-256 与清单匹配，7 份许可文本与 source-of-truth 一致，退役游戏缺席。

本轮**没有安装 Release 包，没有计算原生/Flutter 包体差值，没有运行候选性能**。以前冻结的 3.0.5 debug 主包 C2B45… 与测试包 9874… 哈希复查不变。Release 证据与构建输出独立保留。下方较早 profile/release 数字是历史构建记录，不是本轮候选预算比较。

随后测试侧 ready/ack 握手 ETS 稳定，执行 `Build-Ohos.ps1 -Mode debug -BuildTests` 恢复默认模式，独立 run **`.artifacts/oh/a55c850c/`**。HAR、主 HAP、测试 HAP exit 0，主包 9.433 s / 测试包 6.814 s；当前 staging manifest 确认为 debug 与原固定 SDK。包含最新 `G1MemoryRoundTrips` ready/ack 夹具，但**仅编译，未安装、未执行候选**。新包独立存于该 run 的 packages：

- 主包 SHA-256 `A58E3E9DEBB4F6F3639C59492121492F0A1524ED6D5EB3B263C9A116972E03CB`。
- 测试包 SHA-256 `B71B3C5FE18F315BD90C6DA97D70F217520B0DA5A77386C8BA5BC0815964072C`。

生产源码 diff 再次为空；之前冻结的性能基线主/测试和 Release 包哈希均未改变。外层恢复日志 `.artifacts/flutter-g0/release-eaafd7d0/restore-debug-build.log`，所有阶段日志/exit 文件与新包哈希在上述独立 run 中。

**Debug候选的配对约束**：A58E…是重新生成的主包，哈希与已测主包不同且未安装。后续已获继续验证授权的Debug候选保留冻结主包**C2B45…**，仅按真实夹具修复覆盖测试包；不得默默用A58E…替换原生对照所用生产包。上述独立Release配对拥有另一组明确身份，不能混作该Debug对照。

## 固定 SDK 的实际契约

源码根 `E:/workspace/lib/flutter/flutter-ohos-3.41.10-1.0.0`，没有修改 SDK：

- `packages/flutter_tools/lib/src/commands/build_har.dart` 注册 debug/profile/release 构建模式；目标列表允许 `ohos-arm64`、`ohos-x64`。
- `build_system/targets/ohos.dart` 为两架构分别提供 profile/release `OhosAot` 目标，生成 ABI 子目录的 `app.so`，不采用 debug kernel 运行链。
- `flutter_cache.dart:1029` 起列出四个 Windows x64 主机交叉编译器：arm64 profile/release、x64 profile/release。四个本机 `gen_snapshot.exe --version` 都执行成功；arm64 输出 `windows_simarm64`，x64 输出 `windows_x64`，Dart 均为 3.11.5。
- `ohos/hvigor.dart` 的 `copyFlutterRuntime` 以模式选择 `flutter_embedding_<mode>.har`、`arm64_v8a_<mode>.har`、`x86_64_<mode>.har`；Dart 模块始终名为 `flutter_module.har`。不能只替换 engine 而复用其他模式模块。
- SDK 生成的模块 `buildModeSet` 包含 debug/profile/release，HAR 输出按 `build/ohos/har/<mode>/` 分目录。

## 仓库最小接线

`tools/flutter/Build-Ohos.ps1 -Mode debug|profile|release` 使用固定 SDK 实际编译同一份共享 Dart，每次生成独立 ignored 证据目录。HAR staging 使用四个稳定文件名并最后写入 `manifest.json`，记录模式、SDK 提交和每个文件 SHA-256。宿主 `harmony/flutter-har-guard.ts` 在 Hvigor 求值后核对请求模式、SDK pin、完整文件集合及哈希，混模式、旧工件或中断 staging 均拒绝打包。

`-BuildTests` 仅允许 debug，因为现有 Hypium 使用 debug-only 入口。模式切换必须重跑 Build-Ohos；禁止跳过守卫打包先前缓存。完成 profile/release 验证后再运行 debug，以恢复协作任务的默认构建环境。脚本将每次产物复制到该次证据目录 `packages/` 并保存包哈希，不记录签名材料。

## 验证状态

- `node --test tools/flutter/tests/ohos_har_guard.test.cjs`：RED 4/4（守卫未实现）→ GREEN 4/4；覆盖匹配三模式、debug混入非debug、模块哈希变化、缺工件和SDK pin变化。
- 新守卫接线后的 debug HAR+主包+测试包首先通过：`.artifacts/oh/1acd25b4/`。该组合的设备生命周期验证另见工具链/设备记录，不由构建成功代替。
- `pwsh -NoProfile -File tools/flutter/Build-Ohos.ps1 -Mode profile`：完整通过，`.artifacts/oh/74bfdbb5/`。
- `pwsh -NoProfile -File tools/flutter/Build-Ohos.ps1 -Mode release`：完整通过，`.artifacts/oh/08c678f4/`。
- 模拟器：本子任务不操作设备。SDK 工具具备 x64 AOT 构建目标，不将其存在等同于本项目在模拟器运行 profile/release 已通过。

## 产物核验

两种模式都直接检查 HAR 与 HAP 内容，不以文件名推断模式：

| 项目 | profile | release |
| --- | --- | --- |
| ARM64 `libapp.so` | 6,013,872 bytes，ELF machine=183 | 3,883,952 bytes，ELF machine=183 |
| x64 `libapp.so` | 6,161,328 bytes，ELF machine=62 | 4,031,408 bytes，ELF machine=62 |
| debug `kernel_blob` | HAR/HAP 均不存在 | HAR/HAP 均不存在 |
| HAP 两 ABI `libflutter.so` | 逐字节匹配该模式 SDK engine HAR | 逐字节匹配该模式 SDK engine HAR |
| 双 ABI unsigned HAP 大小 | 86,745,331 bytes | 70,368,339 bytes |

profile 包 SHA-256：`bea03442009a2307e3b721090d7545546fd378b0212c05608c80d2993ac033bf`。
release 包 SHA-256：`d37c1962e45abc96f7091396b1df0eda1148a55b504b45cef6503a6d31a98425`。

包保存在各次证据目录 `packages/entry-default-unsigned.hap`；工件模式/哈希在 `har-manifest.json`、包哈希在 `package-hashes.json`。额外检查 JSON 记录于 `.artifacts/flutter-g0/ohos-modes/*-module-inspection.json` 和 `*-hap-inspection.json`。这是双 ABI 工程包体大小，不是单架构发布包增量或性能预算。

注意：DevEco 自定义 `profile` 模式的现有 C++ 宿主缓存 `harmony/entry/.cxx/default/default/profile/x86_64/CMakeCache.txt:34` 明确为 `CMAKE_BUILD_TYPE=Debug`；release 同位置为 `Release`。Flutter 的 profile AOT 与专用 engine 已核实，但这一 profile 宿主不能直接作为整体 native 优化性能候选。本轮未扩大修改 C++ 编译策略。

最后执行 `pwsh -NoProfile -File tools/flutter/Build-Ohos.ps1 -Mode debug -BuildTests` 完整通过，恢复记录 `.artifacts/oh/46fdff43/`，HAR、主包、测试包 exit0；staging manifest 已确认 `mode=debug` 和固定 SDK 提交，构建窗口已归还设备验证任务。该次包含协作代理最新的生命周期候选，但此构建成功不证明候选已通过真实回归。

额外验证 `-Mode profile -BuildTests` 在任何构建前明确拒绝，证据 `.artifacts/flutter-g0/ohos-modes/profile-tests-rejected.log`；守卫最终4/4记录 `guard-tests.log`。未修改 SDK、Dart、版本或签名配置；没有安装 profile/release 包，也未操作设备。
