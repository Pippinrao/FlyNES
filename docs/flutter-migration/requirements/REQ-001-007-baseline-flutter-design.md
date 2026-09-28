# 8.1 基线与 Flutter 前置验证设计

日期：2026-09-28。状态：用户批准实施；阶段验收见 STATUS 和 verification。
需求：REQ-001～007；上位范围：[roadmap](../roadmap.md)。

## 1. 基线与范围

- 原生产品基线：`main@3a2dc426` / 2.1.2，含 `0c11750c` 存档交付。
- Flutter 工作区：`codex/flutter-foundation`，基础提交 `3b4fb0fd`，主干合并 `08eb6823`；版本保持 3.0.x，正常 hook 递增 PATCH。
- 本阶段冻结 UX、生产调用图、数据格式、工具链和性能口径；交付同源码真实目录→原生游戏→返回的三端闭环。
- 保留现有宿主、暂停/手柄、设置、来源、联机和历史原生页面。完整外围迁移归 G2；公共保存编排和 iOS 历史接入归 G3。
- 没有默认批准性能超标；原版测量及数值预算须在 Flutter 候选测量前确认。缺真机、Mac、签名或 SDK 不计为通过。

## 2. UX 权威与差异

优先级：本次批准→后续已批准产品修订→原始设计→平台实现参考。不可把实现缺陷变成新规范。

| 领域 | 权威设计 | 当前参考与迁移契约 |
| --- | --- | --- |
| 产品导航与视觉 | 2026-08-21 productization-alpha，2026-09-05 cross-platform-android-product-parity | 冷启动到游戏中心；暂停与 NES START 分离；设置分区为显示、操作、音频、游戏语言、关于 |
| 游戏库 | 2026-08-24 game-center-continuous-library，2026-09-12 ios-library-stability | HomeActivity / CatalogLibraryView：左详情约30%、右列表70%；两行横向连续滚动；点击选中，主按钮启动 |
| 可访问性 | HomeHeaderLayoutPolicy 与两端实际布局 | 字号达到1.8或伪本地化压缩条件时一行列表；详情标题普通一行、高字号两行；普通主按钮56、高字号88；最小触点48 |
| 标题与封面 | 连续游戏库设计、现有 CatalogPresentation | 本地化主次标题；文件名仅搜索/诊断；现有截图保持比例，无图标题占位；不硬编码内置内容 |
| 存档 | 已合入存档设计与用户最新菜单修订 | 大厅仅开始/继续；暂停内历史、手动保存、从头开始、保存间隔；继续取真实恢复能力 |
| 联机 | docs/nearby/README，2026-09-23 three-platform-ux 及09-27 room-resume | QR入空房间→房主选游戏→匹配自动开局；回房间暂停保留局；明确继续；显式断开；同连接换游戏 |

Android 深色 token：background #121316，surface #1B1D22，selected #292B31，text #F4EFE6，muted #BEB8AE，primary #FF6B5E。
间距4/8/12/16/24/32，圆角12/16/24。独立定义选中、按压、加载、禁用、错误；不继承骨架浅色 Material 示例作为产品规范。
验证中英文、100%/200%字号、短横屏/宽横屏和安全区。游戏库允许横向滚动；附近页面遵循既有无应用内四向滚动设计。

已知差异单列：iOS系统色不作为统一默认；iOS尚无新历史库；旧源码以lastPlayed决定继续标签不满足新契约；G1客户端不得照抄该判断。
四分类/搜索/收藏的完整 Flutter 页面留G2；G1至少真实目录、详情、选择、能力投影与启动，其他操作进入现有原生页面。

## 3. 生产链与所有权

| 路径 | 当前生产链 | 生命周期/线程/数据所有者 |
| --- | --- | --- |
| Android目录/启动 | FlyNesApplication → AndroidCatalogRuntime / AndroidGameLaunchService → FlyNesApp JNI → fly_app | 应用持有目录；后台构建快照、实际启动重验ROM；Home只持导航投影 |
| Android单机 | MainActivity → EmulationSession / AudioThread → NesCore → nes_* | AudioThread为运行采样链；暂停先停核心执行；HistorySession在静止核心上捕获；不是fly_runtime路径 |
| iOS目录/单机 | CatalogLibraryView → FlyNesAppBridge；RunGameContainer → RunSurfaceViewController → FlyNesRuntimeBridge → fly_runtime_* | app桥持目录；游戏控制器拥有运行/Metal/音频；checkpoint主线程串行边界；旧Documents/saves存档 |
| Harmony目录/单机 | GameCenter → CatalogProductService / PlayService → N-API → PlaySession / NativePlayRuntime → fly_runtime_* | 原生调度器运行；ArkTS服务编排保存；OHAudio/renderer管理设备资源 |
| 三端联机 | 应用级Nearby owner/bridge → fly_lan_mvp_* → runtime + Rust QUIC | 连接与页面分离；现有原生游戏消费视频PCM；返回页面不能关闭会话或释放热点 |
| 新存档 | HistorySession / SaveHistoryService → JNI/N-API → sh_* → 私有SQLite | 库无核心、线程或自动时钟；上层串行调用。G1不另造SaveCoordinator |

目标只增加Flutter呈现与窄客户端；不切换Android核心驱动，不改网络协议，不移动媒体时钟，不更换数据身份。

## 4. 持久化契约与接续

| 数据 | 保留契约 |
| --- | --- |
| 内容身份与授权 | catalog canonical ID不变；Android SAF、iOS bookmark、Harmony文件授权仍由各端保存；不可由Flutter猜物理路径 |
| 目录/收藏/设置/布局 | 原fly_app和已有平台持久化保留；Dart只持不可变投影与临时导航状态 |
| Android新历史 | files/save-history.sqlite，format=nes-state-v1；key为核心RomIdentity.sha1（PRG+CHR），不同于目录整文件payload SHA1；适配器经既有内容授权/哈希校验后读取核心身份，缓存按payload SHA256区分 |
| Harmony新历史 | files/save-history.db，format=fly-runtime-checkpoint-v1，key沿用historyContentKey(ROM) |
| 旧档 | Android saves/<identity>/autosave.nst与battery.sav；Harmony checkpointKey；iOS Documents/saves/<safe canonical ID>/autosave.nst；同名不代表格式兼容 |
| 独立库 | C++17/C ABI；user_version=1；SQLite私有；借用输入、回调范围内字符串、调用者读缓冲；同句柄串行，回调不重入 |
| head/恢复 | sh_get_head为继续权威；prepare/finish/cancel/recover/pending沿现有幂等语义；不按created_ms猜head |
| 配额/时钟 | 默认60条普通自动档，256MiB/内容、1GiB总payload；默认60秒，可30秒/1/2/5分钟/关；暂停后台不累计 |
| 重开 | 先保护当前head，重开保留SRAM，成功提交新head；复用fly_runtime_restart及Android现有接线；清除旧输入、PCM与画面 |

旧文件仅在没有新head时惰性读取，迁移成功仍保留原文件。数据库不打开第二套“Flutter存档”。
本期需定向复现：Android pending恢复cancel→setHead之间的中断窗口；有效新head被提前读取失败的旧档阻断。修复复用已有recover/惰性加载，不改库schema。
恢复失败保持暂停；内存、head、pending和保护点一致；未完成操作不得因页面退出假装取消。

## 5. 最小客户端、宿主与容器

客户端边界：不可变CatalogSnapshot(generation/条目/来源状态/封面引用)、ResumeCapability(查询中/有进度/无进度/不可用+原因)、canonical ID启动、原生页面打开/结果、返回刷新、容器生命周期/小型输入。
canonical ID到存档key由既有适配器解析。异步携带operation/subscription/session generation；旧结果丢弃；重复启动串行化。
公共查询优先FFI；系统页面走窄桥；复用同一应用实例。耗时工作不阻塞Dart UI isolate；工作线程不能直接操作Dart对象；释放快照、取消订阅可测。

- Android：现有Gradle宿主嵌入module，应用级engine，游戏仍MainActivity。
- iOS：现有CMake/Xcode宿主，当前SDK的XCFramework构建方式优先，游戏仍原控制器；Mac上构建/安装/测试。
- Harmony：现有Stage应用嵌入维护方Flutter-OH；先锁定兼容Dart/engine/DevEco/API20再实现；不永久另留一套完整产品UI。
- SDK候选：当前上游3.41.7/Dart3.11.5；OH发行必须以实际maintainer提交锁定。G1用SDK自带导航/通知，无新SQL/路由/扫码框架。
- 包身份保持Android/Harmony com.flynes.emu、iOS com.flynes.app；VERSION唯一版本源；生成宿主不是生产权威。
- 容器先texture，再在其不能满足媒体/生命周期/输入要求时验证native view。至少各端一种有连续真实音视频、多指/取消、前后台、20次附着释放证据。
- 帧/PCM不经Dart搬运；Widget释放不销毁核心、连接或热点。G1容器实验不替换生产手柄。

09-29实施选择：OH `3.41.10-ohos-1.0.0`（commit `244a0e8abb3085e8675589b13e219af8c41cb7aa`）通过 API20 HAR 与真实宿主编译；1.0.1 已复现编译 SDK 不兼容。具体 engine/HAR pin、安装与未测项见[工具链记录](../verification/2026-09-29-ohos-toolchain.md)。这仍是 G1 候选，不能用 API20 编译推断 API12 运行兼容。

REQ-005 通过 `flynes/foundation` 窄方法桥复用现有 N-API owner，避免在验证页新开一套 C++ 应用实例；[具体客户端契约](../../../ui/flutter/lib/native_client/README.md)固定参数、结果与序号语义。generation 是进程内投影响应序号，不冒充原生目录 revision。09-29 后续已补只读本地封面和同路径截图刷新；两端恢复/启动/原生页面返回及容器按真实模拟器断言逐项记录，当前结果见STATUS，不能仅凭接口存在计作闭环完成。

## 6. 性能与验收

原版与Flutter候选采用相同底层revision、设备、构建模式、ROM、历史规模和保存间隔。
分别记录首交互、完整目录可用、native就绪；内存/包体/往返残留；输入到采样/呈现、帧节奏、音频欠载；自动保存停帧与响应。
历史170ms是debug+speed AOT、首批卡片口径，不能视为新完整列表基线。保留既有200ms门槛的真实语义；新增指标先原版数据→数值预算确认→候选测量。
启动至少10次、逐次值与nearest-rank P95；debug软件测量不能认证物理延迟、温度、功耗。不得关闭自动保存来达标。

升级矩阵：2.0旧档→迁移版→Flutter；2.1.2新历史→Flutter；新head+坏旧档；pending恢复；iOS旧档；目录/收藏/设置/布局/授权。兼容签名覆盖安装，禁止卸载清数据；真实重新读取来源并加载存档。
双机最小矩阵：Android房主+Harmony客机，真实QR、同ROM、双方输入、回房间暂停、继续同进度、同连接换游戏；全部方向属后续验收。
Android变更：host+unit+相关instrumentation；Harmony：host+Hypium，有兼容真机则签名安装；iOS：Mac runtime/UI。用许可内容和隔离测试数据。
报告关联REQ/revision/SDK/构建/设备/命令/断言，状态passed/failed/blocked/not-run明确。
G1通过要求三端真实闭环、数据授权保留、容器可行、含OH双机可玩、命令可复现和预算全部达标。缺任何一项保持部分完成。

## 7. 可追溯的冻结入口

以下链接相对本文件；设计决定目标，源码证明当前状态。后续变更须更新差异记录，而不是悄悄把当前实现当成设计。

| 基线 | 可审阅来源 |
| --- | --- |
| 原始产品 UX | [productization-alpha](../../superpowers/specs/2026-08-21-flynes-productization-alpha-design.md)、[连续游戏库](../../superpowers/specs/2026-08-24-game-center-continuous-library-design.md) |
| 后续跨端/大字号修订 | [Android parity](../../superpowers/specs/2026-09-05-cross-platform-android-product-parity-design.md)、[iOS library stability](../../superpowers/specs/2026-09-12-ios-library-stability-design.md) |
| 当前联机权威入口 | [nearby README](../../nearby/README.md)、[房间继续游戏](../../superpowers/specs/2026-09-27-nearby-room-resume-design.md) |
| 已交付历史库 | [C ABI](../../../libs/save_history/include/save_history/save_history.h)、[库 README](../../../libs/save_history/README.md)、[合入时验证](../../verification/2026-09-28-save-history-android-harmony.md) |
| Android 视觉/布局 | [颜色](../../../app/src/main/res/values/colors.xml)、[布局策略](../../../app/src/main/java/com/flynes/emu/gamecenter/HomeHeaderLayoutPolicy.java)、[大厅](../../../app/src/main/java/com/flynes/emu/HomeActivity.java) |
| Android 保存所有者 | [HistorySession](../../../app/src/main/java/com/flynes/emu/save/HistorySession.java)、[MainActivity](../../../app/src/main/java/com/flynes/emu/MainActivity.java) |
| Harmony 保存/身份 | [SaveHistoryService](../../../harmony/entry/src/main/ets/service/SaveHistoryService.ets)、[PlayService](../../../harmony/entry/src/main/ets/service/PlayService.ets)、[GameCenter](../../../harmony/entry/src/main/ets/pages/GameCenter.ets) |
| iOS 原生目录/旧档 | [CatalogLibraryView](../../../ios/app/CatalogLibraryView.swift)、[RunSurfaceViewController](../../../ios/app/run/RunSurfaceViewController.mm) |

本轮接续验证发现 Harmony 恢复失败分支调用 historyFinish(false) 后，head 与回滚内存不一致。已通过真实核心/SQLite RED→GREEN 将该分支改用原子 historyRecover，Hypium 9/9、UI1/1、host15/15；[证据](../verification/2026-09-29-harmony-save-handoff.md)同时记录同版本覆盖安装保留测试。此结论不扩大为跨版本授权保留、iOS或G1整体验收。
