# 3.0.5 匹配 Release 构建验证

生产源码固定 `eaafd7d0a38d3a60ffe7d2db8aad8f04857d6370`，版本 `3.0.5 / 3000005`。两端构建前后生产源码无未提交差异；新增采集夹具属于测试目标。本记录证明构建、产物内容与下方实际双ABI包体预算；运行性能另有实测记录。

| 平台 | 命令与结果 | 冻结 Release 产物 SHA-256 |
| --- | --- | --- |
| Android | `Build-Android.ps1 -FlutterCommand <固定3.41.7>/bin/flutter.bat -Configuration Release`；Gradle BUILD SUCCESSFUL / 7s | `5ABED632DFF6BCE29DBC9534E5C2F54D5A60D11BCCF20E4F1979BDCEC722995E` |
| Harmony | `Build-Ohos.ps1 -Mode release`；固定3.41.10-ohos-1.0.0/API20，HAR与主HAP均exit 0，HAP 15.145s | `5C266B5FE41A2C9B2F75CDE5B02066A1F167CA402EF9D806EF03DFC86CA68CA8` |

Android framework `cc0734ac716fbb8b90f3f9db8020958b1553afa7` / engine `59aa584fdf100e6c78c785d8a5b565d1de4b48ab` / Dart 3.11.5。OH framework `244a0e8abb3085e8675589b13e219af8c41cb7aa`，SDK工作区无修改。

两端均包含 arm64-v8a 和 x86_64，每架构有 AOT `libapp.so`、`libflutter.so`、产品原生库及 C++ runtime；ELF64 machine 分别为183/62。Android无debug kernel且非debuggable；OH包内debug=false/buildMode=release，AOT snapshot符号存在，七份ROM和许可文件与单一manifest逐项匹配。

本表两包沿用未签名Release配置，构建核对时未安装；Android签名检查提示缺少MANIFEST，符合未签名事实，不作为签名成功证据。后续Android从该冻结工件生成兼容本地测试签名副本并覆盖安装，身份与性能见[Release内存对照](2026-09-29-android-release-pss.md)；不改变本表未签名包的哈希或字节比较。

证据目录：

- Android：`.artifacts/flutter-g0/android-foundation/release-eaafd7d0/`，含`artifact.json`、`build.log`、aapt和签名检查日志、构建前后源码差异。
- Harmony：`.artifacts/flutter-g0/release-eaafd7d0/`，含`package-content-abi.json`、`build-release.log`、HAR manifest、源码差异；完整构建日志`.artifacts/oh/535d3f60/`。
- 同修订native-only对照：`.artifacts/ns5/`；导出方法、源码变换及控制包构建见[可审查配方](../../../tools/flutter/README-Native-Size-Baseline.md)。

数值预算已在候选采集前固定；匹配包体差值和候选运行测量另行记录。没有将构建通过、未签名包或模拟器结果作为发布放行证据。

## 双 ABI 包体对照

两端测量窗口交接时执行独立ZIP内容核对，原版与Flutter均为上述同修订、双ABI、未签名Release产物。预算使用预先固定的双ABI增量80MiB。

| 平台 | native-only字节 | Flutter字节 | 增量字节 / MiB | 双ABI门槛 |
| --- | ---: | ---: | ---: | --- |
| Android | 32512882 | 64656926 | 32144044 / 30.655 | 通过 |
| Harmony | 26884836 | 70369059 | 43484223 / 41.470 | 通过 |

两端native与Flutter包的原生库均使用ZIP_STORED，架构对应。Harmony的`libentry.so`和两端`libc++_shared.so`逐字节哈希相同。Android `libnescore.so`在每架构的字节数均相同；ELF节对照只有36字节的`.note.gnu.build-id`不同，其余节逐字节相同，不能把它写成完全相同的二进制。该差异对包体字节增量贡献为0。

单独列出的arm64/x64库payload增量：Android 14857600/16235776B，Harmony 20170496/22490448B。它们不包含公共资源和归档头部，不冒充完整单ABI包体；本轮直接验证的是实际双ABI包的80MiB预算。

可复算记录：`.artifacts/ns5/compare_flutter_release.py`及`flutter-release-comparison.json`，包含两组完整ZIP entry、压缩方法、每库哈希、包体字节和判断。此结果只说明归档增量，不解释运行内存，也不是商店下载体积。
