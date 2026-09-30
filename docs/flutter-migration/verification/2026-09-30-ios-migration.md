# iOS G0/G1/G2 恢复实施记录

## 范围与当前状态

2026-09-30 用户恢复 iOS G0/G1/G2，并在 macOS 版本阻塞后要求评估 Flutter 降级。工作树 `codex/flutter-foundation`，实施起点 `bb7d709e5d9611bda20050ec4acf17d06b3cdac2`，当前未提交版本 `3.0.8`。**正在实施，尚未整体验收**。

沿用共享 Dart 产品页面和 U01～U26／A01～A17。生产包 `com.flynes.app`、目录、来源书签、布局和 `Documents/saves/<safe canonical ID>/autosave.nst` 保持兼容；REQ-020 历史库迁移不提前纳入。

## 工具链降级及隔离

实际 Mac：Intel x86_64、macOS 13.7.8、Xcode 14.3.1（14E300c）、iOS 16.4 模拟器。设备已恢复交流供电，原生编译使用单并行任务。

- Flutter 3.41.7 macOS SDK SHA-256 `a0b9af49e6e1a6800f31a408b98c1d7bd51e98650a8b9ebcd77168b48c916ff0` 与官方清单及 Mac 再校验一致。但 Dart 实际启动报 `Current Mac OS X version 13.0 is lower than minimum supported version 14.0`。
- iOS 兼容 SDK Flutter **3.38.10 / Dart 3.10.9** 已实际启动。SDK SHA-256 `b7056ba00082b9b814415e7516287bb94633c1108838bfe10f8f665307b99afa`；framework revision `c6f67dede3d4aa1aa7a69dd56a3494a5cde6cc80`；engine `cafcda5721a78a7884db92f13c5e89f7643d52dd`。
- 共享 Dart API 可兼容；另为旧 SDK 修正两处无障碍节点合并，给搜索框与开关明确独立语义容器。SDK 下限改为 `^3.10.9`；Android 仍为 3.41.7，Harmony SDK 不变。iOS 用独立锁 `tools/flutter/locks/ios-3.38.10.lock` 和忽略目录中的生成模块；构建不会改写其他平台 `.dart_tool` 或依赖锁。
- `tools/flutter/Build-Ios.sh` 检查完整 SDK 身份，复制同一份 Dart 源码并用 `pub get --enforce-lockfile`；固定 Debug XCFramework 构建已成功。生产脚本默认启用 Flutter；只有显式 `FLYNES_NATIVE_BASELINE=1` 才编译旧原生对照，不提供失败时隐式回退。
- simulator slice 使用 Debug Flutter 运行时；Release 文件夹名称不能认证 AOT。切片选择器还检查 simulator 的 `kernel_blob.bin`，缺资源即拒绝。iphoneos Release 与模拟器功能／成本分别报告。

Mac 任务导出：`~/Developer/flynes-flutter-foundation-bb7d709e`。SDK／日志：`~/Developer/flynes-flutter-tools`。原生 Debug 对照已保存到任务导出的 `.artifacts/ios-g2/native-baseline/FlyNES.app`，未覆盖其他 Mac 工作目录。

## 已运行验证

| 验证 | 实际结果与证据 |
| --- | --- |
| 构建切片选择器 | 6/6，业务 RED→GREEN；`.artifacts/ios-g2/framework-selection-{red,green}.log`、`framework-assets-{red,green}.log` |
| 产品服务首轮 | 7 项先因服务缺失业务断言失败，最小实现后 7/7；`product-service-red.log`、Mac `service-tests.log` |
| 首帧握手 | 实际 `frameNumber` 被旧 `rasterFrame` 校验拒绝，2 条断言 RED；修正后 8/8，`service-handshake-red.log`、`service-green.log` |
| 来源及旧档保留 | 真实隔离导入／去重／移除、所有者销毁重建、书签重新扫描、收藏／设置／布局及真实 checkpoint 恢复通过；属于所有者重建，不冒充操作系统覆盖安装 |
| 宿主租约 | 新增关闭后旧请求和迟到 native completion 共 4 条预期 RED；`deactivateContext` 与回调代次修正后 12/12，Mac `service-lease-{red,green}.log` |
| Dart 兼容 | Mac 3.38.10 analyze 无问题，192/192；Windows 3.41.7 format/analyze/192/192 同样通过，`candidate-tests.log`、`upstream-regression.log` |
| XCFramework／生产宿主 | Debug XCFramework 及 Xcode 生产宿主编译成功。第一次启动实际复现 `engine.run` 前注册 handler 导致 NSException；顺序修正后普通启动 1/1 |
| 首轮真实 UI | 4 项中普通启动、系统文件选择取消通过；设置布局与暂停设置失败证据保留。旧 SDK 在清空 `engine.viewController` 后会销毁无障碍桥；改为保留关联、用 UIKit 生命周期隐藏/显示同一 View 后，设置/布局及同局 20 次暂停设置往返 2/2 通过（`ui-return-03.log`） |
| 实际核心计数 | `RuntimeOwnerDiagnosticsTests` 先因计数接口缺失 RED，补实际 runtime 创建/销毁原子计数后 1/1；不再以控制器是否存在代替核心数量 |
| 两组实际所有者循环 | `roundtrip-actual-owners.log` 2/2，323.060 秒：20 次同局暂停设置保持 nonce/加载次数/暂停帧不变；20 次大厅↔游戏创建不同单局、在后台仍暂停、回大厅核心实际归零，单引擎和活动 View 数量均符合预期。xcresult `tests-20260930-220615` |
| 旧 SDK 无障碍 | 固定字体下复现 4 个节点边界断言失败；明确语义容器后 6/6，含 100%/200% 与伪本地化。Windows 原 SDK 严格比较 199 静态图、81 动画帧全部通过，未更改金标或容差 |
| iOS 语言字号矩阵 | 英/中 × 默认字号/系统 AX XL 四组合真实 XCTest 1/1，36 张截图及语义树。AX XL 实际为 40/17≈235%，不标为精确 200%。审阅发现一张来源页处于动画中间帧，以及下滚控件证据不足，正在补采，不能把采集测试通过等同视觉门禁通过 |
| 稳定补采与布局翻译 | 增加超过产品路由 220ms 的稳定等待，补来源/操作/许可下滚及取消确认。矩阵、布局往返、选择器取消 3/3（`stable-matrix-02.log`，xcresult `tests-20260930-221459`），52 张矩阵图+10 单项图和对应语义树；独立打开 22 张针对性补图后关闭这些审阅问题。动态 `LocalizedStringKey` 先拼普通 String，实际 UI 原始 `control.*` 键断言 6→0。AX 大厅标题缩略仍如实记为可读性限制 |
| U08 共享返回修正 | 两项业务 RED 后最小修正，Mac/Windows 两 SDK 全套 194/194；另补键盘三步回归 3/3。Windows 当前完整视觉 199 静态+81 动画严格通过；只批准更新一项 U08 金标，详情见下节 |
| 附近原生 UI 接续 | 首次 4 项中 3 项失败；诊断发现关闭事件已收到但旧游戏控制器未卸载。沿用原生 `NavigationPath` 无动画原子替换后 3/4；补宿主观察选游戏期间的对端 Continue 后 4/4，200.103 秒（`nearby-flutter-green.log`，xcresult `tests-20260930-223626`）。独立审阅另发现对端断开退出 picker 的遗漏，继续补 RED；同进程真实 peer 不等于双 App 通过 |
| 受影响原生回归 | 产品服务、实际所有者计数、runtime／音频／手柄、目录导入及封面共 57/57（`ios-affected-runtime.log`，xcresult `tests-20260930-223952`）。未把无关或依赖外部配对文件的测试计入 |
| 选游戏期间断开 | peer-only 断开保留 app owner，双方原生 state=4 后 UI 仍留 Flutter 的业务断言实际 RED。宿主观察既有断开状态并撤租约、恢复原生入口，清 picker 状态；完整 5/5，249.562 秒（`nearby-disconnect-{red,green}.log`，xcresult `tests-20260930-224800`），含从恢复入口实际创建/取消房间。没有用双边 cleanup 伪造远端断开 |
| iphoneos Release | 固定 SDK Release XCFramework 与完整 unsigned arm64 原生宿主均 `BUILD SUCCEEDED`（`pinned-framework-release.log`、`device-release-build.log`）；不是签名安装或真机性能证据，最终修订工件仍需重建 |
| 视觉候选采集 | 199 场景断言通过，产生 199 静态图和 81 动画帧。跨 Mac/Windows、跨 SDK 直接比较只有 54/280 像素／几何通过、267/280 语义相等；该对照仅用于兼容性审阅，不是同平台金标验收，不放宽阈值 |

所有本地证据在忽略目录 `.artifacts/ios-g2/`。Mac 原始 XCTest 结果在 `build/ios-simulator/evidence/*.xcresult`。一次错误测试过滤器执行 0 项，不计通过；随后使用正确完整用例名称重跑。

普通大厅真实截图已打开审阅。XCTest `app.screenshot` 在当前 iOS16.4 横屏发生裁剪错位；窗口／控件边界实际为 667×375，按钮可点击。改用 `XCUIScreen.mainScreen.screenshot` 后得到完整 1334×750 图，不修改产品布局来适配错误截图。截图保留语义树及可点击边界断言。

稳定补采的 62 张页面图及 3 张附近通过路径图已全部逐张独立打开并核对语义树（`real-ios-visual-review.md`）。这是人工审阅，不代替同环境像素复测；235% AX 大厅省略和英文按钮换行的可读性限制保留。新增共享键盘返回用例后 Windows 完整 Dart 为 195/195，Mac 同一新增三步返回用例 3/3。

## 当前实现

`FlyNesProductService` 使用既有目录／设置／来源所有者，公共产品投影、串行字段更新、旧单槽真实能力、系统选择器及许可白名单。扫描不支持取消时如实投影不可取消，不伪造百分比。

`FlutterProductHost` 单引擎／单活动 Flutter View，保留原生游戏、布局和附近页面；暂停设置复用同一局，原生返回用宿主 token＋真实 frameNumber 握手移除短期交接图。页面关闭撤销租约，不释放核心／连接所有者。默认应用入口已接 Flutter，旧原生入口仅供明确对照测试。

## 剩余门禁

1. 共享 FIFO 与 iOS 触控边沿修正后的真实双 App 双角色复测及擂台／房间截图审阅。旧实现的偶然通过不能替代修复后证据。
2. 含最终修正的原生／Flutter 对照重建、精确源码指纹／版本／包哈希冻结及任务模拟器安装。
3. iOS 成本采集与适用口径：当前 SDK 的模拟器只运行 Debug；iphoneos Release 构建不等于真机性能。交互就绪、Release 内存、可验证 GC 等缺失指标明确未测，不能用 simctl 返回时间或 macOS RSS 替代。

目录/ZIP/失效重新授权及真实扫描阻塞期间离页/返回已通过并补齐可见状态截图；两组 20 次往返、追加 20 次原生布局循环、媒体回归、两语言／字号截图及 280 张共享静态／动画严格比较已经闭环，详见下述证据。原生 VoiceOver 焦点／朗读不由截图或语义树自动认证。

## U08 返回房间金标修订

附近选择上下文原来只有“附近联机”入口，缺少取消返回现有房间的可见动作。新增两项 Dart 业务断言均失败后，在同一工具栏位置改为返回箭头与“Return to room／返回房间”；按钮和系统返回均调用现有 `closeHost`，不新建房间、不关闭连接。另补非零键盘 insets 的三步返回断言，键盘→搜索→房间 3/3 通过。正常单机入口不变。

独立审阅者 `ios_g2_contract_audit` 实际打开 `head-nearby` 的 actual/expected/diff，确认只有原 48×48 控件内图标及对应语义变化。42 个状态中其他 41 个严格相同；该项像素差比例 0.00030478395，几何偏差为 0。仅更新其 PNG、语义文本与 review 元数据，不修改几何、其他金标或容差；依据是已批准 U08 的取消回原房间要求，重比 42/42 通过。本地报告为 `.artifacts/ios-g2/nearby-state-{diff,reviewed}/report.json`。

## 原生 → Flutter 保留数据覆盖安装

隔离任务模拟器 `FlyNES-Flutter-G2-20260930`（iPhone 14 / iOS16.4，`2A1BB7C1-79A2-466D-9C87-A1C23F7F7E2A`）。先安装冻结的原生 3.0.8 对照，应用二进制 SHA-256 为 `d981f8371a799a9857460ea21439ab86a32140b95ce86d4de1b8aee30aea9a8c`。通过系统 Files 导入仅含仓库许可 ROM 派生的 Single 夹具，再实际收藏、启动/保存、关闭音频并保存布局：`ProductImportUITests/testSeedNativeToFlutterUpgradeThroughRealPicker` 1/1，99.848 秒（`tests-20260930-225719`）。Files 位置标题首次被测试误当导航栏标识而失败，改用实际 StaticText 后准备步骤 1/1；没有用应用数据注入代替系统选择。

原生退出后记录目录/备份、设置、布局、旧 `autosave.nst`、完整 preferences 共 6 个文件的 SHA-256，以及两项来源 metadata/bookmark 域的摘要。相同包身份覆盖安装 Flutter 3.0.8 后，在首次启动前比较全部相等（`native-before-upgrade{,-covering-install}.json`、`upgrade-retention.log`）。之后 `FlutterUpgradeUITests` 1/1，31.319 秒（`tests-20260930-230006`）：收藏条目/继续可用、来源仍显示、声音仍关闭、实际读取原授权 ROM 并进入旧档恢复路径，回大厅仍为继续。

这是原生 3.0.8 → Flutter 3.0.8 的兼容覆盖验证；此前 iOS G1 延期，不能称为已有旧版 iOS G1 发包的跨版本升级，也不包含尚未迁入 iOS 的 history head/pending。未卸载、清数据或重新导入规避失败。后续来源测试已实际导入 200 文件／100 canonical、搜索别名并启动游戏；两项夹具定位问题正在修正，不能将该批写成完整通过。

## 来源测试失败与隔离夹具恢复（独立于覆盖安装）

覆盖安装通过之后，实际 Files 来源批次因旧容器路径缓存、合并后的卡片标题和单文件选择自动结束等测试假设失败，保留 `tests-20260930-230144`。期间用于恢复测试自建 Hundred 来源的旧几何定位错误点到了相邻的 Single 移除按钮，移除了该测试来源登记；原始 ROM 和旧存档仍在。这是测试夹具错误，不能把后续重新登记当成“升级原 UUID 一直保留”。已通过真实系统选择器恢复 Single 登记，新 UUID 为 `688B0146-D748-4346-905A-B2E4DE94787A`；原覆盖安装阶段 UUID 为 `20794F5E-6724-4561-8EA9-E2A34F55B11D`。原生覆盖的 6 文件/2 域相等及随后恢复游戏的证据发生在这次测试错误之前，单独保留。

删除操作现改为来源 UUID 对应的 `source-remove-<uuid>` 无障碍标识；彻底移除按屏幕行位置猜测目标的方法。英文/中文相邻来源先失败、后验证语义点击及确认回调确实使用对应 UUID；来源及动效相关 54/54，Windows 全套 197/197，38 张来源截图像素/几何差均为 0、原语义事实一致。标识合并到按钮既有语义节点，不改变标签、48px 目标或金标。Mac 旧 SDK 来源测试 29/29（中间实现），最终最小实现继续进行原生回归。

定向恢复仅在忽略目录的显式 ownership manifest 匹配失败批次 Hundred UUID 时运行，检查 Single 登记及原存档字节保留，不做全局清理。`tests-20260930-231909` 已找到正确 UUID 按钮，但点击未打开确认框，继续按截图/语义排查；不能记为来源完整通过。后续来源验收以恢复后的夹具基线说明，与原始覆盖安装记录分列。


后续定向恢复 `tests-20260930-233236` 1/1，50.179 秒（`source-stable-recovery.log`）：精确 UUID 移除成功，Single 登记及所有既有 checkpoint 字节相同。此前最终语义实现已能打开对话框，但测试立即读取 preferences 的旧磁盘视图失败；cfprefsd 后续实际已写入正确结果。另一次完整来源批次在滑动后单击被滚动吸收，取消/重复单文件项通过，Hundred 项失败（`tests-20260930-232723`）。测试现要求目标位置连续稳定后仅点击一次，且在有限时间内等待准确持久状态；不重试业务点击、不放宽保留断言。完整来源两项继续复跑。最终共享代码的格式/analyze/197 项测试均通过，日志 `source-final-upstream-full.log`。


完整真实来源回归最终 **2/2，298.914 秒**（`flutter-real-sources-stable.log`，`tests-20260930-233333`）。取消系统选择、同文件重复导入保留 UUID；200 个文件归并到 100 canonical、Game/Alias 搜索同卡；移除取消零状态变化、确认只删除自建 Hundred 来源；原 Single 收藏/继续、源书签及所有旧 autosave 字节保留，重启再检查通过。此批基于前述恢复后的测试登记，不覆盖此前误定位记录。

## 独立审阅后的定向修正

- 暂停→Flutter 设置改为中文→返回旧暂停抽屉，实际复现四条本地化断言失败，当前局 nonce、ROM 加载次数及暂停帧保持相同（`pause-language-red.log`，`tests-20260930-234251`）。先刷新既有按钮后关闭三项，标题因 Flutter 使用 `game:SHA`、原生 manifest 查找只接受 `builtin:` 而仍失败；继续采用启动时的不可变标题字段，不在返回时同步重查目录。
- `scanFileRecords` 的 owner 锁覆盖文件协调读取；主线程 `settingsGet/controlLayoutGet` 会等待整次扫描。受控夹具在真实协调读取处阻塞 1.5 秒，主线程读设置耗时 **1.695646 秒**，业务 RED（`settings-read-red.log`）。现由同一个串行所有者在创建、设置/布局/最近游玩写入成功后发布不可变只读投影，生命周期读只拿短投影锁；写入成功后才 ack，不增加数据库或第二权威。完整 ProductServiceTests **13/13**，4.536 秒（`settings-read-green.log`，`tests-20260930-234837`），含阻塞扫描时读取必须小于 0.5 秒及最新 autosave OFF 值保留。

双 App 运行时首次编排因 XCTest 启动宿主时数据容器换 UUID，等待旧目录下邀请而超时；此批失败保留。编排现每次重新解析当前容器，测试所有权邀请仅归档到该失败批次的忽略目录，不清应用数据。不能把该编排问题当作连接协议已通过。

## 2026-10-01 接续验证

双 App 运行时两种角色分配均已实际通过：`two-ios-peers-forward-02.log` / `two-ios-peers-reverse-02.log`，对应本地 `two-ios-peers-{forward,reverse}-report.json`。两个独立应用进程、同一许可 ROM、各 600 帧、双方非零输入、PCM 和 RGB565 数据断言成立；编排工具 7/7。该证据仍不代替两个产品 UI 完整操作闭环。之前同进程 peer 的五项 UI 与此次双进程 runtime 分列。

最终标题字段接线后的受影响原生回归分两批执行：产品服务/owner/来源/标题封面 39/39（`tests-20261001-000058`），runtime/音频/手柄 19/19（`tests-20261001-000141`），共 58/58。第一批有三个过滤类名错误，未执行的项目没有计入；随后用实际 XCTest 类名补齐 19 项。

同环境矩阵重采 `stable-matrix-03.log` 3/3、351.246 秒，62 张实际截图及语义树；SDK、系统镜像、设备和八个系统字体哈希一致。完整报告严格比较为 59/62 通过：系统 Files 文件夹图标未就绪（0.6123% 超差，Image 标识不同），另有中文常规字号的操作页末端及其确认框背景两图失败。早先只读了截断输出而误报 61/62，现更正。完整打开后发现后两项为滚动停点相差 1.3 逻辑点；原参考英文常规图同样未到准确末端，不能放宽 1 点几何门槛。系统图标增加有界就绪等待后 1/1 通过并与原图严格一致；操作页改为断言末行准确停在 16 点留白处，再重新审阅该四张常规字号夹具图，不改变产品或比较容差。

截图比较器新增真实 XCTest PNG 的 EXIF 横屏方向用例，先 RED 后 16/16 GREEN。只按 EXIF 做无损方向转换，不缩放、不重采样；原始图片保留，几何仍按 XCTest 逻辑点比较。工具不会因自比或缺环境而宣称视觉门禁通过。

旧 Mac 候选的 199 静态场景与 81 动画帧已逐张打开独立审阅，另两张封面夹具也记录 SHA-256 与结论（`candidate-all-images-review.{json,md}`）。没有新的阻塞性布局缺陷；滚动区域可达性、原生 VoiceOver、四项后续语义修正和 U08 返回修正单列。这是旧候选审阅，不把它批准为当前金标。

投影锁修正已独立审阅：没有发现新锁序或确认值一致性缺陷。首次初始化/重建缺缓存、布局保存和 markPlayed 等写入口仍可能等待 owner，不宣称所有主线程工作都已非阻塞。

暂停语言修正最终通过：`final-pause-roundtrips.log` 2/2、148.784 秒（`tests-20261001-000225`），包含英文→中文→英文的既有抽屉按钮和真实目录标题刷新，以及 20 次暂停设置往返；nonce、加载次数、暂停帧、实际核心/引擎/View 数量均保持要求。启动投影携带不可变 `titleFields`，兼容 `game:SHA`，不在主线程重查目录。五张附件已逐张打开，英中暂停画面的左半游戏区域原始 PNG 比较为 0 差异（`final-pause-screens/paused-game-pixel-check.json`）；本地化抽屉的文字另由 XCTest 断言，不将整个不同语言页面作为同一金标。

普通入口、系统选择取消和 20 次大厅往返/后台最终回归 3/3、243.300 秒（`final-hall-picker.log`，`tests-20261001-000602`）。选择器图标就绪后与最初参考严格一致。操作页末行改用真实底部 16 点锚点：首次 1/1、63.800 秒（`tests-20261001-001354`），四图逐张打开审阅；独立重采 1/1、64.074 秒（`tests-20261001-001534`）。这是截图夹具滚动位置修正，没有产品 UX 变更。参考仅替换这四项的准确末端图，其余沿用已审阅原图，失败批次保留。

上述定向补采按原始 xcresult 逐图登记出处，组合完整矩阵后 **62/62 严格通过**（`stable-native-diff-reviewed/report.json`）。最后重新读取 SDK、镜像和八个系统字体哈希，环境一致；没有遮罩、缩放、容差调整或自比。原始各批图片及旧失败报告均保留。完整 Mac 3.38.10 Dart 最新 **197/197**、analyze、语义兼容 **6/6** 通过（`current-dart-visuals-01.log`）；199 静态+81 动画重新采集，当前候选审阅和独立像素复验另记。

## 当前候选视觉与最终构建

当前 iOS 兼容 SDK 的两次独立采集已严格比较：108 页面、42 状态、18 伪本地化、31 补充状态及 81 动画帧，共 **280/280**。像素、几何、语义事实全部通过，另用保留 identifier／结构／边界／动作的完整语义树比较器验证 **280/280**；仅归一化运行期节点与排序对象 ID。报告为 `current-02-diff/*/report.json` 和 `current-02-full-semantics/report.json`。首批审阅记录逐项哈希；40 个当前变化场景实际打开，其余 240 项与此前逐张打开的图片哈希相同。没有调整容差、遮罩或把 Windows 金标整体改为旧 SDK 输出。

双真实 App 产品 UI 两种角色分配均通过（run `f9fc513f-3c3e-4a09-86e8-a2f052f1c631` / `da2693a1-c0ff-4d8e-acae-568d52010280`）：实际房间、Flutter 选游戏、双方 UI 输入、回房／继续及同连接换游戏，两个 PID、单次会话创建与代次断言成立。此批第一款 ROM 截图停在 OPTIONS、第二款在标题，不能冒称已进入双人擂台；固定许可 ROM 的双人开局截图另补。QR 使用实际邀请内容注入扫描结果边界，不属于相机光学扫码。

独立截图审阅发现原生房间标题黑字落在深色背景。新增真实 title element 像素断言，RED 的亮字比例为 0（`nearby-title-red.log`，`tests-20261001-002917`）。只将附近页面宿主设为 `.dark`，GREEN **1/1，17.029 秒**（`nearby-title-green.log`，`tests-20261001-003139`）；实际完整房间及标题裁图均已打开，白色标题清晰。系统选择器及全局外观不变。

包含以上生产修正的最终 iphoneos **Release arm64 / AOT 无签名构建成功**（`final-device-release-build.log`）。该 app 需要后续签名才能安装真机；模拟器依然是 Debug，不因 XCFramework 的 Release 目录名称改变认证口径。追加双人擂台测试首次误用不存在的 FlyNES scheme，失败保留 `two-app-arena-build.log`；随后按现有 target 构建测试成功，属于命令修正而非业务 RED。

补充旧 Stage-1 静态门禁实际失败：`ios/abi/flynes_app.symbols.txt` 未登记 G2 已合入的三个公开增量符号 `fly_catalog_snapshot_user_count/get`、`fly_catalog_user_state_copy_if_absent`；没有旧符号删除。核对公开头、共享实现和既有 host 测试后，仅补齐这三项清单，保持精确集合检查，RED→GREEN 见 `stage1-contract-{red,green}.log`。当前 arm64 Release 的 `libflynes_app.a` 已用 `nm -gU` 确认三项真实定义，不以声明代替链接证据。

追加双人 ROM 视觉检查：首批 `two-app-ui-d5594077-690b-4fbf-b27d-f709225d9208` 的 UI／会话断言通过，但实际打开 TITLE、GAME MODE 等阶段图后判定擂台验收失败。脚本错误地把冷启动标题当 OPTIONS；已按同一锁定源码补充 title→mode、LOCAL→options 两次 START 的按下／释放，分别保留截图和双方屏障。不会把此批 runtime 成功改写为双人实玩成功。

独立规格审计保留当前 I4 未闭合：真实 Flutter 目录重启重扫、ZIP 系统选择、失效重授权与扫描离页／失败、当前布局修改后保存／取消／重启、运行中后台及设置写入均需要对应证据。此前 20 次暂停设置没有每次进入布局，不冒称 20 次布局循环。系统 AX XL 实际为 235%，固定 Flutter widget 的 200% 是另一组证据。原生 VoiceOver 焦点及物理能力未由像素／语义树比较替代。

音频与复制补测：`testFlutterAudioWritesSurviveRestartAndLicenseCopyUsesPackagedBody` 两次实际切换、杀进程重开读值并恢复原偏好，复制真实打包 GNU 许可正文。首次从独立测试 runner 同步读取剪贴板被 iOS 16 系统粘贴授权阻塞，实图确认后中止该 runner、保留日志；修正为后台读取并由 UI 明确点击 Allow Paste，49.457 秒通过。布局当前 Flutter→原生更改后取消零字节写入、保存后重启读回与返回 Flutter 通过，36.026 秒（`additional-product-ui-02.log`）。运行中后台用例因 Home 转场尚未结束就同步读取 app.state 而失败，改为有界等待实际后台状态后单独重跑，不改变生产生命周期。

运行中后台→返回同局→大厅后台→杀进程重建已单独 **1/1，35.755 秒**（`background-rebuild-ui.log`，`tests-20261001-010158`）；返回后相同 gameSessionId/ROM 加载次数，帧继续增长；重建大厅 core=0、engine=1、active View=1、nearby picker observer=0，无虚构游戏会话。两张截图实际打开审阅。该 UI 用例不直接测量后台音频引擎内部状态；受影响媒体 XCTest 与此分列。

音频／复制／布局批次（`tests-20261001-005912`）中的五张附件均实际打开，声音开关重启值、许可复制成功消息、原生布局持久值和 Flutter Custom layout 摘要一致；该批第三项后台测试的初始转场等待失败仍保留，后续单项通过不将整批改写为 3/3。

## 追加输入与来源验证（进行中）

擂台脚本补齐菜单后第二批 `3cac3395-8ea8-4ef8-8c44-7800354999ce` 仍出现 UI 自动断言通过、实际图进入 STORY 的矛盾。逐阶段打开图确认部分短按没有推动预期菜单；不能用增加按住时长掩盖。追加 test-only `input_apply` 观察后，`5c526610-ce83-4fce-aef8-a3ff4d072f45` 的首个 START 失败：提交接口接受非零输入，完成帧已达 1001，核心应用边沿为空。后续增加独立 `input_submit` 回调计数，避免把监听未安装误判为采样丢失。

共享层稳定复现使用两个真实 LAN 会话，让对端暂不提交输入、预测深度达到 10，依次提交 START、150ms 后释放，两次均返回成功且窗口内完成帧仍为 10；解阻后双方达到 26 帧却没有 START→0 的核心记录。P1、P2 两方向均业务 RED，暂停／换局清理四项原行为通过。原始证据在 `.artifacts/flutter-g2/ios/nearby-short-tap-host/red-results.json` 及 `red-*.log`。待修复按真实核心帧消费的有界完整状态变化，不改变 wire/ABI，不把修复前的短按证据称为双人擂台通过。

真实目录系统选择、持久授权重启和原生 ROM 启动已在 `tests-20261001-010551` 执行，但后续重新扫描测试因查询已滚出屏幕的 Add file 按钮失败。实际打开失败图后确认精确 UUID 的 Scan／Remove 行仍存在；这是完成等待夹具错误，尚非该用例通过。保留被测试目录、内容相同的改名 ROM 和 `source-gap-ownership-*.plist`；仅在核对记录与 SHA 后显式恢复该测试拥有的 UUID 和文件，不清应用数据或其他来源。

带独立提交计数的原实现复跑 `161e4a0e-29ce-4a55-b9bb-4b03d8c52433` 通过：首 START 有两个 `input_submit`，核心 frame 374 按下、378 释放。26 张实际 PNG 全部独立打开审阅（房主 14、客机 12；客机无选择页属于角色预期），确认 PLAYER 2 HUMAN、双方角色、实际擂台及双方向内移动，后续切换到另一 ROM。对应 `observed-input-independent-review.{json,md}`。此轮未再次触发短按丢失，不能撤销可稳定复现的共享层 RED；动作后静帧没有捕获完整攻击形态，第二款停在标题／模式页，不宣称第二局完整对战。

来源显式恢复首次因使用 Windows ZIP 元数据生成的 manifest SHA 而在前置断言失败（`tests-20261001-012115`），未执行恢复或删除。核对 Mac 上原文件 SHA `27bc1722a8552adeb55a07062e222ba96a020cfebd196538f4eb8990e9d0d26b` 后锁定精确值，原夹具不变。恢复单项 **1/1，116.411 秒**（`source-gap-directory-recovery-02.log`，`tests-20261001-012309`）：UI 新别名证明之前重扫实际完成，验证改名文件内容后恢复，仅删除 UUID `440286CD-ECB6-488F-B671-45F17078BC76` 的来源登记，重启后原收藏、继续能力、书签与存档字节保留。三张附件均实际打开并记 SHA；正常目录／ZIP／失效重授权用例仍继续独立执行。

共享输入最终定向回归为 **14/14**（`confirmed-digest-ctest.log`），包括双角色短按、容量、双方暂停、换局和原时间戳／预测／启动路径；Android 五个受影响类 **19/19**、Harmony 附近选择 owner host **1/1**。首次 CTest 为 13/14，旧 play 测试在完成帧 68/63 时比较了 last_digest_frame 0/59；实际摘要依赖远端确认。仅把该测试改为有界等待两端同一非零确认边界，再原样比较 hash，失败与观测日志均保留。修复使用 16 槽完整状态变化 FIFO，预留最终释放槽；重复 held 不排队，拒绝不改已接受元数据，成功核心帧才消费，双方暂停与换局清理。没有 ABI／wire 改动；积压最多延迟 16 个实际帧，明确拒绝的过量输入不保证执行。静态算法与末端测试等待已独立审阅；修后真实双 App 仍待再次验证。

暂停→Flutter 设置→原生布局→同局暂停新增 **20 次完整循环，1/1，259.861 秒**（`tests-20261001-012848`）。每轮检查 gameSessionId、ROM 加载次数、暂停帧、核心／引擎／活动 View；不是此前只往返设置的 20 次。录制完整 266.57 秒原始模拟器视频 `native-handoff-video-01/layout-roundtrips.mov`。五个交接窗口提取 126 个原始帧（仅无损转向，按原始 frame index 含开始前保持帧），无整屏白色／纯色帧，首中末已打开；不将五窗口采样冒称 20 轮每一显示帧均人工验收。

视频另暴露 U01：系统启动页先白后深色。`UILaunchScreen` 原为空字典，Apple 官方契约默认 `systemBackground`，现指定通用不透明 `LaunchBackground` 颜色资源 `#121316`，不修改全局外观或原生布局页。契约测试 RED→GREEN 1/1；同任务模拟器普通无参数进程重启录屏 `cold-launch-red` 有 20/95 个超过 98% RGB≥245 的全白帧，`cold-launch-green` 为 **0/99**，实际红白帧、绿色深色帧和普通 Flutter 大厅均已打开。该检查证明本批启动白闪修正，不认证冷启动交互时延或物理显示。

来源后续失败继续分列：`tests-20261001-012525` 页面已显示 Continue，测试却先读取不存在的 Start.enabled；增加 exists 保护后执行到真实游玩和写档。`tests-20261001-013612` 新增存档断言拼小写 SHA，真实共享 canonical 规范为大写、文件实际已写入；只读核对 settings.flyset01 校验和／自动保存开关、实际文件及内容身份后修正测试大小写。仅允许当前精确拥有的测试 canonical 存档随游玩更新，其他存档字节和完整 key 集合继续严格检查，不清数据规避失败。

普通目录用例最终 **1/1，173.197 秒**（`source-gap-directory-04.log`，`tests-20261001-014931`）：真实系统目录选择、进程重启后授权读 ROM、写入当前测试内容的旧档、改名后重新扫描并用新别名检索，最后仅移除本次 UUID，其他来源和旧档保留。ZIP 用例 **1/1，181.931 秒**（`source-gap-zip-01.log`，`tests-20261001-015231`）：两个别名归并同一内容、重复选择不增加来源 UUID、重启后真实解压启动与存档保留。前两次失败登记的显式恢复分别通过 `source-unplayed-recovery.log` / `source-played-recovery.log`；后者恢复前核对已写入存档 SHA，不删除测试存档。

失效重新授权首批 `tests-20261001-015541` 已实际通过权限拒绝触发扫描失败、保留旧库及打开 Files，但在 Cancel 定位失败。实际截图和语义树显示系统选择器停在 On My iPhone，只有 Browse／Open；需先返回根页才有取消。该批仍为失败，精确自建来源及 chmod 状态保留，不能将“选择器已打开”当成取消／重新授权完成。

FIFO 修后正向真实双 App `acc3224e-7eb3-4e00-9a28-09858da0ece6` 两项 UI 和编排均通过，两个 PID 36773／36775、replaceCount=1、换游戏 generation=3。30 张 PNG、30 份语义与 15 个实际 `input_apply` 按下→释放记录独立审阅（`final-fifo-forward-independent-review.{json,md}`）：HUMAN、双方选人、真实擂台和方向移动、暂停／换游戏房间、继续及第二次 Flutter 选游戏均成立。原生 A 输入已采样，但静帧未捕获完整攻击动画；第二 ROM 仍仅证明标题菜单和输入，不称第二局完整对战。反向角色另行验证。

失效来源夹具精确恢复 **1/1，105.613 秒**（`source-permission-recovery.log`，`tests-20261001-020409`）。核对唯一 owner 记录、来源 UUID `00AF02BE-7A63-48F5-9260-0F1F6D56F15C`、非符号链接和原权限后，只恢复该测试目录 0755，立即验证完整文件 inventory／SHA，再通过 UI 移除该登记。全部旧来源及存档保留；未清理应用数据。恢复不是重新授权正常用例的替代证据。

正常失效／重新授权重跑 **1/1，241.719 秒**（`source-gap-reauthorize-02.log`，`tests-20261001-020602`）：真实权限拒绝→扫描失败但旧库保留→Files 返回 Browse 后取消，完整 metadata/bookmark 域零改变→选择 Replacement，UUID 始终为 `C26E8528-CB7C-41DD-8EE0-A939E53A61DC`→恢复自建夹具原权限→杀进程后实际读 ROM／保存→仅移除本次来源，原收藏及全部旧档保留。iOS 现有扫描不支持取消，界面无虚假 Cancel scan；这一能力边界与取消系统选择器分开记录。

真实扫描离页首批运行时 **1/1，164.140 秒**（`source-inflight-01.log`，`tests-20261001-021011`）：NSFileCoordinator 实际写协调锁阻塞同一来源的读，持续检查 held／readAttempted／!readGranted，期间进入 Flutter Audio，再回来源页；释放后真实读完成、同 UUID 和 100 游戏保留，再仅移除测试登记。独立打开六图发现返回及完成时目标行在屏外，语义正确但视觉证据不足；保持该限制，补精确 UUID 滚动与视口断言后另行重采，不把旧图认作可见行通过。

FIFO 修后反向 `31b72c5d-6fe2-4d56-9c8c-9dca4dc505fa` 首个 START 的“输入已接受”断言失败，host completedFrames 299→2645、nonzeroInputCount／observedInputSubmitCount／appliedInputSerial 均 0。故障在共享队列提交之前，不能归为已修正的队列消费问题；连接与运行成功不能替代此项。部分 xcresult 因另一 runner 失败后编排停止而未写完，保留原日志与协调状态，不把缺图记为通过。

扫描可见状态重采 **1/1，199.714 秒**（`source-inflight-visible-02.log`，`tests-20261001-021835`）。仅补精确 UUID 控件在实际 ScrollView 视口内的非零边界和稳定位置断言，再拍阻塞／返回扫描中／完成三图；独立逐图打开确认 Hundred 行可见，UUID `67859963-BED7-4E32-B578-397A42D97928` 从 Reading files／灰 Scan 变为 100 games／可用 Scan。Audio 及最终旧收藏／Continue 亦通过视觉核对；初始 U10 顶部图本身不证明目标行可见，新增三图才提供这项证据。原协调锁、超时、保留断言未放宽。

独立 iOS 输入叶子测试实际 RED：未采样的 150ms START 结束后得到 `0,0`，预期下一次 `8,0`；已有采样的长按释放不重复测试通过。原 `FrameInputLatch` 只保留不足 17ms 的释放，正常持续更长但未被采到的事件没有保护。证据 `.artifacts/ios-g2/frame-input-latch-150ms/`；这项确定缺陷与 `31b` 的具体原因分开。新增 test-only overlay／displayTick 观察的 `d9e74181…` 首个 START 为真实 8→0，中间有 tick，core 728→740 已采到，未复现旧失败；本轮存在约 598ms tick 间隔，但不能事后据此认定旧失败根因。

### 最终联机输入边界复现（2026-10-01 02:44）

最终正向双 App `31709652-fa26-4c94-9c25-e41ad84f8c47` 在第二次 DOWN 失败，不能沿用前次擂台通过替代当前修订。真实 overlay 的 32→0 位于同一显示帧间隔：156578.723139333→156578.885940484；前后 tick 为 156578.706399199→156578.886318279。约 162.8ms 按下全过程落在约 179.9ms 的 tick 空档内，shared 提交/采样计数未增加，进程、会话代次与连接未变。这次数据明确定位 iOS 仅按 displayTick 转发方向状态的问题；不能倒推没有触控轨迹的旧 `31b` START 失败原因。

原生边界测试先行 RED（`nearby-edge-red-test.log`，`tests-20261001-024430`）：真实 `RunSurfaceViewController.applyOverlayButtons` 32→0、不执行 displayTick，existing singleton 提交观察实际 `[]`，预期 `[32,0]`；非活动/单机对照通过，共 2 项 1 失败。该 spy 仅验证适配边界，不冒充核心或真实联机结果；生产修正及真实两角色回归另行记录。

最小修正后原生回归 **29/29，9.641 秒**（`nearby-edge-green-test.log`，`tests-20261001-025048`）：6 个新增边界场景、既有附近桥真实会话及手柄/runtime/音频相关测试全部通过。活跃 nearby overlay 直接提交既有共享 FIFO；成功热路径不投影 snapshot，失败时区分暂停/结束与容量不足。后一种仅让下一 tick 重试最新 held 状态，不能保证容量拒绝的每个短按都被保存。旧 generation 禁止向新局提交；nearby 不再消费离线 face latch，防止已释放 START 被下一 tick 重新插入。单机采样不变。独立源码审阅通过；真实双 App 仍独立验收。

当前 Mac 导出与本地 **64 个变更源码身份检查通过**，normalized dirty fingerprint `706f82c79832974e34a6d707840878595d43ac0dec5b13f0b6f8cb5b09aca74b`，base `bb7d709e5d9611bda20050ec4acf17d06b3cdac2`，版本 `3.0.8`。这是未提交工作树身份，不能写成新 commit。`final-source-manifest.json` 分列原始字节与 LF 规范化 SHA；Mac 使用独立 iOS 依赖锁例外单独验证。可重建源码差异另存 `final-source-diff.patch`、`final-untracked-source.zip`，不含私有 ROM、签名或生成包。

### 最终真实双 App 与工件（2026-10-01）

方向边沿修正后的正向 `9655f63e-1edb-410b-b025-790666cc1e16`、反向 `badc6699-f380-4fba-844f-68a51a789994` 各两项真实 UI 和编排全部通过。两轮各 30 PNG、30 对应界面语义及 15 组输入前后记录均独立审阅，见 `final-edge-evidence/{forward,reverse}-independent-review.{json,md}`。30 组输入均在最终核心记录找到按下与严格更晚模拟帧的释放；不能仅按日志 serial 后首次零状态判断，因为回滚会重访更早帧。HUMAN、双方选人、擂台、双方移动、回房继续及同连接第二 ROM 成立。静图不认证完整攻击动画，第二 ROM 验证到标题及输入；房间卡片为封面/擂台静态图，不冒称实时预览。最初一次批次图片显示异常经同 SHA 单图重开及像素统计排除，不列产品黑屏缺陷。

最终四工件已串行构建并按同一 ZIP level 9 配方冻结，版本均 **3.0.8 / 3000008**，身份 **com.flynes.app**。详细逐文件 SHA 在 `final-artifacts-manifest.json`；包留于 Mac `.artifacts/ios-g2/final-artifacts/`，不提交生成包。

| 工件 | 架构／模式 | ZIP bytes | ZIP SHA-256 |
|---|---|---:|---|
| Flutter 模拟器 | x86_64 Debug／含 kernel | 54,984,771 | `d85102f867fe2433bb0911e14a096b5885e1df78a97b92ffeac9572df8d888b1` |
| 原生模拟器对照 | x86_64 Debug／无 Flutter | 6,450,184 | `6f7f5d81c7392eaeb221bd2e551a65d9729da1ec100163113e8f08437e84b9ed` |
| Flutter iphoneos | arm64 Release／无 kernel | 11,433,350 | `8e638698f858dedd1ffddb67bf680c80e71e59f710dac157494b11d6dc9e6b51` |
| 原生 iphoneos 对照 | arm64 Release | 4,818,089 | `6f86940cbb4fd60f5c480eb1b944cbf2cf22a61b087c3f637f89375c2032456c` |

arm64 Release 压缩增量 **6,615,261 B / 6.31 MiB**，这是实际单架构对照，不冒充 Android/OH 双 ABI 包体。模拟器经 codesign 检查为本地 ad-hoc、无 team/profile；iphoneos 构建未签名，没有生产/商店签名或安装资格。03:03 `xcdevice list` 只列 My Mac 与模拟器，没有连接的 iPhone，不能取得 Release 真机性能或签名安装证据。

静默成本首批 `paired-debug-observation-01` 保留失败：simctl 覆盖安装把 data container UUID 从 `7BD8BB36…` 重定位为 `61083048…`，工具错误地以路径不同直接中止，没有采到样本。旧路径已不存在，新位置仍有 9 个保存文件；因首批没有安装前文件 inventory，不能事后认证该批全部数据未变。后续工具改用安装前后持久数据相对路径+SHA 严格比较，路径迁移单独记录；新批次另存，不覆盖首失败。

### 最终成本诊断与未放行项

采集器先保留 5 项业务 RED，再改为每次覆盖安装立即前后的 `Documents`、`Library/Application Support`、`Library/Preferences` 普通文件相对路径+SHA 严格比较。新增/丢失/改动及缺少 before inventory 均拒绝，允许系统重定位容器；tmp、Caches、SystemData、目录元数据不纳入内容保留证明。Windows 14 通过/1 软链接权限 skip；Mac **15/15、0 skip**，`collector-data-inventory/mac-green.log`。独立源码审阅通过，不把工具修正描述为产品存储迁移。

新批 `paired-debug-observation-02` 实际完成原生／Flutter 各 **2 次预热 + 12 次正式启动、60 个 RSS 样本**。没有同时构建或跑设备测试。两次覆盖安装各 **41 个持久文件**，安装前后完整 key 集合与字节 SHA 均一致，容器 UUID 两次均重定位。最终保留 Flutter 安装。所有样本、命令原始输出与 SHA 清单位于该目录。

| Debug 模拟器诊断指标 | 原生 | Flutter | 解释 |
|---|---:|---:|---|
| simctl 启动命令墙钟 P95 | 624.254 ms | 834.583 ms | 命令返回时长，不是首帧、交互或服务就绪 |
| 固定启动后窗口 macOS RSS P95 | 138,236 KiB | 305,168 KiB | 差值 166,932 KiB / 163.02 MiB；非 PSS、footprint 或稳定游戏内存 |

`firstPaintMs`、`firstInteractiveMs`、`nativeReadyMs`、PSS、physical footprint、post-GC heap 均为 **null / 未测**，性能门禁保持 **not_evaluated**。iOS 当前旧单槽没有 Android/Harmony 的 60 秒周期历史自动保存；不能伪造相同 AUTO 工作负载或用 Debug 数据认证 iphoneos Release。实际 core/audio/engine/View 的 20 次往返断言已通过，但不是可验证 GC 后平台堆增长测量。无连接的 iPhone，本轮不能完成签名真机安装、Release 内存/时延或硬件资格；原生 VoiceOver 焦点/朗读也未由语义树认证。

最终验证工具修订后的整体源码指纹为 `4446044d845ceebed257680aaf0d892a68744ce4457550df251058f8913232ca`，Mac **64 文件**再次核对通过。工件构建时指纹 `706f82…` 保留于 `app-build-source-manifest.json`；之后仅采集器和其 Python 测试两文件变更，产品构建输入未改变，四个包哈希不变。这两个身份及差异已写入最终 manifest，不能混写成新 commit 或隐瞒测试工具后置修正。

### 冻结包的普通启动与提交界限

从已冻结 SHA `d85102f867fe2433bb0911e14a096b5885e1df78a97b92ffeac9572df8d888b1` 的 **3.0.8 x86_64 Debug** ZIP 解包，恢复文件权限并对两台任务模拟器覆盖安装；安装后逐项复核各 **78 个文件 SHA**。两台 `com.flynes.app` 均无测试启动参数，实际进程 PID 与普通启动截图已记录在 `final-installed-artifact/report.json`，两图已分别打开：均显示深色 Flutter 大厅、四分类、两行横向库及选中游戏主操作，没有原生蓝色大厅。simctl 原始 PNG 按设备固有方向存储，未改图像内容以美化结果。SE3 41 个、iPhone 14 10 个持久文件安装前后相对路径及字节 SHA 一致；其中旧存档分别 9／5 个字节不变。容器 UUID 重定位由工具如实记录，不能以容器路径变化冒称丢档。普通启动之后正常运行可能合法更新最近游玩等状态；上述保留比较发生于每次安装前后立即时刻。

本分支按仓库 pre-commit 版本政策提交时，hook 会将 `VERSION` 的 PATCH 从测试工件的 **3.0.8** 递增。以上 ZIP 哈希、安装、性能及截图属于明确的 **3.0.8 提交前源码构建**；提交后的版本元数据与测试工件版本不同，不能把现成 unsigned 包标记为该提交的最终发布构建。上线或签名发包仍须在目标提交上重新构建与验收。本轮没有连接的 iPhone，Release/PSS/真机验收及 G0/G1/G2 整体放行仍保持未完成。
