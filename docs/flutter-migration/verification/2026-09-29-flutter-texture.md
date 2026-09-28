# Flutter 游戏容器模拟器验证

日期：2026-09-29。REQ-007，`codex/flutter-foundation` 3.0.3 工作区，尚未独立提交。此记录持续追加，不能代替 G1 放行。

## Android external texture

调试入口为生产包内 `FlutterFoundationActivity`，extra `flutter_texture_probe=true`，单独引擎运行同一模块的 `textureProbeMain`。正常大厅引擎与默认原生入口不变。原生实验 owner 从 manifest 读取许可 ROM，独立核心不打开用户存档；复用 `AudioThread`、`NativeFrameSource`、`FrameDispatchExecutor`、`NativeVideoPresenter`。现有 EGL presenter 向 Flutter `SurfaceTextureEntry` 的 Surface 输出；像素、PCM、步进不经过 Dart。未切换媒体时钟或启用硬件限定模式。

页面仅持 texture ID、小型输入和 owner token。detach 停音频并等待帧派发结束，确认原生 surface 销毁后释放 texture；保留 host 的核心。host 销毁才关闭核心。新页面可在旧页面 dispose 前发起 attach，原生串行执行 surface 交接；旧 owner 的迟到释放/输入/前后台命令不影响新 owner。hostActive 与 pageActive 同时成立才推进核心。

设备：任务专用 Android API35/x86_64 `emulator-5582`，上游 Flutter3.41.7/Dart3.11.5，debug，同包 `com.flynes.emu`，均 `install -r`，无卸载或清数据。

首次真实运行证实画面和音频泵推进，但找不到 A 控件，instrumentation失败。读取实际 accessibility node 确认 label 重复为 `A\nA`，修正试验控件的重复语义后重跑。

`FoundationTextureIntegrationTest.nativeMediaSurvivesMultiTouchBackgroundAndTwentyTextureCycles` 实际 **1/1通过**，12.754秒：

- 核心采样双指 A+B 为3；取消/释放后依次2、0。
- 后台音频线程停止、输入清零，300ms内模拟时间不增加；前台继续推进。
- 20次释放/重新附着，核心始终保留，每次重新产生真实提交帧，runtimeFailures始终0。
- 第20轮 attaches21/detaches20，submittedFrames194，uploadedFrames194；`playedUs=8219510` 是成功音频泵推进量，**不是硬件播放头或端到端延迟**。
- 已人工查看初始与第20轮截图，均显示真实游戏内容，期间画面从标题进入模式菜单；不是纯色或 Flutter 占位图。

证据位于 `.artifacts/flutter-g0/android-foundation/`：`texture-instrumentation.log`（首次失败）、`texture-diagnostic.log`、`texture-green-build.log`、`texture-green.log`、`texture-cycles.log`、`foundation-texture-playing.png`、`foundation-texture-after-20.png`。

后续追加原生 owner 交接断言和AudioTrack播放头诊断，发现AudioThread启动前取消竞态；
确定性复现并最小修正后，完整Android17项回归中两个texture测试均通过。
测试直接读AudioTrack播放头，要求超过4800帧；仍不证明扬声器物理延迟或声音质量。
owner立即交接后旧owner输入/active/detach不影响新owner，宿主暂停始终阻止音频重启。
证据 `final-17-instrumentation.log`，音频RED及修复见[跨版本记录](2026-09-29-android-upgrade.md)。
模拟器不能证明物理延迟、温度或功耗。

## Dart 公共边界

封面：只读 native 提供的现有本地路径，保持图片比例，缺图/坏图回退本地化标题；generation区分同路径的新截图并回收旧缓存。真实PNG解码与覆盖同路径更新测试通过。

texture：双指cancel、前后台、20次附着/释放、旧页面attach迟到跨页面替换均有widget回归；读审发现的无owner迟到释放问题已实际RED→修正→GREEN，native交接实现另经读审。最新Dart测试28/28；最终format/analyze状态随后统一核验。

## Harmony

同一Dart实验页已完成真实texture Hypium4/4，含音频消费、双指、后台和20次附着释放，
见[Harmony容器记录](2026-09-29-harmony-texture.md)。宿主游戏页往返与后台组合另行回归，
不能由texture单项通过替代。
