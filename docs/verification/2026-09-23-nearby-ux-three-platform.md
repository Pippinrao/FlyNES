# 附近联机三端 UX：2026-09-23 验证记录

本轮按[评审通过的设计](../superpowers/specs/2026-09-23-nearby-three-platform-ux-design.md)改三端原生界面与既有会话接口调用。`core/` 和 `shared/` 没有改动。三端入口均展示建房与扫码；旧好友管理、蓝牙发现和配对码界面已移除。Android 与 iOS 扫码直接打开相机；鸿蒙从入口直接调用 Scan Kit。普通退出页面保留现有会话，明确断开或会话结束才回入口；Android 的房间换游戏沿用原会话对象。

| 检查 | 本轮结果 |
|---|---|
| Android host unit | `:app:testDebugUnitTest` 成功；网络选择测试覆盖局域网优先和热点回退 |
| Android instrumentation | 入口、导航、横屏、房间等 19 项通过；配对页 5 项通过，包含真实二维码与本机原生客机接入 |
| Android 横屏 | 640/736/844 宽，中英双语及 1.0/1.3/2.0 字体倍率的固定页面无裁切和应用内滚动；三张实际页面截图保存在忽略的 `build/nearby-*-android.png` |
| HarmonyOS host CTest | 14/14 通过 |
| HarmonyOS HAP | 应用和 ohosTest 两个 HAP 构建成功 |
| iOS 模拟器 XCTest | `NearbyUxRestorationTests` 6/6、相关 `ProductUITests` 4/4 通过 |
| HarmonyOS 模拟器 Hypium | **未运行**：Pura 70 Pro 模拟器启动成功，但无签名 HAP 安装报 `install sign info inconsistent`；当前构建只生成 unsigned HAP，仓库 `signingConfigs` 为空。需要本机调试签名配置后安装测试包。尝试保留数据卸载后仍无法安装；已将仓库内原有签名的 1.0.0 侧载包重新安装，恢复模拟器原应用。 |

现有联机后端实际支持 Android 房主到 HarmonyOS 客机。Android 客机、鸿蒙房主和 iOS 双角色缺少平台接线；界面保留正式入口并显示真实不可用状态，不能据此称三端全组合已可玩。Android 本地专用热点已在邀请页接入系统 API，并保留到会话结束；本轮未取得第二台设备连接该热点的实测证据。双方断开回入口、同一连接连续换游戏的真实双机验收仍需在可安装的双端设备上完成。
