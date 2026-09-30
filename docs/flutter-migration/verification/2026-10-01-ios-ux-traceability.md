# iOS G0/G1/G2 UX 与动画证据追溯

审计快照：2026-10-01。按最终串行验证结果复核测试、报告及独立审阅；矩阵本身不代替原始 XCTest、截图和两 App 报告。条目依据 `docs/flutter-migration/requirements/REQ-008-012-030-031-g2-design.md` 的 U01–U26／A01–A17。下列“覆盖”表示指定断言有相应证据，不表示整项所有平台、所有故障或真机条件均被认证。

保持原授权边界：原生单槽 `Documents/saves/<safe canonical ID>/autosave.nst`；不扩展 REQ-020 历史库。应用身份 `com.flynes.app`、现有目录/书签/内容身份/保存所有者继续沿用。

## 测试与证据索引

所有路径相对工作树根目录。下表使用以下缩写，避免把总测试数代替具体行为。

| 缩写 | 具体来源 |
| --- | --- |
| PT | `ios/tests/FlutterProductUITests.mm`；下表给完整 selector |
| PS | `ios/tests/ProductServiceTests.mm`；下表给完整 selector |
| FS | `ios/tests/FlutterSourceUITests.mm`，正常类 `FlutterSourceUITests` 与 `FlutterSourceGapUITests` |
| SI | `ios/tests/FlutterScanInFlightUITests.mm`，`testRealCoordinatedScanContinuesAcrossFlutterSettingsAndPageReturn` |
| NL | `ios/tests/NearbyLiveRoomUITests.mm`，真实 native peer **在同进程**，不可当作两 App 产品验收 |
| TA | `ios/tests/NearbyTwoAppUITests.mm`：`testHostFlutterSelectionAcrossTwoApps`／`testGuestInputAndContinueAcrossTwoApps`；两个真实 App，实际 UI 输入 |
| Shared | `ui/flutter/test/product_*_test.dart`，具体文件/用例见各行；widget/协议测试不自动等于原生交互 |
| V280 | `.artifacts/ios-g2/current-02-diff/{visual-actual,state-actual,pseudo-actual,extended-state-actual,animation-actual}/report.json`：108+42+18+31+81 全部通过；`.artifacts/ios-g2/current-02-full-semantics/report.json` 完整语义 280/280 |
| V-review | `.artifacts/ios-g2/candidate-all-images-review.{json,md}` 逐张审阅旧候选；`.artifacts/ios-g2/current-visuals-01-review/` 当前变化审阅/每 family review。当前 40 个变化场景实际打开，另 240 个沿用已打开图片的相同 SHA；新增语义单独审阅，不以像素相同替代 |
| N62 | `.artifacts/ios-g2/stable-native-diff-reviewed/report.json`：62/62，同环境像素/几何/XCTest树；参考/实际原图与逐图来源保留在 report artifacts 对应目录。人工记录 `.artifacts/ios-g2/real-ios-visual-review.md` |
| N62 chronology | 原 `stable-native-diff-03` 59/62，较早名为 `stable-native-diff-final` 的结果 60/62；系统 Files 图标就绪和实际底部16点锚点修正后，`tests-20261001-001354` 四图重审，独立 `tests-20261001-001534` 重采，才得到 N62。其余58图沿用已审阅来源；不能按目录名“final”推断时间或重新列为未解决缺陷 |
| Handoff | `.artifacts/ios-g2/native-handoff-video-01/{layout-roundtrips.mov,handoff-frame-analysis.json,independent-review.json,independent-review.md}`；20次完整布局往返运行 `tests-20261001-012848`，五个窗口126帧证据；不是20轮每帧均人工审阅 |
| Upgrade | `.artifacts/ios-g2/native-before-upgrade-covering-install.json`、`native-before-upgrade.json`；PT `testCoveringUpgradeKeepsImportedProgressSettingsAndAuthorization`；具体原始 xcresult/包 hash 见 `docs/flutter-migration/verification/2026-09-30-ios-migration.md` |
| Src | `.artifacts/ios-g2/source-gap-directory-04.log`（014931，173.197s）、`source-gap-zip-01.log`（015231，181.931s）、`source-gap-reauthorize-02.log`（020602，241.719s）；对应 `source-gap-{directory,zip,reauthorize}-final-screens/` PNG+语义 |
| Scan | `.artifacts/ios-g2/source-inflight-visible-02.log`（021835，199.714s）、`source-inflight-visible-screens/`；真实写协调锁/读尝试/未授权读、离页设置、返回仍运行、释放后完成；目标行已可见。旧 `source-inflight-01.log` 运行通过但返回两图屏外，不充当可见截图证据 |
| TwoApp | `.artifacts/ios-g2/final-fifo-forward-report.json`、`final-fifo-forward-independent-review.{json,md}` 和 host/guest 原图；后续 direct-edge 修正的最终正反结果在 `final-edge-evidence/{forward,reverse}-report.json`，分别30PNG及30输入前后记录；对应独立审阅逐图/逐输入绑定，不沿用历史修订通过 |

N62 模拟器系统大字号为 AccessibilityXL **40/17≈235%**，不是200%；共享受控夹具100%/200%与此分列。N62与V280不是同一种采集，不能合并计数成统一原生动画认证。

## U01–U26

| ID / 批准行为 | 具体测试与证据 | 范围、保留限制 |
| --- | --- | --- |
| U01 冷启/初始化 | PT `testOrdinaryLaunchUsesFlutterProductHall`；Shared `product_app_test.dart`：`U01 retry reacquires bootstrap after startup failure`、普通大厅入口；`.artifacts/ios-g2/cold-launch-{red,green}/` 与 Handoff 独立审阅；启动白闪20/95→0/99 | 普通无参数进程重启、深色启动页/Flutter大厅；不是设备冷重启或可交互P95。失败重试为共享故障测试，不虚构真实生产初始化失败注入 |
| U02 分类/选择/锚点 | Shared `product_hall_test.dart` 的分类独立横向锚点、`product_controller_test.dart` 的显式canonical选择持久/重叠刷新；PS `testBootstrapPreservesLegacyNavigationAndCatalogUsesRealSnapshot`；PT20次大厅往返；N62四组合大厅 | 实际canonical导航与widget状态机覆盖；235%标题省略/英文Continue折行仍是已记录可读性限制，不称全文无截断 |
| U03 卡片/详情 | Shared `product_hall_test.dart` 选择/横拖、迟到详情及紧凑封面；`product_cover_test.dart` 解码占位；FS Hundred双别名唯一卡片；N62大厅及V280 | 实际原生封面/标题和完整动作边界已审；静帧不代替点击/拖动断言 |
| U04 开始/继续 | PS `testLegacyResumeDoesNotUseLastPlayedAndLicenseIDsAreAllowlisted`、`testLegacyCheckpointIsRetainedAndResumeReflectsExistingAutosavePolicy`；Shared hall：`U04 failed resume capability cannot display Start`；FS实际Continue/重启读档；Upgrade | iOS真实旧单槽与autosave开关，未声称history head/pending已迁移 |
| U05 搜索 | Shared controller：精确150ms合并、clear/category取消、dispose/迟到结果；hall可编辑语义；FS文件/ZIP别名；PT四组合搜索键盘；N62+V280 | 双语/别名与键盘画面覆盖；原生VoiceOver焦点顺序仍另列 |
| U06 空态/错误 | Shared hall/controller与V280 state/pseudo/extended空态、失败重试；Src实际不可读来源错误且旧库保留 | 不将每一种空态的widget故障注入说成每端原生故障均已发生 |
| U07 双人筛选/附近 | Shared hall/controller持久筛选及显示状态；`product_nearby_navigation_test.dart`；NL与TA入口；N62独立switch矩形 | 筛选与会话独立；不包含退役配对码/蓝牙功能 |
| U08 房主选游戏 | Shared nearby navigation三步键盘→搜索→closeHost；NL `testFlutterHostRoomRetainsCoverProgressAndPickerWhileEitherPlayerCanContinue`、`testFlutterHostChangesGameWithinTheConnectedRoom`；TwoApp真实选择/返回/HUMAN擂台；`.artifacts/ios-g2/nearby-state-reviewed/` | nearby purpose显示Choose game、显式Return to room；早期9图导出覆盖同名附件，不能声称含两次选择。最终正反角色各30图、15组核心输入已独立审阅 |
| U09 来源布局 | Shared `product_sources_test.dart`、N62来源四组合及滚动；FS exact `source-remove-UUID`；Src/Scan | 实际窄横屏纵向、来源类型/数量/内置保护可见；原生VO是否跳过屏外节点尚无焦点实测 |
| U10 原生选择/取消 | PT `testSourcePickerCancellationReturnsToFlutter`；FS `testExistingSingleImportIsIdempotentAndPickerCancellationPreservesUpgradeData`、目录/ZIP用例；Src重新授权取消metadata/bookmark零写入 | 系统Files真实持久授权；内层On My iPhone需Browse返回根再Cancel。未把恢复操作计入正常用例通过 |
| U11 应用所有者扫描 | SI+Scan真实NSFileCoordinator阻塞/离页/重连观察/完成；Src真实失败；Shared sources committing不可取消、未知不造百分比、known progress/partial/failure；PS `testAcknowledgedSettingsAndLayoutReadsDoNotWaitForCoordinatedScan` | iOS实际能力不提供取消扫描，所以无假Cancel scan；已知百分比/部分提交分支有共享测试，真实iOS采集主要为未知读进度和实际访问失败 |
| U12 失效/同UUID重新授权 | FS `testUnavailableOwnedDirectoryCancelAndReauthorizeRetainUUIDAndLibrary`，Src020602；先权限拒绝保旧库，取消零写入，Replacement沿原UUID，重启真实读ROM | 仅操纵明确自建许可夹具；保存文件与Single原数据保护。失败批次及4次显式恢复保留为历史，不与正常通过混计 |
| U13 移除 | FS `testHundredCanonicalAliasesAndConfirmedRemovalKeepExistingSourcesAndSaves`；Gap3用例精确UUID移除；PS `testPickerImportDeduplicatesAndRemovalPreservesROMAndFavorite`；Shared failed removal保行/cancel无写 | ROM、原来源、所有旧存档字节保留。只有本次明确owned canonical游玩后允许更新，其他字节/keys仍严格；不是笼统排除全部测试存档 |
| U14 设置框架 | PT `testFiveSettingsSectionsLicensesAndLayoutReturn`；Shared settings固定顺序、分区独立滚动；N62五区；pause20/layout20 | 普通大厅与同局pause宿主均覆盖；命名测试有各自前提，不宣称未过滤全UITests可同批运行 |
| U15 显示/硬件锁 | PS `testOneFieldSettingPatchPreservesOtherSettingsAndRejectsLockedOption`；Shared settings `U15 Extreme is not silently enabled without device evidence`；N62 Display | 保留锁定原因，模拟器不解锁；没有硬件认证或发布帧率推断 |
| U16 操作/重置/触感 | Shared settings与motion重置取消、选项与失败回滚；PT controls末端、layout持久；N62准确底部锚点四图；实际native输入回归 | 触感预览接口/状态可操作；模拟器没有物理触感质量证据，不能把tap返回当震感实测 |
| U17 音频/失败回滚 | PT `testFlutterAudioWritesSurviveRestartAndLicenseCopyUsesPackagedBody`；Shared `U17 failed sound write retains value and persistent error`；PS单字段确认值；受影响runtime/audio XCTest | 设置写入重启值真实；后台UI没有直接测音频引擎内部状态，媒体测试单列 |
| U18 语言/自动保存 | PT `testPauseLanguageChangesRefreshExistingDrawerWithoutReloadingGame` 英→中→英且nonce/load/frame不变；PS旧档策略；N62 Game/language | 包含immutable titleFields解决game:SHA标题；`.artifacts/ios-g2/final-pause-screens/paused-game-pixel-check.json` 仅暂停游戏区域0差异。无新历史间隔页 |
| U19 关于 | PT五设置区、N62About；Shared缺build metadata明确unavailable；PSbootstrap真实构建数据 | 缺链接显示未配置；未伪造源码链接或签名身份 |
| U20 许可 | PT真实packaged license复制+系统Allow Paste；Shared `product_licenses_test.dart` 错误重试、迟到正文、列表/正文独立位置；N62许可及下滚 | 法律正文保持原语言；下滚图证明可滚动，不宣称每行文本均人工逐字核验；合法链接协议受共享测试，不额外声称浏览器外跳实测 |
| U21 共用弹层/消息 | Shared settings/source/motion单选checked、取消无写、消息持久/3s/可访问成功；N62重置确认、FS移除确认、真实复制消息 | native系统Files外观归系统；不把系统32pt按钮算成Flutter48pt回归 |
| U22 原生布局往返 | PT `testFlutterLayoutSaveCancelAndRestartPreserveCommittedDraft`、`testGamePauseFlutterSettingsNativeLayoutTwentyRoundTrips`；Shared layout摘要刷新；Handoff | 当前Flutter入口的取消零字节、保存重启、回同分区/同局已实际验证；旧control.*原文缺陷已修正。20轮计数与五窗口视觉各自注明 |
| U23 暂停设置 | PT `testGamePauseFlutterSettingsTwentyRoundTrips`、pause语言及layout20；真实core/engine/View计数；PSprojection非阻塞与lease | nonce/ROMload不变、暂停帧不增长；输入/PCM/保存边界由相关runtime/audio测试补充，UI截图本身不认证音频静音 |
| U24 游戏返回 | PT `testTwentyGameReturnsAndPausedBackgroundKeepOwnersBounded`；Shared `U24 dirty domains and host reattachment share one refresh`；FS实际保存/Continue；Handoff | 先原生保存关闭再大厅，owner归零；原生会话次数与共享分类/查询/锚点状态机分列 |
| U25 联机往返/连接 | NL五类继续/换局/peer断开；TA真实两进程配对→Flutter选游戏→输入→继续→同连接换游戏；TwoApp报告PID/session/generation/replaceCount与实际apply→0记录 | 最终正反两向均已通过并独立审阅；第二ROM只证明实际新ROM画面/输入，不称第二局完整对战。同进程peer不替代TA |
| U26 返回/后台/重建 | PT `testRunningGameBackgroundReturnsSameSessionAndHallRebuildHasNoCore`（010158）、两种20轮；Shared app pressure/后台合并刷新/compact返回；nearby keyboard真实focus+非零viewInsets | 重建大厅core0/engine1/View1/observer0，无虚构会话；不是任意系统杀进程时机或物理后台功耗认证 |

## A01–A17

共享动画的start/middle/end来自 `ui/flutter/verification/g2_animation_capture.dart` 控制时钟，实际PNG为 `.artifacts/ios-g2/current-visuals-02/animation-actual/`，V280逐项严格比较。原始分组包含A01–A14与A17（含进出/fast/unknown等），**没有伪造A15/A16原生交接夹具**。A15/A16使用下述真实原生证据。

| ID | 具体断言/原图 | 实测边界 |
| --- | --- | --- |
| A01 按压80/120ms | Shared hall `A01 primary press enters in 80 ms and releases in 120 ms without resizing`；motion disabled/focus/retired action；`A01-{press,release}-{start,middle,end}.png` | 受控颜色/尺寸/去重与中途取消；不是测量真实触屏物理响应 |
| A02 选择/焦点160ms | capture `A02 A03 A06 actual hall selection and search frames`；`A02-*.png`；motion键盘focus与V280扩展状态 | 边框/背景/尺寸证据；原生VO朗读焦点未由此认证 |
| A03 详情120ms | hall第三次选择覆盖迟到结果、保留painted detail/禁旧actions；`A03-*.png` | 最新请求/淡变均测试；无真实目录慢速故障覆盖宣称 |
| A04 封面120ms | `product_cover_test.dart` 解码/错误同尺寸占位；`A04-*.png` | 截图为解码完成时钟控制，不认证所有第三方ROM封面 |
| A05 分类/双人150/120ms | hall分类结果120ms且grid不移动、独立anchors；`A05-*.png`、`A05-two-player-*.png` | 共享动画与持久导航真实owner分列 |
| A06 搜索160ms | hall高度+透明度、midpoint反向不遗留focus/query；`A06-*.png`、`A06-close-*.png`；N62键盘 | 键盘→搜索→closeHost三步另有业务测试，不以截图替代 |
| A07 二级220/180ms | motion `A07 A08 ... interruption at entry midpoint preserves product ownership`；`A07-*.png`、`A07-return-*.png` | 系统交互返回的物理手势全路径未被widget时钟概括 |
| A08 来源同A07 | 同上 + `A08-*.png`、`A08-return-*.png`；Scan离页不停止owner | 与真实源任务生命周期分开验证，无额外页面缩放 |
| A09 设置/许可120ms | licenses缓存不重读、未缓存正文到达fade不移动导航；settings独立scroll；`A09-*.png`、`A09-license-*.png` | N62真实稳定页/滚动证据，不认证每次原生屏幕刷新帧 |
| A10 对话框180/120ms | motion精确duration、Escape中途取消回焦点；`A10-*.png`、`A10-exit-*.png`；N62/FS确认框 | 取消零写入真实源/布局测试补齐 |
| A11 开关150ms | hall switch start/mid/end；settings失败回原值/等待确认；`A11-*.png` | 动画结束不等同native写成功；实际声音重启持久验证另有PT |
| A12 来源行180ms | sources成功确认后才缩行；motion UUID重现唯一动作、dispose/keyboard focus；`A12-*.png`、`A12-insert-*.png`；Src | exactUUID与真实来源去重/移除均已验证，无改金标掩盖定位错误 |
| A13 延迟150ms/进度120ms | motion fast work不闪、dispose换任务；sources known interpolation不造total；`A13[-fast/-unknown]-*.png`；Scan可见真实未知进度 | iOS原生扫描不提供假known percent/Cancel；共享known分支不冒充当前iOS吞吐量 |
| A14 消息160ms | motion替换取消旧expiry、background不复活、outgoing清actions/semantics、accessible成功保持；`A14-*.png`、`A14-exit-*.png` | 原生VO通知实际朗读尚未验证；持续错误行为有widget及真实源错误 |
| A15 原生交接 | `product_presentation_test.dart` token/旧raster拒绝；PS handshake；Handoff五窗口126帧与cold-launch回归 | 五窗口包含实际前保持/中间/结束画面，无旧大厅/整屏空白；直接切换没有虚构50%中帧。不是全部20轮每显示帧检查 |
| A16 返回Flutter | Shared app `A16 native context restoration removes old settings without a reverse animation`、U24统一刷新；PT20轮/布局20及Handoff | 路由先还原再读快照、同局不重载；真实录像窗口与逻辑断言共同支撑，不将widget捕获冒称原生转场 |
| A17 减少动态 | motion运行中切换reduced motion，静态loading、dialog/switch/row即时settle；hall outgoing/detail/category；`A17-*.png` | 共享状态机/语义验证；235%字号矩阵不是系统Reduce Motion或VO系统开关实测 |

## 当前仍须保留的门禁约束

1. **最终修订双App与构建**：最终方向边沿修正后的原生29项（`tests-20261001-025048`）通过；最终正反角色 `9655f63e…` / `badc6699…` 各两项 UI 和编排通过。正反各30图及各15组严格更晚帧释放均已独立审阅，四份工件已冻结。不得将历史forward擂台、同进程NL或两App runtime 600帧证据直接替代当前修订产品UI验收。`31b`失败原因仍不由独立150ms latch RED反向推定；真实touch/apply证据各自保留。
2. **G0/G1性能口径**：iOS simulator当前Flutter为Debug/JIT，iphoneos unsigned Release编译不能当模拟器Release。现有 `tools/flutter/collect_ios_simulator_evidence.py`（若最终使用，按实际参数与缺失项报告）只是诊断采集工具；本轮仍无可放行的iOS同环境2预热+12冷启动可交互P95和游戏完整内存/媒体配对预算结果。不能用simctl返回时间代表交互就绪；macOS RSS/footprint不是PSS。真实物理延迟/功耗/热/刷新资格不从模拟器外推，也不因本轮任务额外开启硬件模式。
3. **原生可访问性**：3.38兼容6例修好了伪语言/800×360/100%与200%的switch与search独立可操作矩形。hidden字段、progress role/range的跨SDK序列化差异不等于已证明功能失败；原生来源屏外节点的VoiceOver焦点排除、朗读顺序/进度通知仍无实际焦点运行证据。235%来源实际滚动后可点击、屏外零矩形已验证，但不能替代VO。保留已记录AX大厅省略和Continue折行限制。
4. **源码/工件身份**：`final-source-manifest.json`明确base `bb7d709e5d9611bda20050ec4acf17d06b3cdac2` + dirty源码指纹，不是新提交。最终验证工具修订后指纹 `4446044d845ceebed257680aaf0d892a68744ce4457550df251058f8913232ca`；工件构建时指纹 `706f82c79832974e34a6d707840878595d43ac0dec5b13f0b6f8cb5b09aca74b` 同时记录 `dirtySourceFiles` 原始字节和 `normalizedLFSourceFiles` 规范LF字节，两者必须各按对应口径比较。本次已核实当前latch/header及测试分别与两套map完全匹配；CRLF/LF差异不是过期证据。根任务另报告Mac导出64文件匹配。四份测试工件绑定构建时源码身份与实际包 hash；其后仅采集器及其 Python 测试变动。提交时 VERSION hook 再递增 PATCH，3.0.8 工件是提交前的测试构建，不能标为提交版工件。
5. **范围与正常用例选择**：四个消费过UUID的Gap恢复类已归档到 `.artifacts/ios-g2/source-recovery-history/` 并从普通源码移除。保留通用marker授权Hundred恢复供明确过滤使用；原生seed/upgrade和这些用例也有互斥前提，不声称未过滤整个 `FlyNESUITests` 可统一运行。恢复成功不计作来源功能成功；目录/ZIP/reauth/真实在途扫描已有各自正常通过证据，不重新列为未实现项。

G2 iOS 模拟器产品闭环、最终串行结果及身份绑定已有上述具体证据；性能与真机门禁仍未放行。G0/G1跨端完整放行还受批准的预算与跨端门禁约束，不能仅以iOS可构建、页面数、测试总数、280或62张图宣布整体完成。没有新增REQ-020、第二游戏完整战斗、物理性能或无关全平台重跑要求。
