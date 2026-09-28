# HarmonyOS 2.1.2 → 3.0.3 覆盖安装验证

2026-09-29，独立 API 20 / HarmonyOS 6.0.0.48 x86_64 手机 HVD：**通过**。这是旧版原生应用到当前 Flutter foundation 宿主的实际覆盖安装，不是同版本重装或修改新版版本号的替代实验。

## 隔离、版本与包

- 新建 `FlyNESUpgrade212`，配置位于本机 Emulator `deployed/FlyNESUpgrade212`。只复用任务配置模板并生成新 UUID；不复制任何已有 userdata、qcow2 或快照。设备实际监听 `127.0.0.1:5559`，PID 61052。
- 未操作用户 5555 或其他任务 5557；未卸载应用、清数据、降级或修改版本。升级后 userdata 与 HVD 保留。验证结束后停止构建和设备操作，将测量窗口交回主任务。
- 旧源为 ignored `.artifacts/n21`，revision `3a2dc4265625a7bd149ff69b8fa6e34e65c8b1cc`，`2.1.2 / 2001002`。没有 Flutter。旧导出只增加 `SaveHistoryUpgrade.test.ets` 与 `List.test.ets` 测试分流，生产源码保持原版。事后逐一检查 `harmony/entry/src/main`、`core`、`shared`、`libs` 的 **945 个 Git blob，0 缺失、0 不匹配**（允许 checkout CRLF 规范化）。许可资源由旧导出的内容同步脚本生成。
- 新版安装后 `bm dump -n com.flynes.emu` 确认 `3.0.3 / 3000003`，bundle 均为 `com.flynes.emu`。主包是已完成 Foundation 9/9 回归的固定副本；测试包包含最终升级夹具与独立性能 opt-in harness，本次未运行性能测量。
- 两代均为本地 **unsigned debug HAP**，此 API 20 HVD 实际接受安装。这个结果不证明生产签名连续性、商店升级或真机可安装性；没有读取或输出签名材料。

SHA-256：

| 版本 | 产物 | SHA-256 |
|---|---|---|
| 2.1.2 | main | `E0CCB477FDF6741277A9CDCE60ABBBD8CF170B068EE577F1F68071C7323CAC89` |
| 2.1.2 | test | `D03E61ABF4BE9CA7C5B3A73795C40B59890199A53CD1D6C12227F03330C40D0C` |
| 3.0.3 | main | `FC1694F3C48CE0E0D2F5E84BCD1D3425FE7D568DEC70B881625D1F6EA8470FD2` |
| 3.0.3 | test | `BCD45AA43E67DE5F897E46907F8EA1C4520558EC4857F57219F205C2B15BD6F4` |

## 实际路径和断言

1. 将旧 main/test 放入一个包目录，一次 `hdc -t 127.0.0.1:5559 install -r <old-packages>` 安装。记录安装版本。
2. `prepare` 夹具从共享许可 manifest 选择 ROM，添加隔离标记，经真实系统 `DocumentSavePicker` 保存到 Download/`upgrade212.nes`。它不直接写入管理目录、不插入来源、不制造权限。
3. 在旧版产品 UI 点击来源 → 添加游戏，真实系统 **FILE picker**：浏览 → 我的手机 → Download → `upgrade212.nes`。旧产品显示 `Imported 1 game file(s)`、来源 `roms`、`1 个游戏 · ready`。保留系统选择器布局、截图和导入完成布局。
4. 旧版 `seed / cross212 / saveHistoryUpgradeProduct=true` **1/1 PASS，3.054 s**。产品夹具使用真实 EntryAbility context，避免 TestAbility 模块目录冒充生产存储。
5. 同一正确生产 context 对从未建立的 `absent212` 执行 verify，按预期因缺少证据文件失败，证明验证不会自动创建种子或静默通过。
6. 将固定新版 main/test 放入一个新目录，一次 `install -r <new-packages>` 覆盖，避免两个模块短暂混用版本。安装成功，版本核验为 3.0.3。
7. 新版 `verify / cross212 / saveHistoryUpgradeProduct=true` **1/1 PASS，2.739 s**。

通过的真实生产数据断言：

- `save_history` preferences 的 `intervalMs=30000`，而且通过 `PlayService.open()` 验证 `history.intervalMs` 为 30000；不是只检查一条孤立偏好。
- 导入游戏的收藏和 `lastPlayedSequence` 不变。
- 完整 `settingsGet()` JSON 不变；种子显式设方形像素、音频关闭、触觉关闭和英文。设置经 `settingsApply()` 正式接口持久化。
- `controlLayoutGet()` 编码完全不变；种子经正式布局接口把 opacity 改为 0.73。
- 来源 preferences `source_map_v1`、source UUID、规范游戏 ID、相对路径、包格式及 catalog locator 保留。
- `PlayService.readRom()` 实际重新打开管理目录的导入 ROM，内容 key 不变；`PlayService.open()` 实际启动核心，`sourceFrames > 0`。
- 正式 `filesDir/save-history.db` 中非最新 head、历史列表、标签和 pin、playedMs 保留；存档与缩略图逐字节不变。损坏旧槽不会覆盖有效新 head。
- 未完成操作升级后恢复到备份，playedMs=9876；恢复再次查询为 0。保留旧槽仅在无新 head 时导入，且原始旧槽字节仍在。

手机 FILE picker 的正式实现会将文件复制到 `filesDir/roms`，然后以 managed source 记录。这证明系统选取和管理目录保留，**不等同于 Android SAF 外部目录授权保留**；没有将不支持的 folder 权限路径伪造成已测能力。

## 复现命令与证据

旧源先运行其 `tools/content/sync-builtin-content.ps1 -Root <n21>`、DevEco `ohpm install --all`，再用 DevEco Node 执行原生 `hvigorw.js`：

```powershell
# cwd: .artifacts/n21/harmony; DEVECO_SDK_HOME points to installed DevEco SDK
& $Node $Hvigor --mode module -p product=default -p buildMode=debug assembleHap --no-daemon
& $Node $Hvigor --mode module -p product=default -p module=entry@ohosTest -p buildMode=debug assembleHap --no-daemon

& $Hdc -t 127.0.0.1:5559 install -r $OldPackageDirectory
& $Hdc -t 127.0.0.1:5559 shell aa test -b com.flynes.emu -m entry_test `
  -s unittest OpenHarmonyTestRunner -s saveHistoryUpgradePhase prepare `
  -s saveHistoryUpgradeFixture cross212 -s timeout 120000
# Complete real system save dialog, then use product Sources FILE picker.
& $Hdc -t 127.0.0.1:5559 shell aa test -b com.flynes.emu -m entry_test `
  -s unittest OpenHarmonyTestRunner -s saveHistoryUpgradePhase seed `
  -s saveHistoryUpgradeFixture cross212 -s saveHistoryUpgradeProduct true -s timeout 120000
& $Hdc -t 127.0.0.1:5559 install -r $NewPackageDirectory
& $Hdc -t 127.0.0.1:5559 shell aa test -b com.flynes.emu -m entry_test `
  -s unittest OpenHarmonyTestRunner -s saveHistoryUpgradePhase verify `
  -s saveHistoryUpgradeFixture cross212 -s saveHistoryUpgradeProduct true -s timeout 120000
```

Existing fixture names are deliberately non-overwritable. Use a fresh name and freshly imported fixture for a separate run; never clear this HVD to make a rerun pass.

Ignored evidence root: `.artifacts/flutter-g0/harmony-upgrade212/`:

- `old-production-source-verification.json`, old/new package hashes and fixed package directories.
- Old build logs, `old-installed.json`, `new-installed.json`, `upgrade-install.log`.
- `save-picker.jpeg`, `picker-file-visible.json`, `old-imported.json`.
- `old-seed-final.log`, `old-red-production-path.log`, `new-verify.log` and matching seed/verify hilog evidence.

Earlier fixture setup failures are retained: application-only context was invalid for preferences, module context could not see the UI import, and haptic enum 0 was rejected. These were test harness corrections (actual EntryAbility context and valid `FLY_HAPTIC_OFF=1`), with no production fix. The first save-picker attempt raced EntryAbility startup; the fixture now waits for its UI context. No app data was cleared during those corrections.
