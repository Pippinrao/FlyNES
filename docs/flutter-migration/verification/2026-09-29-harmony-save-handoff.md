# Harmony 存档失败恢复与覆盖安装验证

日期：2026-09-29。REQ-002 / REQ-007 定向验证。分支 `codex/flutter-foundation`，执行基线为3.0.3工作区；本记录只覆盖存档子项，不放行G1。

## 恢复失败一致性

原实现 `SaveHistoryService.restore()` 在目标解码失败后恢复当前内存，再调用 `historyFinish(false)`。该N-API调用的是 `sh_cancel_restore`，只清除pending并保持旧head。如果用户在旧head之后继续玩过，退出重开会回到旧进度，与已回滚的当前内存不一致。

修复只将该调用替换为已有 `historyRecover(path,key)`：先回滚内存，再通过库事务同时发布保护点head并完成pending。如果内存回滚或恢复提交失败，后续步骤不执行、保持暂停与持久pending证据。不改变schema、ABI或版本。

真实Hypium测试使用manifest中第一个许可ROM，保存旧head后运行核心300ms，注入SQLite中CRC有效但核心不能解码的三字节目标。断言失败后暂停、内存仍保留新进度、head等于保护点、pending已完成、重开恢复相同帧与playedMs且允许后续保存。测试调用真实N-API与SQLite，无持久层mock。

| 检查 | 实际结果 | 证据（相对 `.artifacts/flutter-g0/harmony-save/`） |
| --- | --- | --- |
| RED，未修复服务+增强测试 | 9项，8通过/1失败；`expect 1 equals 3`，旧head1≠保护点3 | `red-hypium-current.log` |
| GREEN，原子recover修复 | 9项全通过 | `green-hypium.log` |
| 最终增强测试重跑（允许暂停前最后一帧正常前进） | 9项全通过 | `final-hypium.log` |
| 原生暂停→手动保存→历史预览→安全重开→大厅 | 1/1通过 | `final-ui.log` |
| Harmony host CTest Debug | 15/15通过 | `host-ctest.log` |

第一次测试包安装因5557旧主包3.0.2与新测试包3.0.3不匹配失败。其后执行的旧9/9测试**不是RED证据**（`red-install.log`、`red-hypium.log`）。增量构建当前3.0.3主包后，使用 `install -r` 依次替换主包、测试包，再得到上述真实RED。没有卸载或清数据。

环境：DevEco6.0/API20、固定Flutter-OH1.0.0依赖、任务专用x64 HVD `127.0.0.1:5557`。5555未使用。unsigned HAP由模拟器接受，不代表实体设备签名安装。

## 两阶段覆盖安装夹具

`SaveHistoryUpgrade.test.ets` 已执行通过。使用生产 `files/save-history.db` 与 `CheckpointStore(filesDir)`；在许可ROM尾部追加夹具标记，由真实 `historyContentKey` 得到隔离内容身份，并要求真实核心成功打开。未触碰已有内容数据。只给该测试的canonical ID写旧档，JSON sidecar仅保存预期值。

通过断言：较旧的选定head（不是最新行）、手动/自动/保护记录、label/pinned/playedMs/parent/session/createdMs、state和thumbnail逐字节保留；损坏旧档不能阻挡有效新head（旧档回调若被调用立即抛错）；真实pending跨安装后恢复保护点与playedMs9876且后续recover返回0；仅旧档时惰性迁移且原文件逐字节保留。

实际顺序为 seed 1/1通过 → force-stop → 主包 `install -r` 成功 → 测试包 `install -r` 成功 → verify 1/1通过。夹具名 `g1-20260929-a`，两次测试是不同进程。证据为 `upgrade-seed.log`、`upgrade-force-stop.log`、`upgrade-replace-main.log`、`upgrade-replace-test.log`、`upgrade-verify.log`，构建日志为 `upgrade-build.log`，安装包SHA256为 `package-hashes.json`。当前主包包含同时验证的OH独立UI线程修复。

这是**同版本3.0.3包替换保留测试**，不是2.1.2→3.0版本矩阵，也不是实体设备签名验收。夹具可用新名称再次seed；verify支持重复运行，迁移后不重复读旧档。未卸载、清应用数据或删除旧文件。

可复跑命令（当前工作区根目录，先按DEVELOPMENT构建主/测试HAP）：

```powershell
$hdc = 'D:/soft/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe'
$fixture = 'g1-unique-new-name' # 每次seed使用新名称
& $hdc -t 127.0.0.1:5557 install -r harmony/entry/build/default/outputs/ohosTest/entry-ohosTest-unsigned.hap
& $hdc -t 127.0.0.1:5557 shell aa test -b com.flynes.emu -m entry_test -s unittest OpenHarmonyTestRunner -s saveHistoryUpgradePhase seed -s saveHistoryUpgradeFixture $fixture -s timeout 30000
& $hdc -t 127.0.0.1:5557 shell aa force-stop com.flynes.emu
& $hdc -t 127.0.0.1:5557 install -r harmony/entry/build/default/outputs/default/entry-default-unsigned.hap
& $hdc -t 127.0.0.1:5557 install -r harmony/entry/build/default/outputs/ohosTest/entry-ohosTest-unsigned.hap
& $hdc -t 127.0.0.1:5557 shell aa test -b com.flynes.emu -m entry_test -s unittest OpenHarmonyTestRunner -s saveHistoryUpgradePhase verify -s saveHistoryUpgradeFixture $fixture -s timeout 30000
& $hdc -t 127.0.0.1:5557 shell aa test -b com.flynes.emu -m entry_test -s unittest OpenHarmonyTestRunner -s saveHistoryOnly true -s timeout 30000
```

检查 `install bundle successfully` 和Hypium实际 `Tests run / Failure / Error / Pass`，不能仅使用hdc进程exit0。

## 边界

无兼容实体设备连接，未做signed-device安装。未证明真实设备延迟、功耗或温度。未注入Harmony运行时的磁盘COMMIT/内存回滚二次失败；库层相关事务失败/进程终止已有独立测试，此处不冒充平台注入证据。目录数据库、文件授权、设置等非存档升级矩阵仍需独立验收。Mac按用户要求未验证。
