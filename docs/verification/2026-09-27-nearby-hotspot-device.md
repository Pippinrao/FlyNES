# Android / Harmony 热点真机验证（2026-09-27）

## 环境与当前结论

用户重新接入 Android vivo V2324A 与 Harmony HBN-AL80，要求验证热点路径。基线为 `0e68c11`（1.11.4）；两台均覆盖安装当前调试包，保留应用数据。Android 原本同时连接两个路由器 WLAN 接口，Harmony 连接同一路由器。

Android 自动热点方向已实际完成扫码配网、入房、双方原生游戏运行、双向按键、暂停恢复和同连接换游戏。Harmony 手动热点方向也已扫码入房并进入双人游戏，用户明确确认本轮两端声音和操作正常。反向测试时 Harmony 同时保留路由器 WLAN，因此该方向尚不能签收为纯离线热点。

## 真机发现与修复

### 1. Android 热点二维码漏带配网信息

- 关闭 Android WLAN，应用请求附近设备权限后创建本地专用热点，邀请页显示系统提供的热点信息。
- 系统路由只有 `ap0` 的热点网段；同时关闭 Android 移动数据，防止将联网能力误当作热点通路。
- Harmony 真实相机扫码后仍处于原路由器网段，原生连接约五秒后超时。
- 根因：实际邀请页直接渲染原生 `flynes-lan-v1`，没有调用既有 Wi-Fi 邀请封装；三端已有的配网解析未被触发。
- 修复：邀请页使用会话持有的热点信息生成 `flynes-wifi-v1`，再渲染同一个二维码。未持有热点信息时保留普通 LAN 邀请。
- 回归直接解码产品页面生成的 QR bitmap，检查网络信息和内层原生邀请；模拟器仅替代系统提供的热点元数据，不模拟产品 QR 渲染或原生邀请。

### 2. Harmony 页面轮询提前释放正在配网的候选

- 修正后的 Android 真机截图能够解码出 Wi-Fi 邀请；用户再次扫码仍未入房，Harmony 未离开原路由器网络。
- 页面每 250 ms 轮询共享服务。等待系统 Wi-Fi 确认时，原生会话仍处于 IDLE 或上一轮 ENDED，服务据此释放刚创建的 Wi-Fi 候选。
- 增加 deferred 配网回归，模拟等待系统响应时的页面轮询；修复前断言候选不应被释放失败。
- 修复：扫码/配网请求进行中，不用旧原生状态清理网络；显式取消仍由原有取消路径处理。
- 增加仅含阶段和数值错误码的诊断，不记录 SSID、口令、邀请内容或系统错误全文。

复审另外补齐两个相关边界：Android 选择路由器 LAN 时关闭旧自动热点，避免二维码把 LAN 地址和旧热点信息混在一起；Harmony 取消 A 后开始 B，A 晚返回不得再次释放 B 的网络。两者均先以回归复现，再修复。生成 bitmap 的现有 QR 测试偶发 `ChecksumException`，改用同文件其他用例已使用的 `PURE_BARCODE` 解码选项，保留原始 payload 断言；真实相机识别另由真机扫码验证。

## 软件回归证据

日志位于忽略目录 `out/device-20260927/`，含网络配置的原始证据不提交、不打印凭据。

| 检查 | 结果 | 日志 |
|---|---|---|
| Android 实际 QR 回归（修复前） | 1 项失败，缺少 Wi-Fi 封装 | `hotspot-qr-red.log` |
| Android QR、扫码、邀请页（最终修复后） | 9 通过，1 外部对端用例按条件跳过 | `hotspot-final-android-ui.log` |
| Android 单元与调试包构建 | 通过 | `hotspot-final-android-build.log` |
| Harmony 待确认网络期间的页面轮询（修复前） | 6 项中 1 项失败，发生提前释放 | `hotspot-harmony-poll-red.log` |
| Harmony 配网、扫码流和服务（最终修复后） | 19/19 通过 | `hotspot-final-harmony-flow.log` |
| LAN 重建 / 取消 A 后开始 B 的边界回归 | 修复前分别 1 项失败，最终通过 | `hotspot-network-red.log`、`hotspot-cancel-red.log` |
| Harmony host CTest | 15/15 通过 | `hotspot-harmony-host.log` |
| Harmony 构建与签名真机覆盖安装 | 通过；本地测试签名 | `hotspot-harmony-build.log`、`hotspot-harmony-test-build.log` 及安装命令输出 |

Android 厂商安装器的首次 ADB 同版本覆盖请求曾返回取消，最终 `--no-streaming -r` 覆盖成功；通过读取已安装 `base.apk` 的 SHA-256 与本地构建包一致确认代码已更新。Harmony 隔离模拟器最初因主包仍为 1.11.3 拒绝 1.11.4 测试包，升级主包后重新安装测试包；只采纳新版失败复现及最终 19 项修复回归，未把旧包结果算作修复证据。

## Android 自动热点 → Harmony 客机

- Android 移动数据关闭，路由只剩 `<LAN_IP>/24 dev ap0 src <LAN_IP>`；Harmony 从原路由器转到 `<LAN_IP>`。热点信息来自系统 reservation，没有手填或伪造配网成功。
- 22:03:35.929 请求系统确认，22:03:40 左右网络就绪；原生加入用时约 58 ms。用户回复“可以了”。系统另提示该 WLAN 没有互联网，选择“使用”后继续游戏。
- 22:04:59 两端进入 RUNNING；选择《倾斜兄弟》的本地双人模式，P2 设为 HUMAN。保留两端实际画面和 `input_apply` 的 P1/P2 非零输入及释放日志。期间 USB 调试短暂断开，ADB 重连后恢复；热点游戏连接持续运行。
- 22:09:47 客机暂停，22:10:05 返回房间，22:10:17 客机继续。期间主机帧号 17287、客机帧号 17286 保持不变，继续后主机推进至 18301；页面展示当前游戏和继续操作。帧计数是各端异步日志采样，不用相差一帧推导物理延迟。
- 22:11:22 房主通过正常游戏大厅改选《双子龙》，保持原生会话（日志序列/owner 连续），两端重新进入 RUNNING 并超过 600 帧。
- 主机明确断开并完成后续覆盖安装后，确认 `ap0` 路由消失；这条证据不单独证明资源在断开按钮点击时立即释放。
- 证据：`hotspot-round3-harmony.log`、`hotspot-playing-*.log`、`hotspot-paused-harmony.log`、`hotspot-resume-*.log`、`hotspot-switch-*.log`、`hotspot-android-after-disconnect-route.txt`。

## Harmony 手动热点 → Android 客机

- 用户手动开启 Harmony 热点并让 Android 连接。Android 仅有 `<LAN_IP>/24 dev wlan0 src <LAN_IP>`，移动数据仍关闭；Harmony 热点接口为 `<LAN_IP>`，另保留路由器 WLAN `<LAN_IP>`。
- 应用按 LAN 优先规则使用 Harmony 的 `<LAN_IP>:48554`。Android 经已连接的热点成功加入，22:17:51.818 进入 LOBBY，原生加入约 51 ms；用户确认“扫描了，进去了”。这证明当前热点连接可用，不等同于关闭 Harmony 上游 WLAN 后仍可建房。
- 22:22:36 两端进入 RUNNING，通过产品游戏大厅选择《倾斜兄弟》，本地双人模式将 P2 设置为 HUMAN。真实屏幕显示双人对战，双方原生日志记录 P1/P2 按键及释放。用户明确回复“两端声音和操作都正常”。
- 安卓客机回房间后，双方帧号保持在 9581/9583；22:26:19 继续后帧推进，但 22:26:21 鸿蒙在第 9690 帧 `rollback_capture` 失败并断开。诊断为四次重试后仍 `NES_ERR_BUFFER_TOO_SMALL`（capacity=4261、needed=4262）。因此反向暂停恢复不计通过。
- 共享层新增连续微小增长的序列化回归，修复前明确失败；改为容量不足时按至少两倍扩容，保留四次上限与实际写入长度校验，host runtime 回归通过。这修复精确容量反复追赶导致失败的路径；序列化长度波动本身的底层原因仍未确定，真机复测尚未完成。用户随后要求优先验证新接入的 iOS 真机。
- 证据：`hotspot-reverse-host*.log`、`hotspot-reverse-guest*.log`、`hotspot-reverse-android-route.txt`、`hotspot-reverse-human.jpeg`、`hotspot-reverse-stage.jpeg`。

## 验收边界与收尾

- Harmony 房主关闭上游 WLAN/移动数据后的纯离线热点仍未验证；本轮按用户要求保留现有热点连接。
- 结束后恢复 Android 测试前的 WLAN 和移动数据状态。
- 用户随后接入 iOS 真机并要求优先测试。已使用原签名身份覆盖安装 1.11.4，未卸载、清数据；初次安装后 35 个 Documents/Preferences 文件（含 28 个存档）哈希不变，用户确认旧游戏与进度正常。
- iOS 扫描 Harmony 邀请成功；首次连接超时，用户开启系统本地网络权限后重新扫码，于 22:43:02 进入房间（原生加入约 214 ms）。随后发现并修复内置游戏 ID 映射差异，真机已经加载游戏并收到客机输入；详见 [iOS 真机与游戏库记录](2026-09-27-nearby-ios-device.md)，完整双人试玩仍待验收。
- 诊断包再次覆盖安装后，28 个存档哈希仍一致、无文件缺失。游戏目录 live 文件仅 generation 从 43 增至 44，正文条目及用户记录不变、校验和有效；备份轮换到 generation 43。诊断日志区分游戏条目匹配、ROM 读取和原生配置失败，待真实连接复现。
- 当前 iOS 本地测试签名未包含 HotspotConfiguration / Wi-Fi information entitlement；尚未验收 iOS 热点系统交互，不能以 LAN 入房结果代替。
