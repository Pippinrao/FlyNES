# Flutter-OH 工具链探针（2026-09-28～29）

状态：**REQ-004 尚未锁定；REQ-005 页面验证失败；G1 未通过**。1.0.0 的双架构 HAR、现有宿主与测试 HAP 构建通过，任务专用 API20 x64 模拟器接受 unsigned 安装。真实 Hypium 为 2 pass / 1 failure：Flutter 页面在 MaterialApp 构建时 StackOverflow，不能以构建或原生查询通过替代页面放行。

## 环境与身份

- 上游 SDK：`E:/workspace/lib/flutter/flutter`，Flutter 3.41.7、Dart 3.11.5。
- DevEco：`D:/soft/DevEco Studio`，6.0.0.878；API 20 toolchains 6.0.0.47；Node 18.20.1、ohpm 5.3.2、Hvigor OHOS plugin 6.20.2。
- 现有 Harmony 宿主：Stage `UIAbility`，bundle `com.flynes.emu`，target `6.0.0(20)`，compatible `5.0.0(12)`；本探针未修改这些配置或签名。
- Flutter 模块要求 Dart `^3.11.5`；探针复制 `ui/flutter` 的 lib、test、pubspec、lock、analysis_options 和 metadata 到忽略目录，未修改原模块。
- 探针根：`.artifacts/flutter-ohos-probe/`。初始 `hdc list targets` 为 `[Empty]`；原有 Pura 70 Pro 模拟器安装存在但未启动/安装/清数据。其镜像为 API20 x86，Emulator 6.0.0.502。

## 3.41.10-ohos-1.0.1：实测不兼容本机 API20 编译环境

[维护方仓库](https://gitcode.com/CPF-Flutter/flutter_flutter)的标签名与上游基线名不同：该标签基于上游 3.41.9，不应将其误写为不存在的 3.41.9-ohos 标签。

| 项目 | 固定值 |
| --- | --- |
| 安装目录 | `E:/workspace/lib/flutter/flutter-ohos-3.41.10` |
| tag / commit | `3.41.10-ohos-1.0.1` / `adaf911c35c9136a7d18fc424d714c9ec7724e60` |
| OH engine / HAR pin | 两者均为 `3fb08d34b6f96a15fbb219b903c9d0ab37b6c2e0` |
| CLI machine Dart | 3.11.5 |
| CLI machine upstream engine | `42d3d75a56efe1a2e9902f52dc8006099c45d937`（不是 OH engine pin） |

SDK 安装在预先确认不存在的新目录，clone exit 0；`--version --machine` 最终 exit 0，源码 `git status --short` 为空。仓库外 SDK 与现有上游 SDK 分开。

### 实际命令及退出结果

```powershell
git clone --depth 1 --branch 3.41.10-ohos-1.0.1 --filter=blob:none `
  https://gitcode.com/CPF-Flutter/flutter_flutter.git `
  E:/workspace/lib/flutter/flutter-ohos-3.41.10
# 在探针 module 目录，加载同级 environment.ps1：
flutter --version --machine
flutter pub get
flutter build har --debug --target-platform ohos-x64 --no-pub
```

- `--version --machine`、`pub get` 均 exit 0。pub cache 使用任务专用短路径 `E:/workspace/lib/flutter/oh-pub`。初始深层 `.artifacts/.../pub-cache` 触发 Git dependency 文件名过长；短 cache 排除此问题。失败 cache 保留，不清理用户 cache。
- 依赖版本未升级；镜像设置把探针 lock 的 hosted URL 从 pub.dev 改为 pub.flutter-io.cn，原模块 lock 未改。
- 原始 HAR 命令 exit 1：DevEco `ohpm.bat` 出现 batch recursion stack limit。独立 `ohpm --version` 复现 exit 255；同一 DevEco 的 `node.exe .../pm-cli.js --version` exit 0、输出 5.3.2。
- 忽略目录 `bin/ohpm.bat` 仅直接调用原装 Node/pm-cli.js。Hvigor wrapper 强制赋值 `process.env.ohpmBin`，所以仅更改 PATH 不够；在**探针生成的** `.ohos/hvigorconfig.ts` 中覆盖该值后到达实际编译。未修改 DevEco 或 Flutter SDK。
- 实际编译失败：`COMPILE RESULT:FAIL {ERROR:21 WARN:270}`，`HarCompileArkTS`。Flutter 的失败报告采集迟迟未退出，保留日志后中断；随后直接用同一 bundled Node/Hvigor 复现，退出值 `-1`，失败断言相同。不能把失败报告采集阶段误认成编译仍在运行。

直接复现命令（探针 `.ohos` 目录）：

```powershell
node 'D:/soft/DevEco Studio/tools/hvigor/bin/hvigorw.js' --mode module `
  -p module=flutter_module@default -p product=default -p buildMode=debug `
  assembleHar --no-daemon -p FLUTTER_TARGET=lib/main.dart -p TARGET_PLATFORM=ohos-x64
```

`.ohos/.hvigor/cache/meta.json` 明确记录 compileSdkVersion `6.0.0(20)`。因此不是误选 API18：生成模块的 compatibleSdkVersion 为18，但编译 SDK 确为20。

失败内容包括 Autofill 的 AutoFillType/ViewData/FillRequest/requestAutoFill 等缺失、CompetitionStrategy 缺失、Window.isInFreeWindowMode 缺失。SDK 固定源码的 `OhosAutoFillHelper.ets` 定义 `AUTOFILL_SUPPORT_API = 26`；[OpenHarmony Autofill 声明](https://github.com/openharmony/interface_sdk-js/blob/master/api/@ohos.app.ability.autoFillManager.d.ts)将 requestAutoFill 标记为 since26；[Window 声明](https://github.com/openharmony/interface_sdk-js/blob/master/api/@ohos.window.d.ts)将 isInFreeWindowMode 标记为 since22。运行时 API guard 不会消除 ArkTS 编译期名称解析需求。该候选需要更新的编译 SDK，或选择可验证的早期适配版；本轮未升级 DevEco，也未删除第三方功能规避编译器。

证据文件：`sdk-version.log`（深 cache 失败）、`sdk-version-short-cache.log`、`module-pub-get.log`、`module-har-x64.log`、`module-har-x64-shim.log`、`module-har-x64-launcher.log`、`module-hvigor-api20.log`、`module-hvigor-api20.exit.txt`，均位于探针根。

## 可行宿主形态（API 核实及后续装配）

现有 `UIAbility` 可保留，通过 FlutterManager 成对注册/注销 UIAbility 与 WindowStage；ArkUI 页面使用 FlutterEntry 生命周期和 FlutterPage(viewId)。这些 API 在固定 SDK 的 `flutter/index.ets` 和对应实现中存在。[维护方 Stage 接入指导](https://gitcode.com/CPF-Flutter/flutter_samples/blob/master/docs/ohos/app-development/ohos-integrate-flutter.md)

实际生成模块启用 `flutter-hvigor-plugin` / `injectNativeModules`。活动 builder 是 `src/ohos/hvigor.dart`，其 HAR 输出布局是 `build/ohos/har/<mode>/` 下的 `flutter_embedding_<mode>.har`、架构 native HAR 和 `flutter_module.har`。同目录的 `ohos_builder.dart` 是旧 builder，不能用它的单 `flutter.har` 示例作为当前默认产物路径。[维护方 module 接入指导](https://gitcode.com/CPF-Flutter/flutter_samples/blob/master/docs/ohos/hybrid-development/using-module.md)

当前维护方环境指南支持 Windows x64 模拟器；旧 `ohos/docs/03_environment` 页面的不支持说明已经过时。固定 SDK 的 build_har 接受 `ohos-x64`，本轮已实际下载对应 engine 工具。支持构建目标不等于此模块已运行。[当前环境指南](https://gitcode.com/CPF-Flutter/flutter_samples/blob/master/docs/ohos/getting-started/flutter-oh-env-setup.md)

## Mac 执行机

**后续用户明确要求本轮先不验证 Mac，已停止探测。iOS 状态为用户要求暂不验证，不能据此放行 G1。** 下述连接结果仅为该指令之前的历史记录。

只读取现有 SSH 配置的 Host 行，发现 alias `apple`；以 BatchMode、5秒 ConnectTimeout 执行只读 `uname -s; xcodebuild -version`，连接超时 exit1，未改变信任设置或输出配置凭据。

最近仓库证据 `docs/verification/2026-09-27-nearby-ios-parity.md` 记录 `/Users/<USER>/Developer/flynes-room-20260927`、Xcode14.3.1 / iOS16.4 SDK / CMake3.31.8 成功；这与 DEVELOPMENT 的一般 Xcode26.x 表述不一致。本轮无法连接核验当前事实，不把旧成功记录算作本轮 iOS 执行证据。

## 1.0.0：API20 HAR 构建候选已通过

只读检查 `3.41.10-ohos-1.0.0`，peeled commit `244a0e8abb3085e8675589b13e219af8c41cb7aa`，Dart 仍为3.11.5。OH engine pin `ab1841593ed352873a3d26cb41e942e90b813be0`，HAR pin `97a3efd6c9de0776f78f93c265f49491aa5d1089`。该版本不存在上述 OhosAutoFillHelper 文件，FlutterManager 无 isInFreeWindowMode 调用，EmbeddingNodeController 无 CompetitionStrategy 引用。

经授权另装到 `E:/workspace/lib/flutter/flutter-ohos-3.41.10-1.0.0`；另建 `.artifacts/flutter-ohos-probe/module-1.0.0`，复制现有共享模块，lib/test 文件 SHA256 对比0差异。使用同一任务 cache、同一 launcher workaround，未改生产目录或SDK。

| 命令 | 结果 |
| --- | --- |
| clone --depth 1 --branch 3.41.10-ohos-1.0.0 --filter=blob:none | exit0，commit 与上表一致 |
| flutter --version --machine | exit0，3.41.10-ohos-1.0.0 / Dart3.11.5 |
| flutter pub get | exit0，依赖版本未改变 |
| flutter build har --debug --target-platform ohos-x64 --no-pub | **exit0**，Hvigor27.9秒，输出真实HAR |

成功构建的 `.ohos/.hvigor/cache/meta.json` 为 compileSdkVersion `6.0.0(20)`、hvigorVersion `6.20.2`、toolChainsVersion `6.0.0.47`。SDK工作区clean。

第一次x64构建的产物（`module-1.0.0/build/ohos/har/debug`）：

| 产物 | 字节 | SHA256 |
| --- | ---: | --- |
| flutter_embedding_debug.har | 229968 | `B382919173155B880C11FB5BCD88C519E4ED0BD25B6578B7C693E8243867BD7F` |
| flutter_module.har | 17221409 | `CC401EF43C54E49C3F47A21065B21BD539366F1DB2ECC3669C3BF124B530F676` |
| x86_64_debug.har | 15131840 | `596117DC994F5DA95E2D8B84A4F4E0BB8A02E4E18D10784AA4619FC34207FD43` |

证据：`sdk-1.0.0-clone.log`、`sdk-1.0.0-version.log`、`module-1.0.0-pub-get.log`、`module-1.0.0-har-x64.log`、`module-1.0.0-har-x64.exit.txt`、`module-1.0.0-har-x64-hashes.json`。

以上为首轮 HAR 阶段结果；后续宿主与运行验证如下，REQ-004 整体与 G1 仍不能标为完成。

## 现有宿主装配及最终构建

`tools/flutter/Build-Ohos.ps1 -BuildTests` 固定 SDK commit，复制当前共享 Dart 到短路径忽略探针，构建 `--debug --target-platform ohos-arm64,ohos-x64 --no-pub`，再生成现有 `com.flynes.emu` 的主 HAP 和测试 HAP。未更改签名、包身份、版本、生产 minimum/target SDK。生成模块的 minimum 从模板 API18 对齐现有宿主 API12（固定 embedding 自身声明 API12）；这只是打包兼容，不是 API12 运行证明。

最终正式源码构建目录 `.artifacts/oh/ab9a7bb2`：version、pub-get、har-debug、ohpm-install、hap-debug、hap-tests 均 exit0。`dart-source-hashes.json` 比较7个 lib 源文件，SHA256 差异0。`har-hashes.json` 和 `hap-hashes.json` 留存产物摘要；此前失败与成功运行目录均保留。

| 最终产物 | SHA256 |
| --- | --- |
| entry-default-unsigned.hap | `2D91E2B7E121789F5522E24410A980F50626559D3A27B3580110A6AD0CB18670` |
| entry-ohosTest-unsigned.hap | `764E68E8EC4C4C9CC97894E4C092DFB80112C80B39E0D9935C8686A1A5975E44` |

现有 UIAbility 默认仍加载原生 GameCenter；仅 debug Want `flynes.test.page=flutter_foundation` 进入实验页。FlutterManager 配对管理 UIAbility/WindowStage，FlutterEntry 管理页面 engine。`flynes/foundation` 暂只实现 catalogSnapshot：复用原 N-API app owner，单次真实 native catalogSnapshot 后经 CatalogProductService 的既有 manifest 投影返回。其余方法明确 notImplemented；Dart 将缺失能力显示为不可用，不宣称游戏闭环。generation 是进程内递增桥响应序号，不是 native catalog revision。

审阅回归：真实 handler + 真实 service 测试先复现丢弃第一次查询、第二次失败被 fallback 吞掉（queries=2），再改为 loadRowsFromSnapshot，4/4 Node 测试通过。`single-snapshot-red.log` / `single-snapshot-green.log` 保存红绿证据。模块级 generation 保证 replacement handler 不归零。

HAR 当前只提供 debug。`harmony/hvigorfile.ts` 在合法 afterNodeEvaluate hook 检查实际 buildMode，非 debug 明确报错并指向 Build-Ohos；实际 `-p buildMode=release assembleHap --no-daemon` exit **-1**，`release-guard.log` 证明拒绝，不会静默将 debug engine 发布为 release。后续 release 需要独立 release HAR 方案。

Harmony host CTest 按 DEVELOPMENT 的 Debug 配置 **15/15 pass**，证据 `.artifacts/flutter-g0/harmony-host/ctest-debug.log`。先前 Release 在 NDEBUG 下 assert-only 局部触发 C4101/C4100 + WX，保留 build.log，未改产品或测试以掩盖。

## 任务模拟器真实失败及最小复现

创建全新 `FlyNESFlutterG1` HVD，仅复用不可变 SDK 镜像及设备配置，新生成任务 uuid 和 userdata；没有复制、清理或安装原用户 Pura HVD。任务实例以进程启动时间和 TCP owner 核实为 **127.0.0.1:5557**，初始 bm 查询证实无 FlyNES。5555 为其他实例，未安装/清数据。任务实例保留供后续查看。

最终主包和测试包使用 `hdc -t 127.0.0.1:5557 install -r <hap>` 成功（`emulator-install-final-main.log` / `...tests.log`）。该系统镜像允许 unsigned 安装；没有借用其他项目签名，这不是商店签名或真机安装证明。

```powershell
hdc -t 127.0.0.1:5557 shell aa test -b com.flynes.emu -m entry_test `
  -s unittest OpenHarmonyTestRunner -s flutterFoundationOnly true -s timeout 30000
```

最终 `foundation-hypium-final.log`：Tests run3、Pass2、Failure1、Error0。debug route guard 与真实 N-API owner/manifest 投影通过；`renders_real_flutter_catalog_in_existing_ability` 等待15秒后 `library !== null` 断言失败（源码约35行），status -2，suite report -1。**hdc 进程 exit0 仅代表测试命令完成，不代表测试通过。** 首次测试因新设备锁屏而中断，截图 `foundation-initial.jpeg`；正常滑动解锁后再次测试仍失败，排除锁屏即可放行的假设。

正式包直接启动命令及截图：

```powershell
hdc -t 127.0.0.1:5557 shell aa start -b com.flynes.emu -a EntryAbility `
  --ps flynes.test.page flutter_foundation
```

`foundation-final.jpeg` 显示 Flutter 红页 Stack Overflow；尚未发生成功 catalog channel 回调，未验证 root-back/reopen 或游戏往返。

仅在忽略 `.artifacts/oh/be181cd3/module/lib/main.dart` 做差分并 hot restart，未改共享 Dart 或 vendor SDK：

```dart
// 正常显示，minimal-widgets.jpeg。
import 'package:flutter/widgets.dart';
void main() => runApp(const Directionality(
  textDirection: TextDirection.ltr,
  child: Center(child: Text('OH minimal text'))));
```

```dart
// 同一 engine/device 仍失败，minimal-material.jpeg。
import 'package:flutter/material.dart';
void main() => runApp(const MaterialApp(
  home: Scaffold(body: Center(child: Text('OH minimal MaterialApp')))));
```

使用固定 Flutter CLI attach 到该任务实例的 VM service，替换忽略 main 后发送 `R` hot restart。调试地址从该进程 hilog 的 VM service 行读取，不将临时连接 token 写入文档。`flutter-attach.log` / `vm-events.log` 留存结构化错误：构建 `_FocusInheritedScope` 时 StackOverflow；上层为 MaterialApp；栈包括 `_toStringVisiting`、Element.debugFillProperties、TextTreeRenderer、ComponentElement.performRebuild，另有 `_elements.contains(element)` 断言。最小 MaterialApp 无任何 FlyNES 客户端、channel 或目录逻辑，仍可复现。进一步只替换 FlutterError.onError 输出原始 exception+stack（未禁用 assert，未替换错误页面），`stack-process.log` 同样记录 `FIRST_EXCEPTION: Stack Overflow`。具体 engine/framework 根因尚未确定，不能推广为所有 OH/ARM64 不支持。

差分完成后已恢复忽略 main（`main-before-differential.dart` 保存原件），并将最终 `.artifacts/oh/ab9a7bb2` 正式 HAP 覆盖安装后复测得到上述1 failure。attach/VM helper 已结束，任务创建的端口转发已移除。下一步应围绕该固定最小 MaterialApp 复现向维护方核查，或在获准的匹配 ARM64 设备/工具链做定向验证；本轮不升级 DevEco、不修改 vendor、不以关闭 assert 绕过。REQ-005 运行闸门未通过，不能推进依赖它的后续宿主实现。
