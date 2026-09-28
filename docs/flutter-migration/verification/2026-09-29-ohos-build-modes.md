# OH profile/release 构建模式验证

范围：REQ-004 / REQ-007，Windows 主机，固定 `Flutter-OH 3.41.10-ohos-1.0.0`、提交 `244a0e8abb3085e8675589b13e219af8c41cb7aa`、Dart 3.11.5，DevEco API20。仅验证构建/工件模式；本记录不证明安装、真实运行或性能预算。

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
