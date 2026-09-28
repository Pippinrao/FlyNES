# FlyNES Flutter migration foundation

本目录是渐进嵌入现有应用的 Flutter **module**，当前提供 G1 真实目录验证页、深色主题和窄客户端。
Harmony 已添加现有宿主内的 debug 实验入口；Android/iOS 尚未接入。目录桥不等于游戏往返或 G1 已通过。

## 目录与后续工作

| 目录 | 当前内容 / 后续对应需求 |
| --- | --- |
| `lib/main.dart` | 唯一 Dart 启动入口 |
| `lib/app/` | 最小 App 组合；后续 F01 路由/生命周期 |
| `lib/design_system/` | 批准的 Android 深色 token；后续 F02 完整设计系统 |
| `lib/features/foundation/` | 真实目录、选择与开始/继续能力投影；全量外围页面仍归G2 |
| `lib/native_client/` | G1 typed projection / 请求代次 / 窄方法桥；REQ-009 完成统一客户端 |
| `test/` | 客户端与widget断言；不冒充平台安装验收 |

后续按需在 features 下增加 library、settings、nearby、saves、play，
不预先生成没有实现的业务类。公共 C++、Nearby、save_history 的拆分由各自需求推进。

总需求入口：[44 模块 / 45 项需求路线](../../docs/flutter-migration/roadmap.md)，
当前交接见 [工作区进度](../../docs/flutter-migration/STATUS.md)。
当前实际完成范围以 STATUS 和 verification 为准，不表示 G1 三端闭环已完成。

## 本地检查

已使用上游 Flutter **3.41.7** / Dart **3.11.5**，SDK revision
`cc0734ac716fbb8b90f3f9db8020958b1553afa7`。生成器 revision 记录在 `.metadata`，
提交 `pubspec.lock` 固定当前依赖解析结果。未引入路由、状态管理或业务插件。

仓库根目录运行：

```powershell
pwsh -File tools/flutter/Check-Flutter.ps1
# 使用另一个已验证 SDK 时显式指定，不自动下载或升级 SDK：
pwsh -File tools/flutter/Check-Flutter.ps1 -FlutterCommand 'C:/sdk/flutter/bin/flutter.bat'
```

或在本目录运行：

```text
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub --reporter expanded
```

有可用 Android/iOS 环境时可通过 `flutter run -d <device-id>` 运行临时模块宿主。
`.android/`、`.ios/`、IDE 文件和构建缓存均是生成物，不作为生产宿主提交。
生产包身份仍归现有 `app/`、`harmony/`、`ios/`，不安装生成宿主覆盖用户原 App。

## 三端接入边界

| 平台 | 本次状态 | 下一步 |
| --- | --- | --- |
| Android | module 配置已生成；未改生产 Activity/Gradle 接入 | REQ-006：验证现有宿主嵌入和原生游戏往返 |
| iOS | module 配置已生成；未改生产 UIKit/CMake 接入；用户要求本轮先不验证Mac | REQ-006：后续在 Mac 验证嵌入、构建及生命周期 |
| HarmonyOS NEXT | 1.0.0候选通过API20 HAR/真实宿主构建；debug Want进入目录实验页 | REQ-005运行结果见工具链记录；REQ-006游戏接线未完成 |

上游 module 模板只生成 Android/iOS 开发宿主，不能用它宣称鸿蒙已接入。
如 Flutter-OH 需要不同的薄宿主装配，仍消费本目录同一份 Dart 源码，
不得复制第二套页面。三端插件与工具链正式配套在 G1 验证后锁定。

## 版本与数据

产品版本仅由根 `VERSION` 决定；本 module 不声明独立 pubspec version。
版本线为 3.0.x，Android/Harmony 元数据通过仓库同步脚本和正常PATCH hook生成。
临时生成 Runner 的缺省版本不代表产品版本；后续打包集成需从 VERSION 传入
build-name/build-number，不能发布默认 Runner。

不打包任何 ROM、复制用户存档或更改原生持久化。`content/` 仍是内容单一来源。
存档库已由main@3a2dc426合入，Android/Harmony接续现有所有者，Dart不打开SQLite。
架构及存档references保留为历史参考，不能代替当前库契约与验证证据。

## Harmony 实验宿主构建

先使用 `tools/flutter/Build-Ohos.ps1 -FlutterSdk <固定OH SDK目录> -DevEco <DevEco目录> -PubCache <短缓存目录> -BuildTests`。
脚本从本目录复制同一份Dart源到忽略的构建目录，生成HAR后装入现有Stage宿主；没有第二套受维护的页面。
固定候选及机器环境见[工具链证据](../../docs/flutter-migration/verification/2026-09-29-ohos-toolchain.md)。
本阶段仅支持debug，release构建明确拒绝打包debug engine；release/profile产物仍待REQ-004验证。
现有默认入口仍为原生GameCenter，实验入口用debug Want参数 `flynes.test.page=flutter_foundation`。
