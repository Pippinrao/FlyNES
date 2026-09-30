# G2 实施记录（持续更新，未验收）

源提交 f2c5558c / 3.0.6 加当前未提交 G2 修改。实际安装和验证对应工作区开发快照，不能称为已冻结 revision。无 iOS 操作，无真机依赖。未发布、未合并。

## 已执行

- 用户批准的 U01～U26、A01～A17、W0～W8 已进入 requirements 设计／计划，STATUS／索引／路线同步。内容是验收要求，不是通过证明。
- 共享 `fly_product_catalog_project`：调用既有 GameCenterState／能力注册规则，真实 catalog generation，128 上限，窗口外选择保留，版本／指针／错误 ABI 防护。先 34 个业务失败断言；补 manifest 英中标题时另有 2 个失败断言；相关 CTest 最终 15/15。独立规格审阅及质量审阅无阻断项。平台私有头扫描待适配完毕补齐。
- Dart 产品通道和控制器：协议／请求／宿主代次、迟到选择、翻页代次、重复启动、写失败、释放观察。首轮 10 RED→GREEN；独立审阅新增选择／窗口／bootstrap／过期重查／旧错误复现；质量审阅另补已提交收藏刷新、清除旧详情、初始化竞争。日志位于 `.artifacts/flutter-g2/client/`。
- 共享页面首版：四分类、搜索、详情、恢复能力、收藏、双人筛选；来源；五分区设置、许可；Flutter 内部路由。主入口从 G1 实验页改 ProductApp；中文 Material 本地化来自 SDK。每个页面先失败测试后实现。`flutter analyze --no-pub` 无问题，`flutter test --no-pub --reporter expanded` **76/76**，包括原 28 项回归。日志 `.artifacts/flutter-g2/flutter-suite.log`。
- Android 产品桥和普通入口：588 JVM 测试 0 fail，2 既有 skip；debug APK／test APK／arm64 与 x86_64 JNI 构建通过。直接 `am instrument` **3/3**：真实共享投影／设置／许可／旧宿主；原生游戏→Flutter 设置→同一 MainActivity／引擎及暂停媒体时钟→大厅；真实 SAF 文件选择取消，目录 generation 和来源不变。
- Android 覆盖安装前校验证书 SHA256 相同；设备此前是 3.0.5 Release，现在是 3.0.6 开发快照。firstInstallTime 保持；没有卸载、清数据或 UTP。旧 Release 非 debuggable，`run-as` 无法读取旧私有文件，因此该项不证明全部升级数据保留，W7 必须另用完整冻结基线验证。

## 视觉工作

Android 参考截图 `.artifacts/flutter-g2/reference/android-native-hall.png` 已打开核对；参考图显示文件名标题，G2 使用现有 manifest 的双语产品标题，不能复制参考图中的这项缺陷。

显式 runner：

```powershell
Set-Location ui/flutter
E:/workspace/lib/flutter/flutter/bin/flutter.bat test --no-pub --reporter expanded verification/g2_visual_capture.dart
```

8 个页面 × 3 尺寸 × 2 语言 × 2 字号 = **96/96 采集通过**。这是实际截图，不是 golden 比较通过。原首次 95/96 因英文 200% About 导航在滚动视口外；增加真实滚动操作后可到达。首次图标字体未加载显示方框，实际打开图片发现后补加载 MaterialIcons，重新采集。禁止直接批量接受图片为金标。

固定字体来自已安装 Flutter SDK 与任务 Android 镜像，仅置于忽略证据目录：

| 文件 | SHA256 |
|---|---|
| Roboto-Regular.ttf | 79e851404657dac2106b3d22ad256d47824a9a5765458edb72c9102a45816d95 |
| NotoSansCJK-Regular.ttc | 3e7e5afaac2c6d872592d76abedac03a51c6f0fc42d11e311ff2816a6c368afe |

Android 镜像 fingerprint：`Android/sdk_phone64_x86_64/emu64x:15/AE3A.240806.019/12368160:userdebug/test-keys`，物理像素 1080×2340、density 440；模拟器横屏由正常宿主控制。

首批 display／controls／audio 共 36 图已逐张独立审阅；4 图在滚动后发生 AppBar tint 偏色，已禁用该 tint，待重采及复审。Android 普通 Launcher 实际截图发现低高度卡片封面被响应式分支隐藏；新增 850×392 失败断言后改封面与标题横排，17 项大厅用例通过。这两项修正尚未更新已安装 APK，不把旧图当新结果。

## 未完成／继续执行

## 本轮续接记录

- Flutter 当前全套 **88/88**，静态分析无问题。新增业务 RED→GREEN：同路径截图版本缓存；180/120ms 弹层及减少动画；短横屏键盘与 200% 字号；内置来源名称本地化；同一宿主重新附着保留嵌套路由；初始化失败重试 bootstrap；分类切换禁止旧详情启动新 ID。日志分别为 `cover-*`、`motion-*`、`hall-insets-*`、`source-locale-*`、`host-route-*`、`review-state-*`、`category-red.log`。
- 首批 96 张页面截图均实际打开审阅。设置栏 tint 和许可正文居中已修正并复审；许可改用打包的真实长正文。大厅／来源 24 图完成目视检查，来源内置名称本地化之后需更新对应中文图。仍不是全部 U/A 状态或 golden 门禁完成。
- Android 五项独立审阅问题：重命名重复 ROM 的内置元数据；浮点枚举绕过能力锁；失败设置写入被隐式重试；来源移除忽略事务错误；重授权失败补偿。8 条业务失败转绿，596 单元测试零失败／2 既有跳过，debug 与 instrumentation 构建通过。复核再发现已提交移除后映射清理失败导致快照代次不一致，已新增 RED→GREEN，独立复审中。没有用这些构建替换此前安装证据。
- Harmony 公共目录适配：原生异步队列使用公共 `fly_product_catalog_project`；视图 revision 保留不可变快照（收藏写入不会增加目录 generation），单窗口最多 128 条。纯投影 host 业务 RED→GREEN；OH clang C++17 严格语法检查通过，完整应用构建进行中。
- 发现旧鸿蒙内置大厅使用 manifest 逻辑 ID，真实扫描目录使用内容哈希。新增 additive C ABI `fly_catalog_user_state_copy_if_absent`，保留旧记录、精确复制用户计数／修订、已有目标优先；3 条业务 RED→GREEN，独立审阅无阻断。模拟器升级数据仍需后续真实验证。

## 后续门禁仍未完成

OH 产品适配、默认入口与单引擎租约；Android 适配审阅发现项和扫描阶段、观察解绑、稳定错误补全；全部来源成功路径及联机路径；所有 UI 状态及 A01～A17 中间帧、语义和像素差异门禁；完整两端截图和初始金标审阅；覆盖升级完整数据、20 次往返；双向联机；Release 成对性能／包体／最终冻结工件。

G1 的 200ms 原生首卡及 debug PSS 失败仍有效。本记录不宣称 G2 完成、三端完成或物理性能认证。


## 续接：产品宿主与共享动画（2026-09-30）

- 工作区仍基于 `f2c5558c / 3.0.6`，以下为未提交修改的开发验证，不冒充冻结 revision。
- Harmony 普通 `aa start -b com.flynes.emu -a EntryAbility` 无测试参数进入产品 Flutter 大厅；证据 `.artifacts/flutter-g2/harmony/product-g2-normal.jpeg`、`product-g2-normal-layout.json`、`product-g2-normal-semantics.txt`。main HAP SHA256 `2EEBB2B20DE50240A82D5706A15270D239093ED9F55CD076BBFF440D5C324187`，test HAP `431E79FB462B378F2B310C472075F1F15DA0AC130028DD45B267A6017B079E98`。开发模拟器替换安装，不是生产签名或真机验收。
- Harmony 最新 `hypium-second.log` 3/3，覆盖真实目录/收藏、设置/租约、暂停设置与同一游戏往返；`host-ctest.log` 16/16，受影响 Node 19/19。原生暂停→Flutter 设置保持核心暂停，返回仍为同一 RunGame 会话。
- Dart 最新全量 `flutter-tests.log` 102/102。按下 80 ms/释放 120 ms、开关 150 ms、来源行确认后 180 ms、进度 120 ms、消息出入 160 ms及成功提示3秒已补齐。新错误/动画测试先记录业务 RED 后最小修正；证据 `press-motion-*`、`switch-motion-red.log`、`source-animation-*`、`progress-animation-*`、`message-motion-*`。
- 独立审阅发现轮询清除操作错误、旧消息退出期仍可操作、删除行退出期仍有键盘焦点。已在 `notice-poll-red.log`、`outgoing-interaction-red.log` 复现，并修正为操作错误独立保留、退出消息/行立即解除指针/焦点/语义；`motion-review-green.log` 19/19。
- 12 份新增搜索 IME 逻辑截图已逐张查看；模拟 IME 避让不代替平台系统键盘截图。大字号工具栏原始像素与正常字号一致、语义树保留全部按钮；预览中重复区域未显示不能当作产品缺失。控件改动后旧 108 张截图不直接作为新金标。
- 未完成：Harmony 五项审阅修正、两端真实来源事务/联机/升级/重复往返，以及全部视觉和 Release 门禁。不能据局部测试标记 G2 完成。

## 续接：状态、真实来源与异步所有权

以下覆盖前文同名“未完成”项的历史状态，不替代最终 G2 门禁。工作树仍为 `f2c5558c / 3.0.6` 加未提交修改。

- Flutter 全量 `flutter-suite-current.log` 136/136；随后真实流程发现来源页漏订阅 sources 投影通知，`source-event-red.log` 业务失败后 `source-event-green.log` 21/21。`analyze-current.log` 无问题。尚需将这次增量纳入下一轮全量。
- 108 张固定矩阵完成首批逐张审阅和独立重采比较，固定通道容差 8 / 超差占比 0.5% / 几何 1px 的 `visual-comparison-v1/report.json` 通过。后续 V04 间距修正已独立复审 24 张大厅/搜索图，须更新受审金标并重跑比较；不沿用修正前通过结论。
- 54 张 A01–A14/A17 动画帧和 42 张状态图已采集；状态独立审阅发现目录错误误报空库、活动扫描可重复启动、窄窗口零间距、恢复可用按钮短暂低对比度，9 个业务 RED 后相关 65/65 GREEN。重采全部 108+54+42 通过；42 状态和 V04 的 24 张矩阵图复审通过。A15/A16 原生交接证据、缺项状态及伪本地化仍未完成。
- 公共 Release host 受影响 8/8 通过（`shared-affected-release-current.log`）；G2 新适配器私有头/反向依赖门禁 5/5。先前 Debug 运行目标缺失属于配置错误，日志保留，改用实际 Release 目标后通过，不记产品失败。
- Android 真实系统选择器：单文件导入 1 个内容；文件夹内单 ROM + ZIP 两 ROM 共 3 个内容；重复导入后专用只读探针核实 1 个 UUID 映射、1 条来源、3 个内容。取消选择保持列表。仅撤销本轮测试文件夹读权限，其他 grant 不变，继续验证系统重新授权。证据 `android/ui-workflow/`，ROM/ZIP 全为内置许可资源的忽略目录测试副本。
- Android 最新附近选择 worker 修正通过 15 个 JVM 所有权测试和 3 项真实 instrumentation；独立审阅未发现该片段阻断。真实重启又发现来源名称不保留及异步名称未刷新，正在按 UUID 持久保存名称；不把尚未安装的修正写成设备通过。
- Harmony 默认产品宿主、来源竞态与实际 build revision 已落地。异步 nearby 选择新增 owned ROM / retained original session / room generation，Node 33/33、host CTest 17/17、Hypium 4/4 和 debug 替换安装通过；属于 idle 真实 NAPI 工作队列验证，非双应用游玩。独立审阅发现取消完成路径退休队列异常可能越过 NAPI 回调，待修复和复审，不能标记该片段完成。
- 鸿蒙旧产品契约门禁的过期 autosave 参数、配对码/手动准备与蓝色皮肤断言已按当前批准 UX 校正；matcher 3 个业务 RED 后 5/5 GREEN，产品契约通过。自动保存关闭不阻断手动历史/head 恢复。

仍待完成：全部真实来源错误/取消和五分区/许可/布局/游戏流程、两端 20 次往返、双方向模拟器联机、完整 G1→G2 数据覆盖升级、Release 成对性能和双 ABI 包体、精确 revision 的最终工件安装。iOS 延期，G1 首卡 200ms 与 debug 内存失败保留。


### 续接：循环、语言与可见触控区域

- Android `twenty-cycles-current.log`：2 项真实 instrumentation 通过（91.666 秒），分别20次大厅/游戏与20次暂停/Flutter设置/原生布局；`twenty-cycles-owner-log.txt`记录每次所有者断言、暂停音频0、活动FlutterView1、最终已销毁宿主残留2个测试栈引用。不能替代Release GC堆增长测量。
- Android真实系统选择器流程后，移除来源确认取消保留3项；确认仅移除本次自建来源，原始ROM/ZIP SHA256不变，实际图和动作在`android/ui-workflow/source-remove-*`。其他既有来源保留。存档/用户状态完整升级矩阵仍待测。
- 中文设置字段统一为既有`zh-Hans`；Flutter-only宿主通过Android LocaleManager同步系统应用语言。暂停切语言会重建游戏的失败断言已修复，MainActivity处理locale/layoutDirection并仅刷新暂停文案；`paused-locale-green.log`3/3通过。
- 来源显示名缓存的磁盘/Provider操作均移出UI可争用锁，`source-name-io-regression-build.log`20项相关回归通过，独立审阅关闭。
- 鸿蒙nearby取消与工作项失败清理最终`nearby-cleanup-hypium-green.log`4/4、host17/17、Node33/33；早期4跑3过1失败日志保留，不用framework TestFinished值代替断言结果。
- 伪本地化18图独立审阅发现2项：真实bootstrap解析语言丢失原始system偏好、200%窄横屏标题及收藏可见区域裁切。新增`localePreference`向后兼容字段，Dart优先使用原始偏好；对应真实形状bootstrap断言先失败后34项通过。窄短大字号分类改为可横滑条，标题两行和收藏48px实际可见语义断言先失败后18图通过。独立审阅关闭两项。
- Flutter全套147/147，最新常规108图像素与已审阅v2逐字节一致；其中2图新增分类横滑语义，比较门禁如实失败，正在审阅更新语义证据。状态42图重复比较通过，未放宽8/0.5%/1px阈值。
- 随后真实Android200%发现非线性字号下原先scale(16)阈值仍保留两行与56px主操作；新非线性TextScaler测试RED，布局依据用户字号偏好比较1.8阈值（不对文字做线性缩放），54项相关GREEN与analyze通过；实际重装复验进行中。

上述仍为未提交工作树3.0.6开发证据；鸿蒙完整循环、两端完整截图/双向联机、G1覆盖升级和Release性能/最终冻结工件尚未完成。


### 鸿蒙完整循环复验与 W5 接续修正（2026-09-30）

`cycles-ui-ready-hypium.log` 最终 **5/5、Failure=0、Error=0、Ignore=0**，314.981 秒。包含真实正常 Ability→Flutter 大厅→原生游戏→暂停 Flutter 设置→同一局，以及 20 次大厅/游戏、20 次暂停/设置/布局循环。保存和放弃交替执行，断言缓存引擎身份、活动 View/核心所有者数量、暂停帧与自动保存运行计时冻结、返回后实际继续。日志 `cycles-ui-ready-hilog.log` 记录每次循环；冻结主包/测试包与哈希位于 `harmony/cycles-verified-packages`。

首轮仍有测试时序失败：点击异步启动后过早查询不存在的运行会话；此前还有只等待 Start 而错过 Continue 的驱动问题。最终测试等待真实游戏暂停控件再采样，未放宽暂停帧/计时断言。所有失败日志保留。该结果不是 Release 堆增长或物理媒体认证。

W5 独立审阅发现并修正两个缺项：操作设置增加原生已保存布局的推荐/自定义摘要；重置部分失败后重新读取真实设置及布局，不声称事务回滚。读取失败时禁用编辑，提供重新加载；部分失败的 Retry 重新打开确认并执行重置。`settings-reconcile-red.log` 与 `settings-reset-retry-red.log` 保留业务失败，最终设置 widget 9/9、OH channel 14/14。16 张改变截图已逐张独立审阅，`settings-delta-review.md/json` 记录哈希；新金标尚待冻结后重采比较。

截图工具多行语义标签缺失已用业务失败断言修正，`semantics-multiline-red/green.log`：6/6。合并标签（例如编辑布局和布局摘要）及换行 flags 均参与比较，不再仅比较空 label。像素/几何阈值保持不变。


### 原生交接与无障碍补验

Android 独立审阅发现初始化失败无法展示重试、首个raster丢失和宿主放弃/重建生命周期问题；已逐项修正。最终 `presentation-review-final-device.log` **5/5**，此前31项Dart、7项JVM和构建通过，`android-presentation-review.md`确认无剩余P1/P2。故障页实际显示中文错误/重试，重试回正确设置；过期token不放行，目标Activity销毁释放借用引用，配置重建保留交接。Release时序开销仍需测量。

24张扩展状态截图补充成功/失败封面、搜索清除/关闭、来源保护/取消/失败和恢复、自定义设置选择框、音频焦点、已应用语言、关于、窄屏200%确认和真实长许可滚动。首批已逐张审阅；选择框无障碍缺少checked状态的问题已有RED→GREEN。随后真实OH控件树发现tooltip-only图标缺名称，现共享图标/返回按钮增加显式label；4项业务RED到73项相关widget GREEN。对应最终原生重装与金标语义差异审阅仍在进行，不能以前一轮图片替代。

OH来源适配新增3个失败断言并修正：重复选择同目录复用UUID；丢失locator显示unavailable/permission_required；部分扫描保留的旧条目显示partial。`source-contract-red/green.log`最终14/14，未清理旧库或改变ROM/存档。


## 实际鸿蒙页面、无障碍和来源状态补齐

- OH任务5557普通桌面图标启动后，`ui-workflow/hall-zh-100-labelled` 实际语义树导出搜索/来源/设置/附近/收藏标签；Tooltip单独使用时这些标签为空。先4条widget失败断言，再将标签放在IconButton图标语义中，相关73项通过。共享返回按钮同样处理，不改变已批准画面。
- 独立`icon-label-review`核对192图/几何/语义；全部PNG逐字节相同，标签/选中/返回语义差异已审阅。冻结visual-v5/state-v3/pseudo-v2/extended-v1后独立重跑5个捕获runner，再严格比较108/42/18/24全部通过。金标和原始证据在ignored `.artifacts/flutter-g2`，不是自动接受新图。
- 实际OH五设置/许可与大厅zh/en×100/200共28张，`harmony-real-review.md/json`逐张打开、匹配真实树/边界后0缺项0视觉问题。屏外滚动和操作执行单列，不能靠静态图认证；系统选择器已实际打开并取消返回，取消截图保留。
- OH来源Node定向3条失败断言修正重复目录UUID、缺授权状态、部分成功投影。随后phase4取消原抛scan_failed的2条失败断言和取消后清理失败原因消失的1条失败断言，最小修正后17/17通过。旧locator落盘回滚、仅释放新授权、清理错误优先于取消状态均经独立只读审阅。
- Dart将空phase当状态而丢弃OH失败/部分成功/取消/不可用，又有4条真实契约形状失败断言；空phase现在与idle同义，来源26/26通过。错误不能被普通数量掩盖。新源码等待完整OH实际来源回归，不以Node/widget代替系统授权/真实扫描证据。
- 本次全套Flutter164/164（以上后增4项另列），静态分析5处花括号lint已修正后无问题。没有因这些中间结果宣称G2完成。


## 来源异步 I/O 与 Release 测量入口修正（待真实复核）

`HarmonyRomScan.importDocumentUris` 原使用同步 copyFile 和整文件 ArrayBuffer 回退。新路径 await 公共 mkdir/copyFile；URI scheme 不支持直接复制时，分别打开源/目标 FD，再使用异步 FD copy，嵌套 finally 关闭资源。ProductSources 与保留的原生 Sources 调用点均 await。`source-import-async-business-red.log` 实际旧实现产生两条“provider尚未完成却已settled”的业务失败断言，当前2/2通过；早期仅因禁止同步stub抛错的日志不算最终业务RED证据。取消/补偿与入口/事件相关24/24 Node通过。

OH旧G1保存夹具在普通启动已进入Flutter后切GameCenter，不能作为G2原生对照。首次WindowStage loadContent现在响应**进程内测试模块**设置的既有ProductNativeBaseline；外部Release Want仍不能开启该路径，普通Release/debug首屏仍Flutter（RED1→3/3）。Startup/NativeSave测试在进入前检查引擎缓存为空，原生结束时仍为空；候选走普通应用入口。采集器显式区分debug/release并校验实际debug位、引擎身份及各阶段完整性。

`ProductStartupObservation`只记首次单调完成时刻：native owner打开返回与目录真实读取/投影完成分开。ProductCatalog在异步准备完成前不能发布catalog-ready；独立审阅发现原生manifest fallback可能误报，已在CatalogProductService中仅真实snapshot读取/投影成功时调用onVerified，GameCenter不再无条件记录。首次读取失败、随后恢复业务RED1→相关9/9 GREEN。时间事件不是卡片可见时间的推断；仍需真实新Release采集。

完整OH debug构建 `.artifacts/oh/7d1a248b`通过，后续fallback修正另main构建通过；冻结 `.artifacts/flutter-g2/harmony/source-startup-packages/`，main SHA256 `FD1EB87C26798FFF5301D1893A60EE55E59CCBD0C44D21D6E83B7F38738B83E6`、test `E33DBFF96DA0308A3A8A1721DDFCFAC2EB6B236BFD2329CDF52D5F95B92054F3`。这份包尚待来源实际测试；不能混称此前nearby冻结包已经验证本次改动。

当前 Flutter 全套169/169、analyze无问题。搜索EditableText的Dart语义标签断言原实现已通过；OH UiTest空TextInput导出的text/hint为空是另一层观察，不伪造为Dart TDD修复。双机夹具按唯一实际TextInput定位，并保留原始树/图。


## 追加：真实来源、取消提交边界与 Release 准备

- 工作树仍是 `f2c5558c / 3.0.6` 加未提交改动，不能称最终冻结版本。
- 双向 Nearby 最终批次 `.artifacts/flutter-g2/nearby/20260930-052019`：Android host 67.518s、Harmony guest 67.831s、Harmony host 42.317s、Android guest 36.626s，四个角色测试各1/1。实际 Flutter 首/二 ROM 选择、双方输入/音频、回房间继续与同连接换游戏断言通过。独立审阅 `nearby-final-review.md/json` 已打开7张图。NAT测试中继不冒充物理热点/光学扫码证据。
- Harmony真实来源证据在 `.artifacts/flutter-g2/harmony/source-workflow`。使用许可内置测试内容，经系统保存选择器创建 `g2-source-20260930.nes/.zip`，随后普通图标启动→Flutter来源→系统文件选择器导入。ROM和ZIP共两变体、一canonical、一托管UUID，实际读取的payload hash一致。只读Hypium observer不注册来源、不注入授权、不复制ROM。
- `after-import.json` 与 `after-cancel.json` 去掉label后完全相等：重复导入、取消文件选择、取消移除没有改变目录、来源映射、内容key或用户状态。`duplicate-cancel-assertion.json`记录比较。
- 实际点击详情收藏，再确认移除来源：`retained-after-remove.json`证明库和来源登记消失，同canonical的favorite=true保留。`external-files-preserved-after-removal.png/tree.json`证明系统选择器中原始ROM和ZIP仍存在。主代理已打开审阅duplicate-file-result、remove-final-confirm、removed-source-result、external-files-preserved-after-removal四图。
- 搜索实际IME首次使用需系统输入法初始化；输入`g2-source`后，内置分类为0结果，切全部为1游戏/2版本。第一次系统返回关闭键盘保留查询，第二次关闭搜索保留大厅。截图及真实控件树保留；初始化前未聚焦时的输入尝试不算查询通过证据。
- 目录选择缺项：当前SDK API20/6.0.0.47，5557是phone API20/6.0.0.48(SP1)。FolderSelection syscap虽为true，实际选择器没有目录确认入口。本地picker声明限2-in-1；[官方当前API](https://developer.huawei.com/consumer/en/doc/harmonyos-references/js-apis-file-picker)标注Phone/Tablet26+与PC2in1 13+。本机仅有phone_all_x86镜像，不能用authMode/文件批量授权冒充目录授权，也不修改SDK或伪造deviceType。已向用户提出新增受支持手机镜像或单列缺项的选择，其他验证继续。
- 扫描提交修复：`scan-commit-business-red.log`实际复现取消的空扫描仍提交且清空旧库两断言失败。新增COMMITTING=6（原枚举值保留）和mutex内原子CommitGate；提交前取消中止，提交开始后拒绝取消。`source-commit-phase-red.log`两业务失败→Node19/19，取消状态不被轮询改回扫描/可取消，提交显示正在完成。
- 独立审阅发现新增边界下旧sourceRemove可能在commit→conflict retry之间删除成功后复活来源；`scan-remove-business-red.log`先复现拒绝断言失败，再在cancel_source相同mutex内提前拒绝COMMITTING并返回source_busy。真实executor gate-held测试覆盖拒绝移除、完成后移除与真实catalog归零；`scan-remove-green.log`host2/2通过。独立二次复核P2关闭。最新边界代码尚未安装，不能用旧包的来源成功冒充此修复设备通过。
- Android Release已准备但尚未采集：`android/release-prep/PREP.md`记录双ABI/AOT、实际non-debuggable、本地测试签名及same-package两入口方案。主包SHA256 `FA3603408D68D01AEC79920EB6EDAF9A66724A7E1185EB0E49644FF5604004F6`，测试包`92CA89E7B698AE870EBE45EF2B109DC77CB6767BD9E7D85C9C69D962A604A806`。637 JVM/0fail/2历史skip，9 Python通过；实际65秒自动保存、native-ready、5→20 ART GC及成对阈值仍待安静采集。2026-09-30为此已正常关闭两个本任务Harmony模拟器，保留userdata。

## 追加：来源实际取消、可复现金标与第二轮性能

以上“尚未安装/采集”描述保留为当时状态，以下为后续执行结果；仍不是G2整体放行。

- 最新OH debug `.artifacts/oh/d4d5fc73` 已覆盖安装。任务HVD重新启动曾分配5555；通过Emulator进程命令行 `-hvd FlyNESFlutterG1` 及TCP所有者核实身份，未操作其他用户HVD。端口不作为永久身份。
- API20手机目录能力现在明确投影为不可用，添加文件仍可用；既有syscap单独为true不再误报。2条Node业务RED→来源21/21、1条widget RED→来源27/27；完整Flutter170/170和analyze通过。真实普通启动、来源不可用说明、文件选择器三图已打开独立审阅，不能据此声称受支持系统目录重授权已验证。
- 真实来源扫描使用测试模块在应用管理目录中定向创建400个许可ZIP副本，测试不调用目录注册/扫描接口。UI实际开始扫描、取消，原始before/after JSON证明目录、来源状态/映射、内容key、收藏等状态相等；临时fixture库行仍0。再次扫描离开来源回大厅、返回来源仍观察同一应用级任务，再取消。5张实际图及语义树经独立审阅，见 `harmony/source-workflow/independent-scan-review.md/json`。400副本已定向清理，原始ROM/ZIP保留。早期错误context和无权shell复制失败日志保留，不能算通过。
- Harmony Debug host17/17；先前误用Release构建导致assert被消除后的unused警告不是本次产品回归。性能夹具异常清理新增4条业务RED→GREEN，确保启动/模式失败也写失败报告、移除观察者，设置恢复失败不能伪报完整。OH严格Release摘要8项+既有7项共15/15，要求真实AUTO、完整窗口、实际媒体进展及有效采样；尚无新的OH Release实测数据。
- 194张审阅金标移入 `ui/flutter/verification/goldens/`；保留原审阅哈希和环境，仅新增两张中英文目录能力说明。全量独立重采后 `repository-golden-check` 严格比较108/42/18/26全部通过；缺图/语义/几何差异均失败，阈值未放宽。字体脚本要求冻结SDK Roboto/Material及Android镜像CJK哈希，字体不随仓库再分发。54张受控动画帧另有原始审阅记录，不以静态金标代表原生交接动画。
- Android `release-paired-quiet-01` 原始证据独立审阅：native-ready1007>844.7ms、保存窗口108.1483>103.9547ms失败；PSS增量约66MiB通过。原生交互夹具ActivityScenario等待约6秒，后续已修正为实际绘制/lifecycle观察，旧批次不删除。memory第10次输入早于转场，旧结果不完整。
- `release-memory-quiet-02` 仅修正真实转场就绪条件，同主包20/20、GC计数和weak-marker确认后ART增长1,853,136B，旧宿主/音频线程0。`independent-review.md/json`保留原始包和数据哈希。
- `release-paired-quiet-03` 新主包 `1BA90729B74393B65F3E65BCD4FBD660A16F01FC9F9C481E939BBA188B6B7630`、test `F97B2AA0C16E3AFCCBE156D395C30F83314229D9FE71D6B20D19E193966F0196`；同一包先原生再冻结预算再Flutter。28次启动全部有效；Flutter进程后2697≤3052ms、请求后2492≤4000ms、owner-ready759≤1013ms。没有实施启动优化，不能以本批通过覆盖旧批失败或推断优化有效。
- quiet-03两组65秒实际AUTO有效，但候选保存窗口97.5791>88.7473ms仍失败，其他保存预算通过；20次往返GC后ART增长915,168B通过，Release Dart VM不可用单列。阶段诊断：Flutter上一核心帧→停止请求50.4853ms，停止→首恢复帧47.0938ms；原生对应15.5851/51.0630ms。Flutter存储29.75ms低于原生34.72ms，暂将请求相位列为定位线索，不把它当门禁豁免。全部raw数据留在该批目录，无挑样/重跑掩盖。

## 追加：原生交接真实帧与自动保存修正

- `Check-G2Visuals.ps1` 是仓库金标统一入口：运行五个capture runner，再严格比较四组194张金标。`repository-visual-gate.log`整条命令通过；它不覆盖原生页面交接验收。
- OH公开 `AVScreenCaptureRecorder` 已真实调用并操作系统录屏授权，但API20 HVD的AVC编码器初始化失败，`record-04-start-hilog.log`有 `CodecBase is nullptr`、`video/avc`初始化失败及 `Screen capture failed` code6；输出0字节，不能当成功录像。早期锁屏/授权等待超时另保留。
- 改用公开主窗口 `snapshot()`，每张保留实际请求/完成时刻，PNG逐帧保存，不冒称60fps视频。`g2-frames-pause-settings-red-01`共36帧，测试采集1/1通过但**产品视觉失败**：3.png明确是从暂停进入设置时的旧Flutter大厅。原始采样间距约120–180ms，不能排除样本之间的画面。
- 修正OH宿主握手：每attach独立token，当前lease/token/正raster帧ACK才揭开不透明遮罩，旧页面不接受触控或暴露语义；Context/Ready不依赖目录初始化，失败仍可显示Dart本地化Retry。原生设置入口通过公开window snapshot保留暂停画面，只保留一张临时PixelMap，交接/销毁即释放，不新建引擎。
- `presentation-business-red-corrected.log`业务断言失败→通道15/15通过。初次RED因fixture忘记detach旧租约报host_busy，不算有效业务RED，修正夹具后关闭新增握手路径重新复现“目录失败时无法取得目标context”的断言再恢复实现。
- `g2-frames-pause-settings-green-01`同36帧采集1/1通过，独立打开0–5帧未再见旧大厅；起始原生游戏区域本身为黑，不能据此声称所有黑闪合格。夹具已增加暂停前等待真实sourceFrames≥20，后续需重采。
- 独立审阅另发现snapshot await期间Resume竞争。`presentation-resume-race-red.log`实际方法两条成功/失败迟到断言均失败；恢复、后台、返回、hide/disappear及其它暂停命令使旧导航epoch失效，await后校验仍是原暂停上下文，catch不覆盖新状态。相关17/17通过，二审P2关闭；最新main/test已构建，实际循环复验及重装继续。
- Android AUTO修正也按最小边界实施：先停止核心捕获独立state/thumbnail及精确microsecond marker，恢复唯一音频/核心，再由原主线程串行store.put；手动/暂停保存不变。成功只确认捕获时刻进度，I/O期间新进度仍dirty；失败不更新head/parent/marker。4个JVM业务RED和设备失败用例后，643 JVM/0失败/2历史skip、HistorySession11/11、Store/Audio4/4、28Python及独立审阅通过。新工件在 `android/release-auto-resume-prep`；尚未重采性能，quiet-03保存窗口FAIL保留。

## 追加：实际像素修复与剩余状态回归

- Flutter全套192/192，analyze无问题。设置/许可PageStorageKey修正保留各独立offset；许可未缓存正文保持动画树挂载，0/60/120ms实际opacity断言通过。ProductButton保持Material子树，修复press中业务禁用时locked-tree setState，disabled语义同帧生效。动画扩大到81帧并覆盖中途返回、后台、销毁、再次选择；原54/59/80帧证据均保留，冻结前另作逐项差异审阅。
- 新增许可列表失败/恢复、部分重置权威值、重读失败禁编辑/恢复5状态图。独立审阅发现夹具误用storage_failed导致读列表错误写成保存失败；改为OH真实桥对应operation_failed并断言完整文案，重新采图。全套初轮3个扫描测试等待无限spinner导致pumpAndSettle超时；测试改为有界时钟验证真实持续加载，不改生产spinner或跳过断言。
- OH GPU分层目录 `.artifacts/flutter-g2/harmony/gpu-observation`：原3轮第2轮source/texture正常、默认framebuffer黑；多轮探针证明常量着色器可画，nearest同unit0仍黑，rebind/uniform toggle/sampler解绑无效，原纹理unit1正常。没有把GL成功计数冒充正确画面，亦没有确认驱动内部根因。诊断完整源码留ignored，产品中临时GPU读回/额外纹理及shader全部移除。
- 最小呈现unit1候选：原纹理上传/高级滤镜仍使用已有路径，最终显式绑定unit1和sampler1；没有每帧分配、复制、glFinish或SDK修改。静态独立审阅未见spatial/motion新状态冲突，高级模式硬件资格未变。
- `pixel-assertion-red-02.json`对原三轮实际系统截图产生有效FAIL（第2轮两大游戏色块均0）；`pixel-unit1-twenty.json`20轮均PASS，独立重算每个值一致并逐张打开20图。新校验器5测试覆盖真viewport、外围控件不能掩盖黑屏、红atlas、缺buffer、非法bounds。颜色存在断言是固定静止fixture回归，不能代替完整金标或物理延迟。
- `g2-frames-unit1-settings-game-02`、`g2-frames-unit1-pause-settings-01`各36张独立审阅未复现atlas或先露设置后回暂停；保留系统转场复合帧，不冒称60fps或所有连续帧。首次settings-game请求英文Back而实际为中文页，失败日志保留，第二次使用真实“返回”操作通过。
- 最新Release main SHA256 `63859C986FC0E6472C244A4FE8581DB7B2C871F47B61CD96704BF6FF904CC799`，test `ABB2318FC3FF30B21A9628180E1783354BED64F8AEB5C99A2AE3A82D9702F90C`，工作树3.0.6，非最终revision；已经兼容覆盖安装到任务HVD。host17/17、product Node68/68通过，完整Hypium和成对Release性能继续。包为HVD使用unsigned工件，不能称生产签名。
- 启动采集端口保护不再仅凭5555识别用户设备：默认仍拒绝，显式任务PID需同时匹配Emulator.exe、白名单任务HVD名称和该loopback端口拥有者，7项正反断言通过；真实本轮为FlyNESFlutterG1/PID61040/5555，原用户HVD不操作。
