# 9 月 27 日真机联机、房间与扫码记录

基线提交 `206d1fc`（1.11.1），本轮继续在 consolidated main 上实现用户批准的房间与扫码修正。测试证据保存在 ignored 的 `out/device-20260927/`，不提交录像、私有 ROM、签名或安装包。

## 设备与结论边界

- Android：vivo V2324A，Android 16；HarmonyOS NEXT：HBN-AL80。两台真机经现有路由器 LAN 联机。
- iOS：Mac 上独立源码目录的 iPhone SE 模拟器；没有 iOS 真机证据。
- 用户实际试玩后最后明确确认 **两台都有声音**。之前鸿蒙媒体音量为 0 的观察不作为当前静音缺陷。
- Android 屏幕录像 599.894 秒、环境麦克风录音 480.088 秒已结束。Android 内录抽样静音，不能把该文件作为内部音频成功证据；环境录音也不能单独证明两台扬声器。鸿蒙系统录像由用户停止，尚未导出。
- 没有热点、刷新率、温度、功耗或物理触控延迟签收结果；没有启用硬件资格模式。

## 房间实现与验证

按 [批准的设计](../superpowers/specs/2026-09-27-nearby-room-resume-design.md)：P1/P2 玩家列、当前游戏及本地已有截图卡片、继续与房主更换游戏。返回房间保留原核心、帧号、游戏与会话；明确继续解除双方暂停。选游戏页收到对方继续时返回游戏，实际新选择才结束旧局。

共享 Continue 使用双向确认，排空先前暂停消息；新的暂停请求仍被保留。配置兼容指纹升级为 `v4-resume-ack`，旧版不能与新版混合开局。

| 检查 | 证据与结果 |
|---|---|
| 旧回房间行为回归 | `room-ui-red.log` 在保留 RUNNING 断言失败；修复后通过 |
| 选游戏页响应对方继续 | `room-picker-red.log` 缺少游戏暂停按钮；`room-picker-green.log` 1/1 通过 |
| 交叉暂停消息竞态 | `resume-barrier-red.log` 确定性双 FIFO 测试失败；`resume-barrier-green.log` 协议与真实会话播放 2/2 通过 |
| 共享 LAN 回归 | `room-shared-regression.log` 14/14 通过；最终 v4 与捕获诊断版本 `room-final-host-tests.log` 13/13 通过 |
| Android 单元 | `scanner-decode-green.log`，117 类，571 项，0 失败、2 跳过 |
| Android UI | `room-final-android-ui.log` 8/8；包含短横屏、中文/英文、1/1.3/2 字号、扫码状态及恢复游戏 |
| Harmony 宿主 | `room-final-harmony-host-tests.log` 15/15 |
| Harmony 真机 UI | `room-harmony-ux-green.log` 10/10；签名替换安装成功，使用文档约定的本地测试签名 |
| iOS | `room-ios-ui.log` 14/14，runtime 3/3；继续确认及选游戏页修正后 `room-ios-final-runtime.log` 3/3、`room-ios-final-ui.log` 6/6 |
| Android 房主 → Harmony 客机 | `room-final-two-device-result.log`：两台真实 App 的输入、帧、PCM 消费、暂停、回房间继续和同会话换游戏通过 |
| Harmony 房主 → Android 客机 | 修正夹具前台启动后，两台真实 App 的 600 帧播放、图像与 PCM 断言连续四次通过：`reverse-pass1-{harmony,android}.log`、`reverse-repeat-{2,3,4}*.log`。另有下面记录的未解决偶发失败，不能据此宣称稳定性全部通过 |

### 尚未签收的补测

- 反向联机曾在第 234 帧发生一次 `rollback_capture` 内部错误，`reverse-v4-harmony-runtime.log` 保留现场。已增加 core 返回值、缓冲区大小与重试次数日志；后续四次通过，但没有复现并确定根因，不能标为修复。
- 随后的房间 UI 补测在 20 秒内仅播放 489 帧，客机测试超时主动断开（`room-ui-timeout-*.log`）；该轮不能作为 60fps 或稳定性合格证据。
- 新增 `checkRoomResume` 专项在鸿蒙 180 帧、安卓 120 帧后检查真实房间暂停、游戏名称、截图和恢复；默认播放用例仍要求 600 帧。复跑时鸿蒙自动锁屏，专项仍待解锁后完成。此前 Android 房主的双机房间恢复用例通过不替代该反向界面专项。
- 最后一次诊断审查补充“本次 core 调用是否返回”，避免异常路径误用上一帧记录。审查后 `room-reviewed-host-tests.log` 协议/播放 2/2、`room-ios-reviewed-runtime.log` runtime 3/3、Android 单元 571 项（2 跳过）均无失败，Android 与 Harmony 主包/测试包构建成功。

## 扫码迟缓

用户连续对焦修复后仍报告十几秒才识别，仍属于未签收项。Android HAL 确认为连续对焦，默认预览 2560×1440。原扫描器在主线程新建通用条码解码器，空场景每帧约 70–87ms；这本身不能解释十几秒识别，也不证明入房网络耗时。

新增经过生产解码器的 NV21 亮度帧测试：真实邀请长度的小密 QR，11 个垂直采样偏移 × 4 个旋转。原策略漏识别；专用、复用的 QR 解码器与 TRY_HARDER 后 44 组全部通过。单工作线程解码、相机代次检查丢弃过期结果，Camera 操作仍在所属线程。真机空场景每帧约 25–27ms，尚需同距离/光线的真实扫码结果。

调试包记录对焦、每次抽样解码耗时/候选点数量、识别完成和入房耗时到应用缓存 `scanner-timing.log`，不存相机帧、二维码内容或凭证。`scanner-timing-baseline.log` 与 `scanner-timing-after.log` 为本机导出证据。等待用户拿手机的时间不能计入识别耗时。

## 三端一致性核对

| 项目 | Android | HarmonyOS NEXT | iOS |
|---|---|---|---|
| 配对入口 | 创建／扫码 | 创建／扫码 | 创建／扫码 |
| 扫码页 | 恢复左相机、右状态操作；比例保真、安全区 | 使用系统 Scan Kit 相机扩展，系统页面外观不同 | 内嵌原生相机；模拟器只验证不可用状态 |
| 识别后的连接 | 留在扫码页等真实连接；无效/网络/过期分别反馈 | 原生服务轮询 | 原生服务轮询 |
| 空房间与选游戏 | 只有房主可选 | 只有房主可选 | 只有房主可选 |
| 当前游戏、截图、继续 | 本机封面仓库 | 本机 CoverStore | 本机 GameCoverModel |
| 真机证据 | 已连接、播放、操作、用户确认声音 | 已连接、播放、操作、用户确认声音 | 未接真机 |

系统相机扩展不等于自绘扫描页像素一致。Harmony 扫码取消后的失败呈现、无 LAN 时热点引导以及 Android 扫码速度仍需单独验收；不能把构建和模拟器成功概括为三端真机全部完成。
