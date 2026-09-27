# 三端联机一致性补齐与模拟器验证

依据：用户要求三端功能同步、确保 iOS 一致并完成模拟器测试；沿用已批准的三端 UX 和房间暂停恢复设计。工作在 main，补齐现有行为，不增加产品范围。

技术：Swift/SwiftUI、Objective-C++、AVFoundation、ArkTS、共享 C++ 会话。

## 验收清单与执行顺序

1. 扫码实际链路：NearbyPairingView 使用 NearbyQRScanner，串行启动停止，退出后旧授权/识别回调无效。对 NearbyScanLifecycle 的退出、重试和迟到回调先做失败回归，再接入页面；模拟器检查真实生产接线与相机不可用状态。
2. 连接状态：NearbyScannedJoinFlow / NearbyScannedJoinAdapters / NearbyPairingView 区分请求接受与连接完成。CONNECTING 时离开或重试必须取消，已连接进入房间保留会话。以可控原生状态回归覆盖取消和迟到完成；页面只在真实连接状态导航。
3. 扫码反馈：区分无效码、网络不可用、过期和一般连接错误；错误后由用户重试；较矮横屏仍可见热点说明。修改双语 Localizable.strings 并用 UI 断言可见性。
4. 换游戏：FlyNesNearbyBridge 的同步等待改为状态推进；CatalogLibraryView 展示等待并在主线程回调；取消/断开后旧请求不能配置新 session。先以原生会话测试验证异步返回、同连接换游戏、取消过期请求，再修桥接和调用方。
5. 标题与诊断：iOS/Harmony 客机标题复用本端游戏大厅语言策略；iOS 注册共享会话诊断输出，敏感邀请数据不写日志。增加针对语言回退、诊断注册的有效回归。
6. 房间 UI 回归：覆盖有游戏/本地截图、暂停继续、房主换游戏权限、选游戏页收到对方继续；尽量走真实原生会话而非硬编码 UI 状态。
7. 构建与验证：同步 Mac 后 touch 源文件，重新构建 FlyNES/FlyNESRuntimeTests/FlyNESUITests，再由 ios/scripts/run_simulator_tests.py 执行相关套件。运行共享 host 回归、Android 单元与受影响 UI、Harmony host/Hypium及连接设备替换安装。保留数据，不使用卸载或清数据绕过失败。
8. 审查、记录、提交：修复审查问题；docs/verification 写明红绿证据、运行的测试及真机边界。安装版本钩子，提交通过的代码与文档，不提交 out 证据、包、签名、私有 ROM。

## 判定边界

模拟器证明本次运行的功能与回归用例；不证明真实扫码、触控、扬声器、热点系统交互或硬件性能。已有 rollback_capture 偶发内部错误继续单列为未定根因，不能因共享实现或后续通过而销项。
