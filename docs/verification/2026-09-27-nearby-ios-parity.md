# 三端联机一致性补齐与模拟器复测（2026-09-27）

## 范围与结论边界

在 `main@08a18dd`（1.11.3）上，按用户要求补齐近期联机功能的 iOS 差异，并完成受影响模拟器回归。交互依据仍是已批准的三端 UX 与截图房间设计。本轮未修改共享联机协议，也未增加 ROM 传输、STREAM 或自动恢复。

Android/Harmony 双向房主的先前真机结果见 [真机、房间与扫码记录](2026-09-27-nearby-device-room.md)。本轮 iOS 使用模拟器，没有 iPhone 真机结果。模拟器中的原生 TCP 对端能验证真实会话和 UI 状态推进，不能替代两台真实 App 的跨设备体验验收。

## 本次补齐

| 项目 | 修改与证据 |
|---|---|
| iOS 扫码生产接线 | 页面统一使用受保护的 `NearbyQRScanner`；串行启停、授权与识别回调按代次失效；退出后不能重新启动相机。生命周期和页面绑定回归通过。 |
| 连接完成与取消 | 区分请求接受、连接中和真实已连接；退出/重试取消未完成连接，进入已连接房间保留会话；覆盖迟到完成回调。 |
| 扫码错误与热点指引 | 无效码、过期、网络和一般失败分别反馈；显式重试；较矮横屏仍展示热点说明。模拟器验证相机不可用、重试、退出。 |
| 房主换游戏 | 改为主线程异步状态推进，移除最长三秒同步等待；过期选择不能写入替换后的会话。 |
| 游戏页与房间 | 去除遗留的遮挡横幅和不可用暂停菜单项；保留继续/返回房间；根导航统一管理房间、选择页、游戏页。 |
| 暂停与恢复竞争 | 前台恢复时重新核对共享状态；独立状态检查不依赖已暂停的画面时钟；旧播放页不能暂停新局；Room 离开不重复发送 Pause 覆盖对端 Continue。 |
| 房间标题与截图 | iOS/Harmony 客机复用各端游戏大厅的语言策略；iOS 展示本机真实保存截图；继续、取消换游戏保持原局代次。 |
| 诊断 | iOS 注册共享会话诊断并记录页面代次/状态，帮助区分导航与原生会话问题；不记录邀请内容或 ROM 数据。 |

## 失败复现与修复验证

本地证据位于忽略目录 `out/device-20260927/`，不把日志、包或截图提交到仓库。

- `parity-scan-red.log`、`parity-scan-connection-red.log`：退出后的迟到回调和连接状态问题；`parity-scan-final.log` 三套回归通过。
- `parity-selection-red.log`：异步选择接口断言失败；桥接原生会话回归验证非同步完成、同连接换游戏和取消失效。
- `parity-drawer-red.log`、`parity-lifecycle-red.log`：遗留菜单、后台恢复、暂停时退出及旧视图误暂停；修复后运行时回归通过。
- `parity-room-departure-red.log`：Room 回调后对端继续，旧视图退出再次暂停；离开标记修复后通过。
- `parity-ios-live-diagnostic.log`、`parity-live-lifecycle.log`：实际 UI 暴露根导航与嵌套目的页冲突，换游戏没有创建新播放页，最终原生会话超时。统一导航后 `parity-ios-live-green.log` 两项通过。
- Live UI 测试最初还发现测试端缓存了安装前容器路径。现在以每次运行 UUID 选择当前容器。截图测试使用唯一临时封面根目录，清理仅针对该目录，不读写用户原有封面；测试夹具只启用于 Debug 模拟器测试构建。

两项 Live UI 测试走真实产品入口和原生 TCP 会话：

1. iOS 客机暂停抽屉打开时，原生房主更换 ROM；验证新标题、新播放代次及新画面继续运行。
2. iOS 房主从游戏大厅选游戏并开局，捕获实际画面保存到隔离封面目录；回房间显示截图、继续保持进度/代次；取消换游戏保留原局；选择页收到对端继续后自动回到原局。

## 执行结果

| 检查 | 结果 | 证据文件 |
|---|---|---|
| iOS 相关 UI（Live Room 2、UI Parity 7、UX Restoration 8） | 17/17 通过，0 失败，184.3 秒 | `parity-ios-ui-final.log` |
| iOS 运行时（联机桥、标题/封面、音频、手柄、播放桥） | 最终导航版本 34/34 通过，0 失败 | `parity-runtime-navigation-final.log` |
| iOS 纯 Swift 扫码生命周期、连接流、生产绑定 | 3 套通过 | `parity-scan-final.log` |
| Android 单元 | 571 项，569 通过、2 跳过，0 失败/错误 | `parity-android-unit.log` 及 Gradle XML |
| Android 相关模拟器 instrumentation | 15/15 通过 | `parity-android-ui.log` |
| 共享联机 host CTest | 14/14 通过 | `parity-shared-host.log` |
| Harmony host CTest | 15/15 通过 | `parity-harmony-host.log` |
| Harmony 隔离模拟器房间 UX / 目录服务 | 10/10、4/4 通过 | `parity-harmony-ux-unlocked.log`、`parity-harmony-catalog.log` |
| Harmony 主包与测试包构建 | 通过 | `parity-harmony-build.log`、`parity-harmony-test-build.log` |
| iOS 产品源码契约 / 内置内容门禁 | 通过 | 直接运行 Python 契约脚本；`parity-content-final.log` |

iOS 在 Mac 源码副本 `/Users/<USER>/Developer/flynes-room-20260927` 编译。使用该机现有 Xcode 14.3.1 / iOS 16.4 模拟器 SDK、CMake 3.31.8，目标为 iPhone SE 模拟器。源码同步后更新时间并重新构建测试目标；运行器自身不负责构建。

最终 UI 与运行时结果分别保存于该副本的 `build/ios-simulator/evidence/tests-20260927-213602.xcresult`、`tests-20260927-213921.xcresult`。两次执行均为 `TEST EXECUTE SUCCEEDED`。完成后对导航代次、Room 离开与夹具数据隔离进行只读复审，未发现新的重要阻塞。

```sh
cmake --build build/ios-simulator --config Debug --target FlyNESRuntimeTests FlyNESUITests --parallel 2
python3 ios/scripts/run_simulator_tests.py <LOCAL_UUID> FlyNESUITests \
  -only-testing:FlyNESUITests/NearbyLiveRoomUITests \
  -only-testing:FlyNESUITests/NearbyUiParityTests \
  -only-testing:FlyNESUITests/NearbyUxRestorationTests
```

Android 使用现有 `emulator-5566`，本轮未修改 Android 产品源码。Harmony 真机断开且用户表示暂时无法重连；旧模拟器安装因签名不一致不能覆盖，未卸载或清数据。另建 `FlyNESParity` 隔离模拟器，先确认没有应用安装，再安装无签名调试模拟器主包与测试包。初次锁屏导致 UI 测试停滞，解锁后重跑通过。该安装结果不代表签名真机安装通过。

## 仍待真机验证

- iOS 实际相机扫码速度与权限切换、热点系统流程、跨设备输入、扬声器/音频路由和触控表现。
- 三端热点互通、物理画面、刷新率、温度、功耗，以及单机对照的本地 P50/P95 增量 ≤5 ms。
- 先前 Harmony 房主的 `rollback_capture` 偶发内部错误仍未确定根因；本轮未修改共享核心，后续通过不能视为已修复。

以上结果覆盖本次发现的联机差异和相应回归，不表示所有产品功能、所有设备组合均已验收。
