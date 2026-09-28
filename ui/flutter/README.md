# FlyNES Flutter migration foundation

本目录是渐进嵌入现有应用的 Flutter **module**，当前只提供启动页、主题边界和组件测试。
不包含游戏库、联机、存档、输入实现或原生服务绑定。它尚未进入三端生产入口。

## 目录与后续工作

| 目录 | 当前内容 / 后续对应需求 |
| --- | --- |
| `lib/main.dart` | 唯一 Dart 启动入口 |
| `lib/app/` | 最小 App 组合；后续 F01 路由/生命周期 |
| `lib/design_system/` | 最小主题；后续 F02 设计系统 |
| `lib/features/bootstrap/` | 明确展示未接入状态的启动页 |
| `lib/native_client/` | B01 边界说明；REQ-009 再确定实际 ABI 接线 |
| `test/` | 无原生 SDK/服务也能运行的启动页测试 |

后续按需在 features 下增加 library、settings、nearby、saves、play，
不预先生成没有实现的业务类。公共 C++、Nearby、save_history 的拆分由各自需求推进。

总需求入口：[44 模块 / 45 项需求路线](../../docs/flutter-migration/roadmap.md)，
当前交接见 [工作区进度](../../docs/flutter-migration/STATUS.md)。
本次仅交付工程起点，不表示 G1 三端闭环或 REQ-004～007 已完成。

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
| iOS | module 配置已生成；未改生产 UIKit/CMake 接入 | REQ-006：在 Mac 验证嵌入、构建及生命周期 |
| HarmonyOS NEXT | 当前只有共享 Dart 源码；未安装/验证 Flutter-OH | REQ-004/005：锁适配 SDK，验证 module/宿主方案，再通过自动构建安装闭环 |

上游 module 模板只生成 Android/iOS 开发宿主，不能用它宣称鸿蒙已接入。
如 Flutter-OH 需要不同的薄宿主装配，仍消费本目录同一份 Dart 源码，
不得复制第二套页面。三端插件与工具链正式配套在 G1 验证后锁定。

## 版本与数据

产品版本仅由根 `VERSION` 决定；本 module 不声明独立 pubspec version。
本次版本迁移为 3.0.0，Android/Harmony 元数据通过仓库同步脚本生成。
临时生成 Runner 的缺省版本不代表产品版本；后续打包集成需从 VERSION 传入
build-name/build-number，不能发布默认 Runner。

不打包任何 ROM、复制用户存档或更改原生持久化。`content/` 仍是内容单一来源。
本分支的架构及存档调研文档是创建时的参考快照；正在推进的存档代码应按
REQ-002 读取其实际交付 revision，不能以这些快照判断任务已完成。
