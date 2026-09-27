# 三端附近联机实施与模拟器验证（2026-09-24）

## 源码与包

基线：`main@fe12f9ac604a0871a06c72200125d543447b191b`，版本 `1.7.23`。本轮修改仍在工作区，未提交；`AGENTS.md` 的原有本地修改被保留。下面的哈希仅对应本轮测试包，不是商店签名包。

| 包或可执行文件 | SHA-256 |
|---|---|
| Android `app-debug.apk` | `AB4B0B6BA69BE604713D53C97E9D4F28EDB788F803B94A055FAB43A127FF5D2E` |
| Android `app-debug-androidTest.apk`（原全量扫测） | `A5CF4AD826BBDE5CE8C0FF0DD075A47D4107F2007E4477348B98F12E71411260` |
| Android `app-debug-androidTest.apk`（同平台双模拟器夹具更新后） | `F325D8AF86EA99822D96463FF92498FC518D4A08314183AF8FDBF0E71C51D568` |
| Harmony `entry-default-unsigned.hap` | `3E9DDEF1D78C232B974C1653D259E287F8175CB6CD8CD4CDA96799A992C63914` |
| iOS Simulator `FlyNES.app/FlyNES` 主可执行文件 | v3 包按用户安排留到下一轮重建和记录 |

## 产品接线与体验修复

三端新版建房、扫码、房间、选游戏和游戏入口现在使用同一进程持有的真实 LAN 会话。Android 客机按房主游戏身份匹配本地内置或导入的 ROM；Harmony 房主选择本地游戏并生成真实邀请；iOS 的建房、扫码、确认、游戏页使用共享桥与播放源。无 ROM 传输。

Android 联机移除 Canvas 二次缩放与固定过滤，共用单机 GPU 出口和显示设置；音频线程保留部分写入余量。Harmony/iOS 继续走单机渲染和音频设备层。共享会话不再由显示/PCM 轮询驱动，按源 NTSC/PAL 时序执行，输入于模拟帧前取最新值；远端最多预测 10 帧，12 槽回滚。更正后的画面只发布最终帧；外部画面序号单调递增，已交付 PCM 不重复播放。版本化输入 ABI 保留本地采集时间与序号，旧调用自动在提交边界打本机单调时间戳；重演复用历史输入元数据。配置哈希隔离旧同步实现，旧 ABI 布局未改。

跨端重测暴露了准备状态竞态：房主先发 READY 时，客机后来加载相同 ROM 曾清掉房主的 READY，接收 START 后以配置不匹配结束。新增定向断言先失败，修复后保留相同配置哈希的对端 READY，六个方向均重新通过。回滚的外部播放隔离实现在共享会话层，未另增 runtime 重演输出 ABI；测试直接检查最终画面与 PCM 的外部行为。

独立代码审阅还发现 iOS 把对端合法暂停误判为会话结束，以及客机只按游戏标识记忆 ROM 加载尝试。同一游戏标识下若房主更换配置，Android、Harmony、iOS 客机现在以共享会话的对端配置哈希为重新匹配依据；已配置且未变化的局不会重复加载。iOS 播放页在对端暂停时保持画面与会话，恢复后继续按源时钟运行；仅会话离开运行态才返回大厅。两类回归均先有失败断言，再修复。

复审发现 iOS 后台返回会遗留本机暂停。共享会话现分别保留双方暂停请求，只有两方均解除才恢复；iOS 只在自己确实发起后台暂停时解除该请求，对端暂停仍有效。暂停交互的兼容指纹从 v2 升到 v3，必须三端同版重新开局。短按锁存只在输入提交被接受后消费。跳过短暂大厅状态的同 ROM 新局，由本地配置由 1 归 0 的变化触发重新匹配。双暂停、短按和同局重开断言先红后绿。

## 模拟器证据

| 范围 | 结果 | 证据 |
|---|---|---|
| 共享真实 QUIC、ROM、预测/回滚、双暂停、停顿、提前 READY、输入时间戳、同帧原始像素等 CTest | 当前源码 14/14（8+6）；新增像素断言另连续 4 次通过 | `out/nearby-20260924-shared-nearby-ctest.log`、`out/nearby-20260924-shared-nearby-extra-ctest.log`、`out/nearby-impl-pause-v3-pixel-test.log`、`out/nearby-impl-pause-v3-pixel-repeat-{1,2,3}.log` |
| Android 构建和单元测试 | 最终包 `:app:assembleDebug :app:assembleDebugAndroidTest :app:testDebugUnitTest` 通过；配置令牌及新局回归先红后绿 | `out/nearby-20260924-saf-fix-build.log`、`out/nearby-impl-round-retry-red.log` |
| Android 新接线、真实帧 GPU/AudioTrack instrumentation | 最终包受影响回归 16 通过、1 个隔离植入用例因显式前提跳过；该用例在隔离 AVD 中另行通过。真实会话画面上传和 PCM 写入通过；同游戏标识更换配置的房间测试 2/2 | `out/nearby-20260924-android-final-affected.log`、`out/nearby-20260924-disposable-catalog-seed.log`、`out/nearby-impl-pause-v3-android-lobby.log` |
| Android 附近 UX 包 instrumentation | 最终包 44 通过、1 个需要 Harmony 客机的用例跳过；该用例在双模拟器跨 App 测试中另行通过。扫码导航的短暂 RESUMED 时序断言修复后连续 5 轮 5/5 | `out/nearby-20260924-android-ui-final-apk.log`、`out/nearby-20260924-final-android-host.log`、`out/nearby-20260924-android-approved-fixed-{1,2,3,4,5}.log` |
| Harmony host CTest | 当前源码 15/15 | `out/nearby-20260924-harmony-host-ctest.log` |
| iOS Simulator 真实双会话 ROM/画面/PCM、对端暂停恢复 | v2 桥接 3/3 曾通过；v3 待重建，画面对照正在改为按核心帧号比较 | Mac `/tmp/flynes-nearby-config-token-ios-runtime-final.log` |
| iOS Simulator 新版附近 UX | v2 7/7 曾通过；v3 待重跑 | Mac `/tmp/flynes-nearby-config-token-ios-ui-final.log` |
| iOS Simulator Metal 像素、AVAudioEngine 实际 mixer 非静音及播放时钟 | v2 7/7 曾通过；v3 待重跑 | Mac `/tmp/flynes-nearby-config-token-ios-runtime-final.log` |
| Android 房主/P1 → Harmony 客机/P2 双模拟器跨 App 产品路径 | 最终 Android 包＋v3 Harmony 包双方 1/1；真实 QUIC、同 ROM、触控 P1/P2、帧、音频消费、暂停恢复、回大厅、同会话换游戏 | `out/nearby-20260924-final-android-host.log`、`out/nearby-20260924-final-harmony-guest.log` |
| Harmony 房主 → Android 客机 | 最终 Android 包＋v3 Harmony 包双方 1/1；同 ROM、600 帧、GPU、AudioTrack、P2 输入 | `out/nearby-20260924-final-harmony-host-android.log`、`out/nearby-20260924-final-harmony-host-android-guest.log` |
| Android 房主 → Android 客机（双 AVD） | 双方各 1/1；同版包、真实 QUIC、同 ROM、P1/P2、GPU、AudioTrack、暂停恢复、回大厅、同会话换游戏。房主测试夹具原只提交 ROM，未发布游戏身份，已据首次失败改用 `selectGame`；客机夹具补同会话换游戏配合 | `out/nearby-20260924-android-android-host.log`、`out/nearby-20260924-android-android-guest.log` |
| Harmony 房主 → Harmony 客机（双模拟器） | **未通过、未验收**。第二隔离实例的普通 Hypium 冒烟测试亦出现 `TestAbility onDestroy unexpectedly`；首次跨实例尝试房主 0/1、客机未完成。复制已验证实例的数据、重启及配置对齐后仍复现，尚不能归因为联机产品代码 | `out/nearby-20260924-harmony-harmony-host.log`、`out/nearby-20260924-harmony-harmony-guest.log`、`out/nearby-20260924-harmony-clone-smoke-signed-copy.log` |
| Harmony 房主 → iOS 客机 | v2 双方 1/1；同 ROM、600 帧、原始画面、PCM；v3 待复测 | `out/nearby-impl-harmony-host-ios-final.log`、Mac `/tmp/flynes-nearby-harmony-host-ios-guest.log` |
| iOS 房主 → Harmony 客机 | v2 双方 1/1；同 ROM、600 帧、原始画面、PCM；v3 待复测 | `out/nearby-impl-timestamp-final-ios-host-harmony.log`、Mac `/tmp/flynes-nearby-timestamp-final-ios-host-harmony.log` |
| Android 房主 → iOS 客机 | v2 双方 1/1；同 ROM、600 帧、原始画面、PCM；v3 待复测 | `out/nearby-impl-final-android-host-ios.log`、Mac `/tmp/flynes-nearby-final-android-host-ios-guest.log` |
| iOS 房主 → Android 客机 | v2 双方 1/1；同 ROM、600 帧、GPU、AudioTrack、P2 输入；v3 待复测 | `out/nearby-impl-timestamp-final-ios-host-android-guest.log`、Mac `/tmp/flynes-nearby-timestamp-final-ios-host-android.log` |
| Harmony 完整 Hypium | 当前包 174/174 | `out/nearby-20260924-harmony-full-hypium.log` |

Android 全仓模拟器 instrumentation 曾以单一进程选择 197 项：运行到第 160 项时，约 192 MB 的测试进程 Java 堆耗尽。按类隔离复跑后，63 个可在当前 AVD 上执行的类共 193 项，初轮 188 通过、4 项因显式前提跳过、1 项扫码导航瞬间状态断言失败。扫码断言改为等待目标 Activity 进入 `RESUMED`，单独 5 轮全部 5/5；最终包 UI 集合 44 通过、1 项需要对端的用例跳过。四项跳过后来分别在双模拟器配对、隔离 AVD 的 2224 个合成游戏植入、及系统文件选择器授予 SAF 目录读取权限后执行并通过。目录扫描的 SAF 测试先红：原生扫描已标记 `INDEXED`，最新目录投影已有 1 包，返回值却在投影刷新前组装而缺包；修复后该测试 1/1、受影响 Android 回归 16 通过、1 项隔离植入用例跳过。见 `out/nearby-20260924-android-class-summary.log`、`out/nearby-20260924-disposable-catalog-seed.log`、`out/nearby-20260924-saf-diagnostic-test.log`、`out/nearby-20260924-saf-fixed-test.log`。

当前 Android AVD 的 SwiftShader 仅报告 OpenGL ES 3.0；4 项依赖 ES 3.1 计算／Motion Shadow 原生呈现的测试已执行并因 `EGL_CONTEXT_UNAVAILABLE` 或未生成原生帧失败，不能算模拟器通过，也不能用软件降级结果代替真机认证。全共享宿主树构建另在三个既有非附近测试目标遇到 MSVC `C4244/C4389` 警告当错误；附近目标单独构建并完成上表 14/14。见 `out/nearby-20260924-android-full-instrumentation.log`、`out/nearby-20260924-shared-host-build.log`。Android 测试后 Wi-Fi 已恢复，模拟器 UDP 重定向为空；隔离 AVD 留在忽略目录 `out/nearby-20260924-disposable-avd/` 以保留证据。

同平台补测使用两个独立 Android AVD、两个独立 Harmony 模拟器数据目录。Android 房主夹具原先只调用 `selectRom`，使新版 Android 客机无法从 `peerGameKey` 找到本地 ROM；第一次失败后改为 `selectGame(ROM, 身份)`，再补客机响应换游戏，最终双方通过。Android 隔离 AVD 已关闭并保留数据。Harmony 第二实例虽能安装同版 HAP，但其 Hypium 在非联机冒烟测试也会被系统以 `handleForegroundTimeout` 终止；数据副本、标准设备配置和 HDC 重启未排除此问题，不把该方向记为通过。原有鸿蒙实例此前完整 Hypium 174/174 的证据仍保留；后续重启该实例的隐藏窗口测试也出现同类前台超时，需在可交互模拟器环境复测。

跨 App 测试的邀请只在本地测试脚本内转交，未写入本记录。模拟器入站 UDP 隔离由测试专用 UDP/TCP 转发解决；转发脚本位于忽略目录 `out/`，产品协议和页面没有引入转发逻辑。Android 模拟器 UDP 重定向使用空闲端口并检查控制台返回；测试期间临时关闭 Wi-Fi，结束后恢复。Harmony 仿真器使用独立克隆数据，不覆盖原部署模拟器。

六方向跨 App 矩阵先在 v2 共享协议上完成；双暂停修复升级为 v3 后，Android↔Harmony 两个方向已按同版双包复跑。其余四个 iOS 参与的方向按用户安排留到下一轮，与新版包一并复测；v2 历史通过不充当 v3 验收。此前 Mac 原 SSH 地址 `<LAN_IP>` 无法连接，最后一轮 iOS 模拟器任务尚未完成。

iOS 旧桥接测试曾直接比较两端的“最新画面”，在预测执行时可能拿到不同核心帧号并报像素差异；一次等待相同当前帧号的尝试也因两端持续相差数帧而无法对齐。新的测试保存短窗口内每个原始画面及其核心帧号，只比较同一帧号；该版本尚未在 Mac 恢复后编译和执行。因此不把未对齐的失败推断为核心画面错误，也不将历史通过当成新断言通过。

## 尚未签收

六个跨平台方向均有**双应用**模拟器闭环，但除 Android→Harmony 的产品触控/房间完整路径外，其余方向的跨端测试以各端原生会话桥为入口；新版页面另有各端 UI 回归。模拟器的像素和 PCM 测试不能替代真实扬声器、显示刷新、触屏手感或热点连通性。需等用户接入真机后，按同设备单机对照测量本机端到端 P50/P95 增量 ≤5 ms、音频延迟增量 ≤5 ms、稳定速度偏差 ≤0.5%，每角色至少 200 次操作，及十分钟双人游玩。当前没有这些物理指标的通过结论。
