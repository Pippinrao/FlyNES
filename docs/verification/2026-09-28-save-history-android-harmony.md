# 独立存档库与 Android / HarmonyOS 验证

日期：2026-09-28。分支：`codex/save-history`；基线：`main@78057350`；隔离 worktree：`.worktrees/save-history`。分配版本为 2.1.0，后续提交 PATCH 由仓库 hook 自动维护。未发布。用户已要求验证完成后合并到 main 并删除该 worktree。

## 本轮交付

- `libs/save_history` 是可独立构建、安装并由 C/C++ 消费的库，平台和模拟器不属于它的依赖。SQLite 3.53.4 固定源码作为私有实现；不需要数据库服务器。库自身采用仓库 GPLv2，SQLite 为 public domain。
- 存档为不透明状态与缩略图，带内容身份、格式、时间、类型、备注、保留标记和当前恢复点。支持原子写入、事务配额清理、损坏校验、回退保护以及中断操作原子恢复。
- Android 与 HarmonyOS 接入按实际模拟运行时间自动保存、手动保存、预览、恢复、备注、保留、删除和从头开始。默认一分钟，可选 30 秒、1 / 2 / 5 分钟或关闭；暂停与后台不累计时间。
- 恢复与重开先保存保护副本；失败保持暂停且保留恢复点。重开保留游戏 SRAM，并刷新画面、输入、PCM 和运动插帧队列。
- 旧版文件在首次迁移后保留；已经有新库恢复点时，不再读取旧文件，旧文件损坏不会阻挡新存档恢复。
- 用户最新要求已覆盖最初设计：**游戏中心删除“存档记录”“从头开始”两个按钮，只保留开始 / 继续主按钮。两个功能仅在游戏内暂停菜单提供。** 继续标签按实际保存的恢复点判定。
- 未加入通用关卡识别；没有可靠的跨 ROM 关卡事件。游戏内部菜单或暂停若仍在模拟帧中运行，仍可能累计时间。

## TDD 与审查

所有主要行为先记录实际失败断言再实现。原始证据在 worktree 的 `.artifacts/`；清理前日志和截图复制到主仓库忽略目录 `.artifacts/save-history-verification/`，以下路径相对此归档目录：

| 行为 | 红灯证据 | 绿灯证据 |
| --- | --- | --- |
| 独立库打开、存取、保留、配额、回退 | `save-history-host/red-*.log` | `final-library-host.log` |
| 恢复提交失败仍保留重试意图 | `save-history-host/red-recovery.log` | `save-history-host/green-recovery.log` |
| Android 时钟、JNI、真实核心与菜单 | `android-save-*-red*.log` / `android-history-*.log` | `final-android-instrumentation.log` |
| Android 损坏内核状态回滚 | `android-save-review-red.log` | `android-save-review-green-tests.log` |
| Harmony 存储、回退、自动保存 | `harmony-history-red.log`、`save-history-env/harmony-play-fixture-red.log` | `harmony-legacy-head-green.log` |
| 非法类型、失败后暂停、暂停瞬间计时 | `save-history-env/harmony-recover-review-red.log` | `final-harmony-history.log` |
| 回退后的画面与运动队列刷新 | `save-history-env/native-runtime-red.log`、`native-motion-red.log` | `save-history-env/cold-restart-full-green.log` |
| 重开保留 SRAM / 音频时钟重新起算 | `save-history-env/cold-restart-*-red.log` | `save-history-env/cold-restart-full-green.log` |
| 删除游戏中心两个按钮 | `home-buttons-android-red.log`、`home-buttons-harmony-red.log` | `home-buttons-android-green.log`、`final-harmony-ui.log` |
| 已迁移时不再读取旧文件 | `harmony-legacy-head-red2.log` | `harmony-legacy-head-green.log` |

独立审查已处理：原子恢复缺口、启动失败后误写新 head、失败恢复自动继续、回退帧序号导致画面停滞、旧运动帧混用、重开覆盖 SRAM、UI 确认时底层可点击，以及自动保存失败导致 UI 轮询停止。UI 测试等待面板销毁后再点击暂停菜单，避免异步页面切换时误点。最后审查未发现剩余阻塞项。

## 实际结果

| 检查 | 结果 |
| --- | --- |
| 独立库 MSVC CTest | 11 / 11 |
| 安装后独立 C 与 C++ `find_package` 消费者 | 2 / 2 |
| Harmony Windows host CTest | 15 / 15 |
| Harmony Linux 原生音频、渲染、回退、冷重置相关 CTest | 24 / 24 |
| Android 单元测试 | 573 项，0 失败 / 错误，2 项既有跳过 |
| Android 存档 + 原有暂停模拟器回归 | 12 / 12 |
| Android 删除首页按钮后界面回归 | 3 / 3 |
| Harmony 模拟器存档服务 / NAPI | 9 / 9 |
| Harmony 模拟器完整 UI 流程 | 1 / 1 |
| Harmony 原有 Smoke / PauseParams / CheckpointStore / SettingsHelpers / 一个内置游戏操作回归 | 13 / 13 |
| 内容唯一真源门禁 | 7 游戏通过 |

模拟器：全新隔离 Android API 35（`emulator-5580`）与 HarmonyOS API 20（`127.0.0.1:5555`），未使用原有模拟器数据。Android 使用调试签名；Harmony HVD 接受未签名测试 HAP。没有连接可用于本轮签名安装验证的实体设备，没有把测试签名称为商店签名。

安装、测试和截图按上述目录归档，未提交包或私人 ROM。UI 图：`android-save-home.png`、`android-save-menu.png`、`android-save-history.png`、`harmony-history-home.png`、`harmony-history-menu.png`、`harmony-history-panel.png`。

## 范围限制

- 用户明确先做安卓、鸿蒙；iOS 未接入，原始 iPhone 通关画面仍需后续 Mac / iPhone 验收。
- 没有云同步、加密或跨平台存档转换；Android NES state 与 Harmony runtime checkpoint 使用不同格式隔离。
- 默认 60 条普通自动记录、每内容 256 MiB / 总计 1 GiB 为 payload 配额，不包含 SQLite 页、索引与事务日志开销；重要记录需手动保留。
- 电池 SRAM 由自制测试 ROM 验证；未据此宣称所有 EEPROM / FDS 持久化介质或实体硬件功耗、温度、延迟均已验证。
- 系统强杀前未给应用执行时间时，不能保证保存最后一帧；依靠上一自动点和事务完整性恢复。
