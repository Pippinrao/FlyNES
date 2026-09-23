# Nearby 扫码局域网与热点加入后端验证（2026-09-23）

本增量只提供三端后端入口：解析普通 LAN 邀请与热点凭据二维码；热点加入成功且取得可用
IPv4 后，再将内层邀请交给既有联机会话。未接前端页面，未实现自动发现或自动建热点，
现有好友页未删除或修改，待新版 UX 决定。

## TDD 与当前验证

- Android：新增解析、扫码解码、加入顺序/取消、网络租约单测，先观察缺少服务类的
  编译失败，再补最小实现。`app:testDebugUnitTest` 与 `app:assembleDebug` 通过。
- HarmonyOS：新增二维码协议、Wi-Fi 候选配置和扫码加入服务测试。服务测试先因缺少
  类编译失败，补类后 `ohosTest` HAP 编译通过；产品 HAP 编译通过；多网卡客机优先
  wlan 的 C++ 测试先红后绿，host CTest 15/15。普通无效 QR 现在先由 ArkTS 校验，
  不会让 native join 先重置既有会话；取消后可重试、旧监控回调隔离及热点转普通
  LAN 时释放候选配置的 Hypium 断言仅编译，尚未在设备运行。
  这个结果不是 Hypium 在设备上运行通过：本地没有可安装的签名测试包。
- iOS：新增协议、扫码加入顺序/取消、Wi-Fi 就绪、相机状态、网络租约终态和地址选择测试，
  已观察缺少实现的失败并在补齐后通过。Mac 模拟器产品构建通过；五组独立后端
  测试均通过（后续增至七组）。指定热点加入绑定 Wi-Fi 接口；取消/失败/会话结束
  会清理本应用的 joinOnce 配置；停止扫码会拒绝迟到的相机回调。相关 bridge 的
  模拟器 runtime 定向测试 1/1 通过。模拟器未执行实际热点关联或相机取景。

## 待真机验证

合入主干后的增量核验：Android `:app:testDebugUnitTest :app:assembleDebug` 通过；
HarmonyOS host CTest 15/15、产品与 `ohosTest` HAP 编译通过（均未签名，未在设备运行 Hypium）。
iOS 与新版主干 UX 合并后的 Mac 构建尚未复跑：本次 Mac SSH 主机不可达；上面的
iOS 通过记录仅属于功能分支的合并前版本，不能替代主干构建证据。

三端系统 Wi-Fi 加入确认、热点下的地址/链路行为、相机二维码识读，以及三端各自
担任房主和客机的真实跨设备游戏路径。这些尚不能凭 ABI、模拟器、mock 或编译
结果宣称完成。iOS 的 HotspotConfiguration/Wi-Fi Information 真机授权与签名、
HarmonyOS 的 Wi-Fi 权限及候选配置安装运行也尚未验证。
