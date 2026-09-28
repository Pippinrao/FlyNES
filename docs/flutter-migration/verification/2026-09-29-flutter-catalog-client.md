# Flutter 目录验证页与客户端

范围：REQ-005 共享目录页面的 Dart 部分。真实 Harmony 宿主结果另见[工具链/宿主记录](2026-09-29-ohos-toolchain.md)。本记录不代表 REQ-006 游戏往返或 G1 放行。

## 实现边界

- 用批准的 Android 深色 token 替换浅色骨架；横屏 30/70、两行水平游戏库，大字号单行，触控目标至少48。
- 页面展示宿主的真实不可变目录投影，点击卡片仅选中；横拖不调用启动。主按钮仅开始/继续，取决于恢复能力；没有大厅历史/重开按钮。
- 中英文标题、加载/错误/空目录、200%字号、短横屏与安全区有 widget 断言；无法取得服务时显示明确不可用状态，不生成模拟目录。
- `FoundationClient` 仅传 canonical ID、元数据和命令结果；不打开数据库，不传 ROM/PCM/帧，不拥有核心、热点或联机连接。
- `FoundationController` 用目录请求序号及选择请求序号丢弃旧结果；同一个 ID 在新一轮刷新后的旧结果也会丢弃。重复启动串行；返回刷新目录和真实进度；页面销毁只停止通知。
- Harmony 当前只实现 catalogSnapshot；缺失 resume/launch/openNative 方法会使客户端报告不可用，不返回伪成功。generation 是进程内桥投影响应序号，不是原生目录 revision。

## 验证与审阅修正

原浅色页面先出现真实 widget 失败（Brightness.light 与设计 dark 不符）。新控制器 API 测试在文件不存在时编译失败，随后实现并通过；两种 RED 证据区分保存，不能把缺失 API 编译错误写成事务故障复现。

客户端12项断言覆盖不可变快照、不同选择与同 ID 刷新下的迟到结果、重复启动、返回刷新、来源不可用、销毁、旧 generation、无效/重复 ID、不能从 lastPlayed 推断恢复能力、启动只携带 canonical ID、原生页面白名单。

UI审阅指出英文错误泄漏中文；添加英文通用失败、真实鸿蒙“游戏来源不可用”与中文重复提示回归，均先 RED 后修复。未知宿主返回的具体原因保留原文，后续完整客户端应采用统一可本地化错误码。

执行工作树根 `tools/flutter/Check-Flutter.ps1 -FlutterCommand <上游SDK>/bin/flutter.bat`：format、analyze 和完整测试执行结果见 `.artifacts/flutter-g0/flutter-all-green.log`。客户端12项，UI12项（共24项）；有针对性的日志包括 `flutter-hall-red.log`、`flutter-client-red.log`、`flutter-client-green.log`、`flutter-hall-english-red.log`、`flutter-hall-source-red.log` 和 `flutter-hall-source-green.log`。没有 golden 自动接受或无断言截图替代状态测试。

## 未完成项

封面引用尚未投影，当前显示标题占位卡；四分类/搜索/收藏的完整 Flutter UI 归G2。真实新 head/旧档能力、启动校验、原生设置/来源/联机返回、覆盖升级保留、texture/native view、多指/音频/帧节奏及真实双机均未因这些 Dart 测试而通过。iOS 按用户指示本轮先不验证 Mac。性能预算未冻结，本轮没有测 Flutter 候选性能。
