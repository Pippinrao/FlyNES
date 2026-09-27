# 附近联机选游戏与模拟器复测（2026-09-25）

基线为当前 `main` 工作区；代码和测试仍未提交。本记录只对应 2026-09-25 的工作区与构建包，不把 2026-09-24 的旧包结果算作本次通过。测试邀请和 ROM 内容未写入记录。

## 用户指出的路径

扫码建立连接后，房间保持空白游戏身份；房主从现有游戏大厅明确选游戏。客机按房主发布的身份匹配本机 ROM，双方匹配后自动执行内部准备并开局。房间不再显示“确认入局”。房主回房间选另一款游戏时，保留原会话和座位，等待双方回到房间态后重新配置。Android、HarmonyOS NEXT、iOS 的页面与桥均按此路径改动；共享协议仍使用原 READY 消息。

Android 新回归测试先在扫码后观察到 `CONFIGURING(5)` 而非预期空房间 `LOBBY(3)`，修复默认选游戏后通过。iOS 旧桥的 `configureLocalGameIfNeeded:` 自动选游戏入口也先由测试查出，再移除并通过断言。

## 本次实际执行

| 平台与范围 | 结果 | 证据 |
|---|---|---|
| Android 构建、单元与测试包 | `assembleDebug`、`assembleDebugAndroidTest`、`testDebugUnitTest` 通过 | `out/nearby-20260925-android-final-build.log` |
| 仓库 CI 与共享宿主 | CI 五项全通过：平台头约束、ABI、核心宿主、共享层 CTest 132/132、Android 构建。共享层真实 Quinn 双引擎与 Android QUIC 适配器两项均通过。 | `out/nearby-20260925-ci-check-green.log`、`out/nearby-20260925-shared-ctest-green.log` |
| Android 新房间及相关 UI instrumentation | 11/11 通过 | `out/nearby-20260925-android-final-targeted.log` |
| Android 全量可运行 instrumentation | 65 类、195 项全通过：支持 ES 3.1 的 `emulator-5600` 先过 41 类；并行启动第二个 Harmony 模拟器时该 AVD 从 ADB 消失，剩余 24 类在 `emulator-5590` 补跑全通过。另在 `emulator-5600` 跑 ES 3.1 呈现专项 5/5。外部对端和真机资格用例另列。 | `out/nearby-20260925-android-es31-class-summary.log`、`out/nearby-20260925-android-recovery-summary.log`、`out/nearby-20260925-es31-tests.log` |
| Android 房主 → Android 客机，两个独立 AVD | 双方各 1/1；真实会话、同一 ROM、P1/P2 输入、GPU/AudioTrack、暂停、回房间、房主明确选另一款游戏，同一 session ID 下继续运行 | `out/nearby-20260925-android-android-host.log`、`out/nearby-20260925-android-android-guest.log` |
| Android 房主 → iOS 客机 | 双方各 1/1；当前包同一 ROM、两端运行至 600 帧，iOS 客机读取原始画面与 PCM | `out/nearby-20260925-android-host-ios.log`、Mac `/tmp/flynes-nearby-final-android-host-ios-guest.log` |
| iOS 房主 → Android 客机 | 双方各 1/1；当前包同一 ROM、两端运行至 600 帧，Android 客机 P2 输入、GPU 与 AudioTrack 断言通过 | `out/nearby-20260925-ios-host-android-guest.log`、Mac `/tmp/flynes-20260925-ios-host-android-final.log` |
| iOS 房主 → iOS 客机，两个独立模拟器 | 当前包双方各 1/1；同一 ROM、P1/P2 输入、各运行至少 600 帧，画面与 PCM 断言通过。测试等第二台 XCTest 启动后再计连接结果。 | Mac `/tmp/flynes-20260925-ios-ios-host.log`、`/tmp/flynes-20260925-ios-ios-guest.log` |
| iOS 当前包构建、附近桥回归、附近 UI | 构建通过；桥 4/4、UI 11/11 通过，包括空房间、无确认控件、扫码直入相机、真实邀请 QR、横屏布局 | Mac `/tmp/flynes-20260925-tests-build.log`、`/tmp/flynes-20260925-nearby-runtime-green.log`、`/tmp/flynes-20260925-nearby-ui.log` |
| iOS 全量 runtime | 最终界面与导航源码重建后运行 56 项，54 通过、2 项无外部对端时按设计跳过、0 失败；这 2 项另接 iOS 双模拟器对端分别通过。音频用例在离线 AVAudioEngine 中接入真实游戏 PCM，检查非静音混音和播放时钟；36,000 帧长时测试通过。物理扬声器输出仍属真机项。 | Mac `/tmp/flynes-20260925-runtime-final-ui-route.log`、`/tmp/flynes-20260925-ios-ios-host.log`、`/tmp/flynes-20260925-ios-ios-guest.log` |
| iOS 导入与游玩 UI 专项 | 单文件导入、收藏、重启、启动、暂停、移除 1/1；100 款目录导入、去重、别名搜索、重扫、移除、重启 1/1。模拟器没有 RemoteIO 设备时，测试进程使用离线 AVAudioEngine 验证 PCM 通路，避免系统音频驱动在 `prepare` 阶段终止进程。 | Mac `/tmp/flynes-20260925-ui-import-focused5.log`、`/tmp/flynes-20260925-ui-hundred-focused2.log` |
| iOS 全量 UI | 最终界面与导航源码全部 28 项通过、0 失败。覆盖附近入口、扫码相机、真实邀请 QR、无确认控件、空房间与真实游戏库导航、横屏布局、文件导入与清理、7 款内置游戏逐款启动和输入、暂停设置返回、语言及设置持久化。 | Mac `/tmp/flynes-20260925-ui-final-ui-route.log` |
| HarmonyOS 当前源码 | HAP、ohosTest 包构建通过；宿主 CTest 15/15；最终全量 Hypium 176 项、0 失败、0 错误；附近 UX 与双卡入口专项通过。用全新隔离模拟器 `127.0.0.1:5559` 安装当前签名包，保留原实例数据。 | `out/nearby-20260925-harmony-ui-host-ctest.log`、`out/nearby-20260925-harmony-entry-cta-full.log`、`out/nearby-20260925-harmony-entry-cta-green.log` |
| Android 房主 → Harmony 客机 | 当前包双应用产品测试通过：双方画面、音频与输入，暂停、回房间及同一连接内换游戏。 | `out/nearby-20260925-current-android-host.log`、`out/nearby-20260925-current-harmony-guest.log` |
| Harmony 房主 → Android 客机 | 当前包双方各 1/1，通过同一 ROM、P1/P2 输入、帧与 PCM 断言。 | `out/nearby-20260925-harmony-host-android.log`、`out/nearby-20260925-harmony-host-android-guest.log` |
| iOS 房主 → Harmony 客机 | 当前包双方各 1/1，通过同一 ROM、P1/P2 输入、600 帧与 PCM 断言。 | `out/nearby-20260925-ios-harmony-guest.log`、Mac `/tmp/flynes-20260925-ios-host-harmony.log` |
| Harmony 房主 → iOS 客机 | 当前包双方各 1/1，通过同一 ROM、P1/P2 输入、600 帧、RGB565 与 PCM 断言。测试转发脚本先确认 SSH 反向端口监听，再启动 UDP 桥。 | `out/nearby-20260925-harmony-host-ios-final.log`、Mac `/tmp/flynes-nearby-harmony-host-ios-guest.log` |
| Harmony 房主 → Harmony 客机 | 两个隔离的当前包模拟器，双方各 1/1，通过真实 QUIC、同一 ROM、P1/P2 输入、600 帧、RGB565 与 PCM。 | `out/nearby-20260925-harmony-harmony-host.log`、`out/nearby-20260925-harmony-harmony-guest.log` |
| 内置内容约束 | 7 款游戏的单一来源检查通过 | `out/nearby-20260925-content-gate.log` |

跨 Windows 与 Mac 的 UDP/TCP 转发仅位于忽略的 `out/` 测试脚本，用来连接两个主机上的模拟器；没有进入产品代码。原 Harmony 模拟器的签名不一致实例未卸载、未清空。首次 Harmony→iOS 转发启动早于 SSH 端口就绪，随后一次已连接但帧数停住；在端口就绪检测和双方进度记录后重跑，双端完整通过。失败的尝试保留在本地日志，不计入通过。

## 仍需验证

- 真实摄像头扫码、系统热点、物理显示和扬声器、触控延迟、刷新率、温度及功耗必须用真机签收。模拟器通过不代表两台真机已完成双人游玩。
