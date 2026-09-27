# 附近联机三端界面一致性复核（2026-09-25）

依据已评审的 `docs/superpowers/specs/2026-09-23-nearby-three-platform-ux-design.md`，复核当前未提交工作区的原生页面。三端采用各自原生导航和控件，但应保持相同的信息顺序和操作：两个建联入口；左侧二维码、右侧网络和连接状态；建联后空房间；房主从游戏库选择；明确断开。

| 页面 | Android | HarmonyOS NEXT | iOS |
| --- | --- | --- | --- |
| 入口 | 顶部返回与标题、网络说明、左右两张角色卡；本次在 `emulator-5590` 截图复核 | 原页额外堆叠主标题、说明与方框字形，卡片缺乏角色层级；已改为网络说明加 P1/P2 双卡和明确的卡内操作，布局专项在 `127.0.0.1:5559` 通过 | 原页额外堆叠主标题、说明；已按同一信息顺序精简，Mac 横屏与大字体 UITest 通过 |
| 邀请 | 大幅正方形二维码位于左侧，标题、网络、状态和操作位于右侧；将原来实际断开会话的“取消”改为“断开” | 原页二维码固定 200vp、标题在左下、右侧大面积空白，且缺少重新生成；现按可用宽高计算二维码，加入白边，内容与操作移至右侧 | 原页缺少重新生成与断开；已加入两个明确操作，二维码补白边；Mac UITest 已验证生成、重新生成和断开 |
| 房间 | 左侧连接角色、右侧游戏，房主进现有游戏大厅选择；菜单可断开 | 已清除原始英文调试状态，左侧显示连接和座位，右侧游戏、匹配状态与房主选游戏；断开仍在顶栏 | 左右布局保留；补上房间顶栏断开和结束状态处理，清除 `READY/CONFIGURED` 调试字样并校正房主、座位、游戏文案。已连接时从游戏大厅重进附近联机将回到原房间，房间返回大厅保留会话；Mac 空房间注入态 UITest 已通过 |

鸿蒙邀请页布局测试先失败（二维码宽度未达到页面宽度 28%，`out/nearby-20260925-harmony-invite-red.log`），修改后通过（`out/nearby-20260925-harmony-invite-green.log`）。最终签名包和测试包已安装到专用模拟器 `127.0.0.1:5559`，宿主 CTest 15/15、全量 Hypium 176/176；两倍字号邀请页专项也通过。最终日志为 `out/nearby-20260925-harmony-ui-host-ctest.log`、`out/nearby-20260925-harmony-ui-final-focused.log`、`out/nearby-20260925-harmony-ui-final-full.log`。

鸿蒙截图保存在忽略目录：入口修改前后为 `out/nearby-20260925-harmony-entry-before.jpeg`、`out/nearby-20260925-harmony-entry-after.jpeg`；邀请页修改前后为 `out/nearby-20260925-harmony-invite-before.jpeg`、`out/nearby-20260925-harmony-invite-scale2.jpeg`。最后一张在 2 倍系统字号下拍摄，二维码、重新生成、断开均完整可见。

入口卡片补齐卡内操作后，Hypium 断言先失败于 `nearby_card_cta_create` 缺失（`out/nearby-20260925-harmony-entry-cta-red.log`），修改后专项 10/10 通过（`out/nearby-20260925-harmony-entry-cta-green.log`），最终全量 176/176 通过（`out/nearby-20260925-harmony-entry-cta-full.log`）。最终截图为 `out/nearby-20260925-harmony-entry-cta-final.png` 和两倍字号 `out/nearby-20260925-harmony-entry-cta-scale2.png`，与 Android 入口截图 `out/nearby-20260925-android-entry-review.png` 对照。

Android 邀请页截图 `out/nearby-20260925-android-invite-review.png` 暴露按钮文案仍为“取消”。Espresso 新断言先按预期失败（`out/nearby-20260925-android-invite-label-red.log`），后改为“断开”；修复后邀请页 6/6 通过，真机跨应用用例按条件跳过（`out/nearby-20260925-android-invite-label-green.log`）。最终截图 `out/nearby-20260925-android-invite-final.png` 确认二维码、状态和“断开”按钮均完整可见。

iOS 邀请页新增断言先失败（缺少两个按钮，Mac `/tmp/flynes-20260925-ui-review-red.log`），首次补齐后单项通过（Mac `/tmp/flynes-20260925-ui-review-green.log`）。之后补充了按钮点击及入口文案收敛。Mac 第一次组合测试中扫码页查询发生 XCTest 界面空闲超时（`/tmp/flynes-20260925-ui-consistency-tests.log`）。第二次定向测试有四项先通过，但创建邀请后 App 主线程持续约 100% CPU，XCTest 无法读取二维码（`/tmp/flynes-20260925-ui-final-tests.log`；采样 `/tmp/flynes-20260925-sample.txt` 指向 SwiftUI 布局更新）。将配对页退回已知通过的布局后扫码测试 1/1 通过；仅恢复配对页持有的上层导航回调便复现主线程满载。改用应用内连接事件触发大厅导航后，扫码入口、模拟器无相机提示、真实邀请二维码 3/3 通过（Mac `/tmp/flynes-experiment11-test.log`）。邀请二维码只在载荷变化时重新生成，配对状态轮询 250 毫秒。

Mac 全量 `FlyNESRuntimeTests` 在界面首轮修复后运行 56 项：54 通过、2 项无外部对端时按测试设计跳过、0 失败（`/tmp/flynes-20260925-runtime-full.log`）；两个外部对端方向已在本轮的双模拟器测试中分别通过。首次全量 `FlyNESUITests` 在 iPhone SE 横屏和系统大字体下运行 26 项，25 通过、1 失败（`/tmp/flynes-20260925-ui-full.log`）：设置页表单将“恢复推荐设置”放在屏幕外，原测试直接查询按钮未滚动。给按钮稳定标识并让测试滚动到操作后，定向用例 1/1 通过（`/tmp/flynes-20260925-controls-reset-focused.log`）；随后同一模拟器全量 `FlyNESUITests` 26/26 通过（`/tmp/flynes-20260925-ui-full-rerun.log`）。

只读代码复核又发现 iOS 实际房间路由用了独立 `UIHostingController`，会让房间内的选游戏与运行页面失去原导航栈；房主从邀请页返回后，角色页也未监听后来建立的连接。新增真实根路由测试先按预期失败（Mac `/tmp/flynes-20260925-lobby-route-red.log`）。房间已接回游戏大厅 `NavigationStack`，房主选游戏由根导航栈打开现有游戏库；角色页监测活跃会话，重新进入创建页不会重建已经连接的会话。模拟器还查出从选游戏页返回与断开都需避免在 SwiftUI 导航目标内直接替换父路径：前者由根路由处理，后者重建导航栈再回角色入口。最终两项定向路由测试 2/2 通过（Mac `/tmp/flynes-20260925-lobby-both.log`）。最终源码在 Mac iOS 模拟器上的全量 `FlyNESRuntimeTests` 执行 56 项：54 通过、2 项因缺少外部对端按设计跳过、0 失败（`/tmp/flynes-20260925-runtime-final-ui-route.log`）；这两个外部对端方向已在本轮双模拟器联测中分别通过。扩充后的全量 `FlyNESUITests` 28/28 通过、0 失败（`/tmp/flynes-20260925-ui-final-ui-route.log`），包括真实游戏库导航、连接后返回空房间、断开、大字体页面、导入流程以及七款内置游戏逐一启动与按键操作。后台脚本的 `BUILD_OK`、`RUNTIME_OK`、`FIXTURES_OK`、`UI_OK` 均已写入 `/tmp/flynes-20260925-mac-final-route-status.log`。本轮未把摄像头实际扫描、物理显示、扬声器、热点或真机延迟计为模拟器通过。
