# Flutter 迁移骨架验证记录

日期：2026-09-28。分支 `codex/flutter-foundation`，创建基线 `78057350c12b`。
工具：上游 Flutter 3.41.7（`cc0734ac716fbb8b90f3f9db8020958b1553afa7`）、Dart 3.11.5、PowerShell 7。

## 改动范围

- 仓库脚本建立独立 worktree，用户明确授权版本迁到 3.0.0；Sync-Version -AllowMajorChange 同步 major 与 Android/Harmony 元数据。
- 新增可嵌入的 Flutter module、最小启动页、主题边界、原生客户端说明和命令行检查。
- 无生产原生代码、核心、音视频、存档或网络实现改动；未嵌入现有三端宿主。
- 重构资料集中到 docs/flutter-migration，并在 AGENTS 与 STATUS 说明协作范围。

## 实际检查

| 检查 | 结果 |
| --- | --- |
| TDD 失败阶段：替换生成模板的 smoke test，再执行 `flutter test --no-pub --reporter expanded` | 正确失败：默认模板找不到 `FlyNES` 文本（编译成功后的断言失败） |
| 实现最小启动页后 `pwsh -File tools/flutter/Check-Flutter.ps1` | pub get、格式检查、analyze 无问题，widget test 1/1 通过 |
| `Invoke-Pester -Script tools/versioning/tests/Versioning.Tests.ps1 -PassThru` | 5/5 通过 |
| `git diff --check` | 通过；Git 的 LF/CRLF 提示不属于行为失败 |
| 独立只读代码审查 | 未发现具体缺陷；核对版本来源、脚本退出处理、生成物忽略与范围 |

版本记录：VERSION=3.0.0，VERSION_MAJOR=3，Android/Harmony versionCode=3000000。
iOS 已有 CMake 从根 VERSION 读取版本；本次未在 Mac 构建其安装包。
Flutter module 不声明独立产品 version，pubspec.lock 随源码保留。

## 未验证范围

未执行 Android/iOS/Harmony 应用打包、设备安装、原生集成与游戏流程；未安装/验证 Flutter-OH。
当前测试只证明上游 Flutter 环境中的公共骨架可加载、静态检查通过。
不能据此宣布 G1、原生音视频、真实手柄、存档迁移或联机验收完成。

现有原生运行行为没有改动，未启动无关全平台测试。生成宿主与缓存被忽略；
未覆盖用户安装、导入 ROM 或修改任何现有存档。
