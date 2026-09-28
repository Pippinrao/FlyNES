# FlyNES 跨端技术选型与公共手柄组件调研

> 最新决策：用户已选定 Flutter。本调研保留候选比较与资料依据；“不锁定框架”等文字反映决策前过程，不再是当前方向。统一架构和落地需求见 [Flutter 三端统一架构与重构落地路线](roadmap.md)。

日期：2026-09-28。代码基线：`main@78057350c12b`。状态：资料调研和架构建议，未做框架原型、设备测试或代码迁移。

关联：[分层架构方案](architecture-analysis.md)、任务 [评估 Flutter UX 迁移](codex://threads/01a0e860-0aee-7eb2-973d-16ef06ef6c3c)。

存档补充：任务 [修复通关后重新开始](codex://threads/01a0e85e-d42a-7360-b2d4-06e07971f3e5) 的独立存档历史库已纳入整体设计，详见分层方案第 13 节。读取时正在实现，最新顺序为 Android/鸿蒙优先、iOS 后续；不是已验收能力。所有候选共用该库及公共存档用例，不随框架重新选择一套存档系统。

## 1. 修订结论

不应现在锁定 Flutter。上一轮证明了“公共 UX＋公共应用服务”值得推进，但没有充分证明 Flutter 是 FlyNES 的最佳承载技术。本轮把应用框架和游戏引擎放在同一组产品需求下比较；此前 Flutter 的工作量估算只是该候选路线的估算，不能用作 Godot、Cocos 或团结的估算。

当前建议分开决定三件事：

1. **先确定框架无关架构。** 公共 C++ 产品/运行/输入服务、独立 Nearby、薄系统适配继续成立。
2. **公共手柄行为组件可以先抽取。** 既有三端也能立即复用，不必等 UI 框架定案。
3. **UI 承载技术通过门槛筛选后再选。** 应用框架重点看 Flutter、React Native＋RNOH、ArkUI-X；游戏引擎重点看 Cocos Creator、团结，Godot 先通过鸿蒙移植可维护性审查。Compose 鸿蒙分支、Qt 作为有条件备选。

如果后续只做两条完整原型，建议一条代表“保留原生游戏页的公共应用 UX”，另一条代表“统一游戏内外呈现的游戏引擎”。应用路线从 Flutter、RN/RNOH、ArkUI-X 中按团队经验、版本覆盖和插件证据筛选；引擎路线从 Cocos、团结中筛选，团结先核对许可条件。当前资料不足以提前指定最终代表或排名，也不建议同时启动全部框架的完整迁移原型。

## 2. FlyNES 的选型门槛

本项目是模拟器应用：已存在 C++ NES 核心、运行层、QUIC 联机与三端 GPU/音频链路。需要统一的是产品 UX、交互组件和行为，不需要新增物理引擎、3D 场景或重新实现 NES。

| 门槛 | 需要证明的结果 |
| --- | --- |
| 三端产品覆盖 | Android、iOS、HarmonyOS NEXT 的真实原生包；Android 兼容模式或 Web 演示不算 NEXT 接入 |
| 平台与版本可持续 | 明确上游、适配维护方、确切版本/提交、可重复工具链、升级路径和未实现功能；区分稳定版与开发分支 |
| 核心与存档复用 | 继续调用已有 `fly_*`/`nes_*` ABI 及独立 save_history 的 C ABI；不能为 UI 选择重写核心、Nearby 或存档历史库 |
| 媒体与输入正确 | 原始帧、连续 PCM、短按/多点触控、物理手柄、后台恢复；唯一模拟执行者，输出读取不推进核心 |
| 系统能力 | ROM 导入与持久授权、相机扫码、热点/网络绑定、设置跳转、覆盖安装保留数据 |
| 存档一致性 | 同一公共 SaveCoordinator 协调捕获/恢复，保留历史、保护点、head、格式身份和旧档；引擎序列化机制不替代模拟器快照 |
| 维护收益 | 不把三套 UI 成本转成长期自维护的引擎分支、三套插件和两套媒体循环 |
| 可分发 | 核对运行时、编辑器、插件、资产与当前 GPLv2 核心的实际许可组合；技术能链接不等于组合可发布 |

仓库当前 Android `minSdk 24`、Harmony API 20、iOS 部署目标 16.4 是比较基线。候选框架要求更高版本时，必须单列覆盖变化，不能在迁移中默默缩小支持范围。

证据级别统一为：上游/维护方正式文档、维护方适配仓、社区移植或提案、FlyNES 实测。前三者都不能代替第四者。本轮没有任何候选取得 FlyNES 实测资格。

## 3. 应用框架比较

| 候选 | 三端与鸿蒙支持事实 | C++/原生页面复用 | 主要维护成本 | 本轮判断 |
| --- | --- | --- | --- | --- |
| **Flutter＋Flutter-OH** | Android/iOS 上游支持；NEXT 走 CPF-Flutter 的独立适配发行 | C ABI 经 FFI；官方 add-to-app 支持 Android/iOS，鸿蒙混合接入另核验 | Dart/SDK 与 OH 适配版本、插件和原生游戏容器 | 应用路线短名单 |
| **React Native＋RNOH** | Android/iOS 主平台；OpenHarmony 在 RN 官方 From Partners 列表，属于 out-of-tree | C++ TurboModule、原生页面渐进接入；鸿蒙有额外注册/构建胶水 | RN/RNOH、JS/TS 运行时、Fabric/TurboModule 和插件配套 | 应用路线短名单 |
| **ArkUI-X** | 项目明确覆盖 HarmonyOS/OpenHarmony、Android、iOS；有 NEXT 规格与版本配套 | ArkTS/ArkUI 公共页面；Node-API、平台 Bridge、原生混排 | 跨端 API 子集、Android/iOS 平台桥、SDK 配套与最低系统版本 | 应用路线短名单 |
| **官方 Compose Multiplatform/KMP** | Android/iOS 在官方范围；官方 target 表没有 OHOS | Kotlin/Native 接 C ABI，iOS UIKit 混排 | 单用官方发行无法直接满足三端条件 | 不作为无分支的三端方案 |
| **ovCompose / Kuikly** | 腾讯维护的鸿蒙扩展路线；二者也不能与官方 CMP 混成一个产品 | OHOS target、HAR/原生库和 ArkUI 宿主接入 | 定制 Kotlin/Compose/Skiko 组合；Kuikly 自有包与功能差异 | 团队有相应经验时作为备用 |
| **Qt/QML** | Android/iOS 稳定支持；官方 Wiki 已记录 Qt 6.12 RC 的 HarmonyOS 包与部署，6.11 稳定支持表未列鸿蒙 | C++ 复用直接；Android 有 QtQuickView 渐进嵌入 | 鸿蒙新版本成熟度、模块许可、三端混合宿主与部署限制 | 保留观察，不以“完全不支持鸿蒙”排除 |

### 3.1 Flutter 的证据更新

本轮成功读取 [CPF-Flutter 维护方主页](https://gitcode.com/CPF-Flutter)：相关仓库已迁移至该组织，页面发布 Flutter OH 3.41.9 Release 信息，并建议鸿蒙使用适配产物、其他平台使用上游产物。由此可以确认存在维护中的适配发行；仍不能直接确定哪一版本/插件组合适用于 FlyNES。此前只依据旧 Gitee 页面且未成功打开新主页的证据不足已得到补充。

官方能力边界见 [平台列表](https://docs.flutter.dev/reference/supported-platforms)、[add-to-app](https://docs.flutter.dev/add-to-app)、[FFI](https://docs.flutter.dev/platform-integration/bind-native-code)。本项目适合复用公共 C ABI；逐帧 RGB/PCM 不应穿过 Dart 消息通道。Flutter 的优势是共用应用页面与交互，触控手柄仍需要公共输入契约。

### 3.2 RN 与 ArkUI-X 都不能省略

RN 官方 [out-of-tree 平台列表](https://reactnative.dev/docs/out-of-tree-platforms) 把 OpenHarmony 列为合作伙伴路线；[C++ 模块文档](https://reactnative.dev/docs/the-new-architecture/pure-cxx-modules) 提供现有核心的包装方向。这使其具备候选资格，但 Android/iOS 插件不自动具有鸿蒙实现。比较时核对当前 CPF-RN 的确切发行，不用旧仓库版本代表现状。

ArkUI-X 能利用仓库已有 ArkTS/ArkUI 经验，但不能默认现有鸿蒙页面零修改迁到另外两端。[6.0.2 发布说明](https://github.com/arkui-x/docs/blob/master/zh-cn/release-notes/ArkUI-X-v6.0.2-release.md) 列出的配套包括 HarmonyOS 6.0.2/API22、Android 8+、iOS 10+：相对本仓库 API20 和 Android API24，应核实可采用的历史/当前 SDK 与覆盖范围。Node-API 的实际可用接口见 [跨端 N-API 文档](https://github.com/arkui-x/docs/blob/master/zh-cn/application-dev/quick-start/ffi-napi-introduction.md)。

### 3.3 Compose 与 Qt 的保留条件

官方 [CMP 平台支持](https://kotlinlang.org/docs/multiplatform/supported-platforms.html) 与 [Kotlin/Native targets](https://kotlinlang.org/docs/native-target-support.html) 不提供鸿蒙目标。腾讯 [ovCompose 示例](https://github.com/Tencent-TDS/ovCompose-sample) 和 [KuiklyUI](https://github.com/Tencent-TDS/KuiklyUI) 是实际存在的补充路线，但引入它们意味着接纳相应工具链和兼容边界。FlyNES 已经使用 C++ 共享业务，新增 KMP 的收益主要在 UI，并不能再把“业务逻辑跨端”完整算一次收益。

Qt 不应因过去缺少鸿蒙而永久排除：[Qt 6.12 RC 鸿蒙指南](https://wiki.qt.io/Qt_for_HarmonyOS_development_with_6.12.0) 已给出 API23、安装器和部署路径；[6.11 支持表](https://doc.qt.io/qt-6/supported-platforms.html) 与 [鸿蒙限制](https://wiki.qt.io/Qt_for_HarmonyOS/platform_limitations) 则说明要分版本判断。当前本仓库的 API20 工具链、手机形态和既有媒体宿主仍需专项验证，不能把 RC 能构建视作迁移风险已经消除。

## 4. 游戏引擎比较

| 候选 | HarmonyOS NEXT 证据 | 核心/画面/声音接入 | 输入能力 | 本轮判断 |
| --- | --- | --- | --- | --- |
| **Godot** | 有 OpenHarmony 社区移植和上游支持提案；未核实到上游正式支持 | GDExtension 包装 C++；ImageTexture 可更新帧；AudioStreamGenerator 可推 PCM | Input/InputMap、TouchScreenButton；移动端和鸿蒙不能套用桌面后端保证 | 有条件候选，先验证鸿蒙分支和维护成本 |
| **Cocos Creator** | 官方 3.8.5 起提供 NEXT 发布；3.8.8 发布说明新增鸿蒙游戏控制器支持 | C++/JSB 原生接入、纹理更新；持续低延迟 PCM 注入需要单独确认 | 游戏触摸组件和游戏控制器 API，可接公共输入核心 | 游戏引擎路线重点候选 |
| **团结引擎** | 官方 OpenHarmony 模块、NEXT 打包/安装文档 | C linkage/PInvoke、C/C++ 源码及 `.so/.a` 插件；AudioClip 流式回调可接 PCM，NEXT 延迟需测 | 1.8 官方新增 OH 手柄按键、轴及设备插拔；具体设备能力需测 | 游戏引擎路线重点候选，先核对许可/发行条件 |
| **国际版 Unity** | 不把团结的 OH 模块当成国际版同版本支持承诺 | 可复用 C++ 的技术机制不等于三端发行一致 | 国际版输入包能力不能自动推导团结 OH 行为 | 不与团结合并评分或混用支持结论 |

### 4.1 Godot 值得评估，关键是鸿蒙承载成本

Godot 的统一场景、Control UI、主题、触摸和手柄机制适合“游戏库＋游戏内控制层”。既有 NestopiaUE 可经 [GDExtension](https://docs.godotengine.org/en/4.6/tutorials/scripting/gdextension/what_is_gdextension.html) 接入，不必改写。视频有 [ImageTexture.update](https://docs.godotengine.org/en/stable/classes/class_imagetexture.html)，音频有 [AudioStreamGeneratorPlayback](https://docs.godotengine.org/en/4.4/classes/class_audiostreamgeneratorplayback.html)。这些接口证明存在数据接入路径，不证明零拷贝、音频延迟或高刷新效果达标。

本轮核对 [上游 OpenHarmony 支持提案 #12734](https://github.com/godotengine/godot-proposals/issues/12734) 仍为开放提案，指向 [kdada/godot openharmony 分支](https://github.com/kdada/godot/tree/openharmony)。该分支版本文件为 4.4.1，分支最近提交查到 2025-08-07；这不是对全部 Godot 鸿蒙生态的穷尽调查，但不足以证明该具体路线持续跟随当前上游和 NEXT 工具链。

因此 Godot 的前置任务是证明可重复的 NEXT 构建、C++ 扩展装载、音频、触控/手柄和维护者升级路线。如果必须长期维护自有引擎 fork，节省三端页面维护的收益可能被抵消。不能仅因为它是开源游戏引擎，就把其端口成本计为零。

### 4.2 Cocos 是不能遗漏的候选

[官方 NEXT 发布文档](https://docs.cocos.com/creator/3.8/manual/zh/editor/publish/publish-openharmony.html) 明确从 3.8.5 开始支持，另记录 3.8.7 原生通信改进；[3.8.8 发布说明](https://www.cocos.com/creator-download) 列出鸿蒙游戏控制器支持。相较尚依赖社区端口的路径，这是更强的产品支持证据，仍需要在 FlyNES 实测。

原生 C++ 可通过 [JSB 绑定](https://docs.cocos.com/creator/3.8/manual/en/advanced-topics/jsb-manual-binding.html) 接入。TypeScript 层做页面/控件，帧执行、回滚和输入采样继续留 C++。是否把现有滤镜和 GPU presenter 迁到 Cocos，需要另算工程量；不能把“可显示一张 NES 纹理”等同于保留原渲染能力。

一个未决点是持续 PCM：`AudioSource.getPCMData` 的存在表示能读音频数据，并不证明可以满足模拟器流式低延迟播放。优先验证保留当前原生 AudioSink 的接线方式，再比较引擎音频方案；本轮不对延迟作猜测。[AudioSource API](https://docs.cocos.com/creator/3.8/api/zh/class/AudioSource)

### 4.3 团结引擎单独评估

团结有正式的 [OpenHarmony 环境与发布路径](https://docs.unity.cn/cn/tuanjiemanual/1.9/Manual/openharmony-sdksetup.html)，以及 [原生插件类型](https://docs.unity.cn/cn/tuanjiemanual/Manual/openharmony-native-plugins-introducing.html) 和 [C++ 插件构建说明](https://docs.unity.cn/cn/tuanjiemanual/Manual/openharmony-native-plugins-create.html)。可以继续使用 FlyNES 的 C ABI，不能将“游戏引擎迁移”理解为重写模拟内核。

手柄方面有直接的一手证据：[团结 1.8 更新说明](https://docs.unity.cn/cn/tuanjiemanual/Manual/WhatsNew1.8.html) 新增 OH 平台按键、轴事件和设备插拔监听。应继续验证当前发行版的 Input System 包版本、Gamepad 布局、两个设备区分、重连 ID、震动及实际硬件，不能因通用 Unity API 有一个方法就承诺所有能力在鸿蒙成立。

音频也有团结自身的 API 证据：[AudioClip.Create](https://docs.unity.cn/cn/tuanjiemanual/1.8/ScriptReference/AudioClip.Create.html) 在 `stream=true` 时通过 `PCMReaderCallback` 持续按块读取样本。因此可评估从公共 PCM 队列供数；NEXT 的缓冲、欠载、实际延迟及音频线程安全仍需验证。原生 DSP 插件的 NEXT 完整支持本轮未核实，不能把通用插件文档视作平台保证；保留现有 OHAudio 等后端也是候选接法。

系统集成有正式的 [C# 与 ArkTS 交互接口](https://docs.unity.cn/cn/tuanjiemanual/1.9/Manual/openharmony-csharp-ets-Interaction.html)，包含 UI 线程与引擎线程通信。文件导入、相机和热点仍需通过明确的平台适配实现，不会随引擎迁移自动具备。

它的潜在收益是把全屏游戏 UI、触控、控制器、动画和编辑工具收敛到同一套引擎工作流。相应代价是引入 C# 层、引擎资源/打包流水线、GC 与音频缓冲边界，以及现有 GPU 滤镜的适配。包体、启动、内存和功耗只作为必测指标，本轮没有数据证明它一定比其他方案差或好。

团结与国际 Unity 必须锁定各自编辑器、模块和包版本。不能用国际 Unity 的插件兼容表证明团结 OH 的可用性，也不应为了三端分别使用两个长期分叉的项目。

本项目一个前置核验点是许可：[仓库 COMPLIANCE](../COMPLIANCE.md) 当前记载自有代码/NestopiaUE 按 GPLv2 组合分发；[团结 2026-08-14 条款](https://unity.cn/tuanjie/legal/terms-of-service) 对可能使引擎受特定开源条件约束的软件组合设有限制。进入实施前应核对确切代码许可、链接/分发方式及可用授权；这里不据资料直接作兼容或不兼容的法律结论。也不能假定改用 `.so`、加一层接口或更换 UI 就自动解决该问题。

### 4.4 引擎不会自动替代模拟器运行层

无论选哪个引擎，都必须保留一个 C++ SessionRunner 作为唯一游戏步进者。不能用默认 60Hz 的 `Update`/物理帧回调直接代替 NES 当前 NTSC/PAL 的源时序，也不能让引擎与现有音频驱动各跑一套模拟循环。

引擎读取 OutputPublisher 的视频/音频，不参与附近同步的时间线判断。回滚期间仍只发布最终修正画面，已交付音频不重复；输入在公共层规范化后进入单机或联机。相机、热点、文件授权、后台中断及存档策略仍由前述公共用例和平台端口处理。

## 5. 公共手柄组件：建议先抽取，独立于 UI 选型

“手柄”至少包含四层，不能用一个第三方 joystick widget 代替全部：

| 层 | 职责 | 推荐归属 |
| --- | --- | --- |
| 虚拟手柄呈现 | 方向盘、A/B/Start/Select、布局编辑、按压反馈 | 选定 UI/引擎的公共组件；迁移期可有薄原生 renderer |
| 触控行为 | 命中、触点归属、方向锁定/迟滞、A+B、多指、短按、取消 | 框架无关 C++ 组件 |
| 物理设备接入 | 枚举、按键/轴、热插拔、设备能力、震动 | SDL/引擎输入后端或薄平台适配 |
| 游戏输入语义 | 来源合并、轴归一化、按键映射、座位、逐帧采样 | 公共 InputHub/SeatRouter，NES 编码归游戏适配 |

### 5.1 当前可直接复用的基础

- [ControlLayoutV2](../../shared/include/flynes/product/control_layout.hpp)：位置、缩放、透明度和布局持久化。
- [GamepadHitMap](../../shared/include/flynes/product/gamepad_hit_map.hpp)：安全区域、控件形状、命中、方向与死区计算，已有 host 测试。
- Android [DirectionSession](../../app/src/main/java/com/flynes/emu/input/DirectionSession.java) 和 [GamepadInputState](../../app/src/main/java/com/flynes/emu/input/GamepadInputState.java)：触点归属、方向手势与按钮持有状态。
- iOS [DirectionSession](../../ios/app/run/DirectionSession.hpp) 明确标注从 Android 状态逻辑移植；[FrameInputLatch](../../ios/app/run/FrameInputLatch.hpp) 另行处理短按采样。
- Harmony [GamepadOverlay](../../harmony/entry/src/main/ets/overlay/GamepadOverlay.ets) 也保存 directionId、facePointers 并处理拖动/取消。
- Android [GamepadView](../../app/src/main/java/com/flynes/emu/GamepadView.java) 已映射部分实体键，但沿 `Source.KEYBOARD` 合并，没有在此路径按设备实例区分。它证明已有基础接入，不能据此宣布完整多手柄支持。

第一批抽取应是触点所有权、方向手势、按钮来源记账、短按锁存和清键；保留已验证布局，不需要因换框架重做整套交互。

### 5.2 组件接口与数据流

```text
TouchSurfaceAdapter → PointerEvent → VirtualPadCore ─┐
HardwareAdapter     → DeviceEvent  → MappingProfile ├→ InputHub
KeyboardAdapter     → KeyEvent                     ┘    ↓
                                                SeatRouter
                                                    ↓
                                        FrameInput → 单机 / 联机

VirtualPadCore → ControlVisualState → UI/引擎绘制
FeedbackEvent → seat/device 映射 → 手机触感 / 实体手柄震动
```

建议组件包为 `shared/input/` 下的 `VirtualPadCore`、`InputHub`、`SeatRouter`、`InputSampler` 和 profile；对外 C ABI，便于 Dart FFI、JSB、PInvoke、JNI/N-API 调用。如果未来确有外部消费者，可再独立为库，不必为了此次抽取先创建独立仓库。

关键契约：

- 设备身份使用连接实例 ID＋generation，GUID/厂商型号仅作映射查找，不能当作当前连接的唯一 ID。
- 每个 pointer/source 分别持有按钮；触屏松开 A 不得清掉物理手柄仍按住的 A。
- 平台统一坐标/方向/安全区域转换，公共层使用同一坐标约定；绘制使用其输出的 `ControlVisualState`，不反向决定输入。
- 多点触控包含 down/move/up/cancel；方向盘触点不能被另一根手指抢占，方向键和 A/B 可以同时保持。
- 轴处理统一范围、死区与迟滞；相反方向、A/B 滑入滑出和短按保持使用显式规则。
- 屏幕回调只提交事件；实际帧采样负责消费短按。显示帧或重复帧读取不能提前清除锁存。
- 取消、失焦、拔出和换局释放相关来源；迟到事件按 generation 丢弃，不把正常抬手延迟规则用于取消。
- 暂停菜单是 AppCommand，NES Start 是游戏按键；不能混成一个逻辑键。
- 物理输入设备→本地玩家→游戏座位明确映射，主客角色与设备无直接绑定。
- 联机传输规范化的逐帧输入，不传 pointer 坐标、OS keycode 或设备对象；远端输入直接进入同步历史，不重新走本机触控路由。
- 如未来增加连发，在公共映射/采样规则中定义，回滚重演消费已经确定的帧输入，不依赖当前 UI 定时器。
- 反馈输出独立处理，区分手机触感和实体手柄 rumble；NES 本身没有标准震动输出，不能虚构能力。

公共组件不意味着平台零代码：原始事件采集和绘制宿主仍需适配，但三端不再各实现一份手势状态机。

## 6. 可引入的开源组件及边界

| 候选 | 能复用什么 | 不能替代什么 | 建议 |
| --- | --- | --- | --- |
| **SDL3 Gamepad** | 设备实例、标准按钮/轴、热插拔与反馈 API | 完整触屏控件、座位/联机策略；鸿蒙后端也有未完成项 | 硬件后端候选，不作三端即插即用承诺 |
| **SDL Virtual Joystick** | 软件注入的虚拟设备，适合测试/回放 | 可见的屏幕手柄与多指 UI | 仅按测试/适配需求引入 |
| **SDL_GameControllerDB** | 平台/GUID 对应的按钮、轴、hat 映射数据库 | 设备读取、热插拔、触控、P1/P2 | 合适的数据层复用对象；匹配所选后端格式 |
| **Godot Input＋TouchScreenButton** | 引擎内动作系统、多点触屏按钮与手柄 API | 脱离 Godot 的三端原生控件库；NES 采样和回滚语义 | 选择 Godot 后复用；不只为按钮引入引擎 |
| **Flame Joystick/HudButton** | Flutter/Flame 摇杆、按钮和 pointer 事件设施 | 完整模拟器手柄、硬件驱动、座位与输入合并 | 选 Flutter 后评估，优先按需使用 |
| **flutter_joystick** | 可配置摇杆 widget | 完整 NES 控件和逐帧采样 | 不原样采用默认时序；可参考组件能力 |
| **RetroArch overlay 规范/资产** | 归一化布局、hitbox、组合键、图像和预设表达 | 平台输入驱动、会话状态、现有三端组件替换 | 借鉴规范/按许可复用资产，无需改成 libretro 核心接口 |

### 6.1 SDL 的鸿蒙缺口是实质性条件

官方 [SDL3 平台列表](https://wiki.libsdl.org/SDL3/README-platforms) 已列鸿蒙；[鸿蒙 README](https://wiki.libsdl.org/SDL3/README-harmonyos) 给出 ArkTS/N-API→C++ 的移植路径和设备记录，但 `STILL TODO` 包括 Joystick、HIDAPI、Haptic。

这不能扩展成“鸿蒙没有任何键值输入”，但足以否定“引入 SDL 就解决三端物理手柄和震动”。还应确认这些文档对应哪一实际发行/tag，不能把主干刚具备的平台能力自动算进所选稳定版。若某端仍使用原生硬件适配，应保持同一 InputDeviceAdapter 契约，避免为用 SDL 强行重写已有音视频。

[SDL_JoystickID](https://wiki.libsdl.org/SDL3/SDL_JoystickID) 和 [Gamepad API](https://wiki.libsdl.org/SDL3/CategoryGamepad) 可提供模型参考；[虚拟 joystick](https://wiki.libsdl.org/SDL3/SDL_AttachVirtualJoystick) 是注入设备，名称中的 virtual 不表示屏幕上会自动出现手柄。

### 6.2 映射数据库和触屏控件分开复用

[SDL_GameControllerDB](https://github.com/mdqinc/SDL_GameControllerDB) 是数据集，可帮助减少设备映射工作。采用前核对 SDL2/SDL3 或其他解析器的实际格式、平台标签与 GUID 生成方式；不直接把 SDL GUID 假定为 Android device ID 或 iOS controller ID。

Godot [TouchScreenButton](https://docs.godotengine.org/en/stable/classes/class_touchscreenbutton.html) 支持多点同时按下，适合作为引擎内触屏基础；[控制器文档](https://docs.godotengine.org/en/stable/tutorials/inputs/controllers_gamepads_joysticks.html) 的桌面 SDL 后端说明不能外推到移动端/鸿蒙。

Flame 的 [Joystick/HudButton](https://docs.flame-engine.org/latest/flame/inputs/other_inputs.html) 和 [drag cancel/pointerId](https://docs.flame-engine.org/latest/flame/inputs/drag_events.html) 能提供基础事件，但来源合并、NES 短按和玩家绑定仍由公共层负责。[flutter_joystick](https://pub.dev/packages/flutter_joystick) 文档的默认回调 period 为 100ms，不适合直接作为 NES 的输入采样时钟；调低参数也不能代替短按和取消语义验证。

### 6.3 RetroArch 值得参考，但代码与资产不是同一种许可

[Overlay 规范](https://docs.libretro.com/development/retroarch/input/overlay/) 的配置能力比一个通用摇杆 widget 更贴近模拟器。可将其作为扩展现有 ControlLayout 的参考，不必为了屏幕手柄引入整个 RetroArch 或更换核心 ABI。

[RetroArch 本体](https://github.com/libretro/RetroArch) 声明 GPLv3；[common-overlays/COPYING](https://github.com/libretro/common-overlays/blob/master/COPYING) 当前根许可为 CC-BY-4.0。直接复制程序实现与使用某个有明确来源的美术/配置资产是两件事，必须按具体文件核对。仓库当前按 GPLv2 描述，不能直接把 GPLv3 输入代码复制进来且仍沿用原许可声明。

### 6.4 许可证核验范围

可复用候选的主许可证据：SDL [zlib](https://github.com/libsdl-org/SDL/blob/main/LICENSE.txt)，GameControllerDB [zlib](https://github.com/mdqinc/SDL_GameControllerDB/blob/master/LICENSE)，Godot [MIT](https://godotengine.org/license/)，Flame [MIT](https://github.com/flame-engine/flame/blob/main/LICENSE)，flutter_joystick [MIT](https://pub.dev/packages/flutter_joystick/license)。Cocos [engine v3.8.8](https://api.github.com/repos/cocos/cocos-engine/license?ref=v3.8.8) 为 MIT，不以此替代编辑器及所有插件的条款检查。

应用框架同样要核验：Flutter [BSD-3-Clause](https://github.com/flutter/flutter/blob/master/LICENSE)，RN [MIT](https://github.com/react/react-native/blob/main/LICENSE)，CMP [Apache-2.0](https://github.com/JetBrains/compose-multiplatform/blob/master/LICENSE.txt)，ArkUI-X [Android 适配仓许可](https://github.com/arkui-x/arkui_for_android/blob/master/LICENSE)，Qt [模块与开源义务](https://www.qt.io/development/open-source-lgpl-obligations)。这些是具体仓库/模块的事实，不构成对全部 SDK 及 FlyNES 组合分发的统一许可结论。

## 7. 如何决策，而不是凭功能列表定框架

先做资料门禁：锁版本与维护方、核对平台覆盖、排除许可阻塞、列出硬件/系统缺口。通过后保留两条代表路线做同一组 PoC；Godot 先补鸿蒙端口证据，团结先核验许可和发行条件。此处只定义验证，不授权本次实施原型。

| 共用 PoC 场景 | 必须记录的证据 |
| --- | --- |
| 真实游戏库→打开 ROM→游戏→返回 | 同一公共应用状态、用户数据与文件授权保留、原生往返/场景切换无重复会话 |
| 虚拟手柄＋实体手柄 | 方向+A+B、滑动、短按、取消、拔出重连、双设备区分、不同来源同时按住 |
| 画面与持续 PCM | 持续运行、帧节奏、音频欠载与缓冲、后台恢复、滤镜能力保留；不用一张静态纹理替代 |
| 扫码与真实房间 | 实际相机权限、连接取消、同 ROM、双方输入、暂停/继续、同连接换游戏 |
| 构建/覆盖安装/升级 | 三端锁定工具链和依赖，安装身份/签名相容，存档和设置不丢 |
| 修改一个公共交互 | 观察需要改多少共享/平台代码、测试维护量及是否出现另一套业务逻辑 |

比较对象为相同设备上的现有原生版本与候选 release/profile 构建。记录输入采集→采样→发布/显示、音频 underrun、帧节奏、冷启动、内存、包体与所需平台桥接量。沿用现有延迟及设备资格门槛，其余阈值在 PoC 开始前结合基线定义，不在看到结果后调整标准。

框架的 InputMap、Input System 或动作绑定都只是输入来源/映射工具；每个候选必须通过同一 VirtualPadCore/InputHub 契约，不允许用不同输入规则换取表面性能结果。测试手柄体验时用真实设备，虚拟 joystick 只用于补充可重复用例。

存档也采用共同验收：真实运行→手动/自动保存→继续推进→恢复旧点并保持暂停→重开→退出重进，验证 head 指向选定分支或新局且旧历史仍可读；覆盖保护点失败、提交失败、旧档迁移与场景销毁后的迟到回调。引擎场景切换、Flutter Widget 销毁或 RN 页面卸载都不能直接关闭存档句柄或跳过公共恢复状态机。以上是后续候选 PoC 要求，不表示本轮已经实现。

SQLite、状态 BLOB 与 schema 继续是独立库内部实现。Unity/团结的序列化或第三方 Unity 存档插件、Godot Resource、Flutter/RN 持久化插件只因框架可用，不构成替换该库的理由；页面只通过公共用例读取列表/预览、发送保存/恢复/重开命令。库不依赖具体引擎，也不与 Nearby 同步快照合并。

迁移预算在上述结果后重估：公共底层、手柄组件和独立存档库各只计一次，各候选分别计算 UI、系统桥、媒体接入、工具链升级及回归；存档另计公共编排收敛与尚缺平台接入，扣除关联任务已交付部分。现有 Flutter 的 40–60 人日不适用于引擎路线，也不能说明最便宜；本轮没有给其他方案编造同精度估算。

## 8. 建议的下一步顺序

1. 评审并固定框架无关的公共输入/输出、应用状态、Nearby 和存档契约；对既有三端输入差异建立共用测试用例，并接续关联存档任务的实际产物与验收记录。
2. 独立抽取公共手柄行为组件，复用现有 ControlLayout/GamepadHitMap；三端 renderer 可以暂留。
3. 按本报告完成候选版本/许可/平台门禁，选择应用路线与游戏引擎路线各一个原型。候选状态是“待验证”，不是“已决定迁移”。
4. 用相同实际游戏、手柄和生命周期流程比较，再确定迁移范围与预算。

当前可以确定的是共享架构与手柄组件方向；尚不能确定最终 UI/引擎赢家。团结已经单独纳入正式候选，Godot 也已评估其可行路径和鸿蒙限制，Flutter 不再作为默认结论。

本次仅新增/修订架构调研文档，没有引入任何第三方依赖、复制组件代码/资产、修改产品源码、版本、构建或发布配置，也没有运行产品测试。

## 9. 按低成本、视觉效果与 AI 自动化偏好调整优先级

用户进一步明确关注“成本最低、界面好看、AI 友好、尽量无需人工点击和测试”。在这一权重下，建议优先验证 **Flutter＋公共 C++＋薄平台媒体/系统适配**，Cocos 为引擎路线对照，团结在许可条件明确后保留。这里是基于工作流的工程判断，不是已经测得 Flutter 迁移成本最低，也不代表鸿蒙自动化已通过。

推荐 Flutter 的理由是页面、布局、主题和交互主要用 Dart 源码表达，便于 AI 通过可审查 diff 修改；官方具有统一的 [命令行工具](https://docs.flutter.dev/reference/flutter-cli)、[组件/集成测试体系](https://docs.flutter.dev/testing/overview) 和 [golden 图像比较](https://api.flutter.dev/flutter/flutter_test/matchesGoldenFile.html)。游戏库、设置、房间及存档时间线可使用同一设计系统；好看取决于设计、资源和验证，不是换框架自动获得。

成本需分开判断：只抽公共业务而保留三端 UI，近期投入通常较小但继续承担三份界面维护；Flutter 渐进迁移是本次偏好下优先验证的成本控制路线；Cocos/团结统一游戏内外界面可能减少长期分叉，但现有媒体接入和工具链转换投入仍需测量。没有统一范围的原型数据，不给出精确成本排名或节省比例。

其他候选也有自动化能力：[Cocos 命令行发布](https://docs.cocos.com/creator/3.8/manual/zh/editor/publish/publish-in-command-line.html)、[团结 batchmode](https://docs.unity.cn/cn/tuanjiemanual/Manual/EditorCommandLineArguments.html)、[ArkUI-X CLI](https://github.com/arkui-x/cli)。不能将引擎描述为必须人工拖拽或不能 CI；不过 Cocos 文档明确命令行仍需 GUI 环境。GUI 运行环境不等于需要人点击，仍需在执行机上配置和验证。引擎场景、资源引用与编辑器版本会增加自动生成/修改资产的约束；本项目以代码驱动 UI 时，Flutter 的工作流更直接。

后续首个验证应优先挑战鸿蒙这一薄弱项：固定 Flutter-OH 发行及工具链，从干净环境自动构建/安装，执行真实页面操作并收集机器可判定结果；证明相同页面代码可在 Android/iOS 跑同范围测试。上游 Flutter 的测试能力不能直接视作 OH 适配版保证，插件和系统 UI 还需平台测试工具接续。若这条闭环不能稳定运行，不启动大规模页面迁移，再比较 Cocos 与 ArkUI-X 的同等闭环成本。

自动化目标为：代码修改→静态检查/公共 C++ 测试→组件与截图回归→三端构建安装→保存/恢复/重开/联机 UI 流程→汇总日志、截图及失败原因。多指、真实核心状态与事务失败断言要单列，不能用截图正常或构建成功替代。截图基线应在受控字体、尺寸和渲染环境下比较，不能让 AI 自动接受所有新图来消除失败。

“不用人工日常点回归”可以作为目标；“任何阶段都不需要人或真实硬件”不能作为框架承诺。iOS 构建/模拟器需要可用 Mac，设备连接/信任、签名授权和首次权限环境可能需要一次性准备；物理手柄、端到端延迟、音频听感及功耗等仍需实际设备证据，部分可以自动采集，不能用软件输入注入或模拟器冒充。整体自动化能力是本仓库要交付的工程工作，不是框架默认替项目完成的功能。
