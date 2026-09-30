# G2 HarmonyOS G1→G2 覆盖升级

2026-09-30，独立任务 HVD `FlyNESUpgrade212`：G1 **3.0.3 / 3000003 → G2 3.0.6 / 3000006** 覆盖验证通过。iOS 与真机不在本证据范围。

## 环境与工件

复用之前 2.1.2→3.0.3 验证后保留的 HVD 和 userdata。此次启动进程 49828 的命令明确指定 `FlyNESUpgrade212`，实际分配监听端口 **5555**（此前该 HVD 使用5559）；通过进程端口及安装版本核对后使用 `127.0.0.1:5555`，不是接管未知设备。任务循环设备5557不参与本次升级。

G1 为原已安装的冻结3.0.3，参见[原跨版本报告](2026-09-29-harmony-cross-version-upgrade.md)。G2 主包来自已通过循环测试的冻结副本；它早于后续布局摘要/交接错误路径修正，因此这是数据迁移子项证据，最终工件仍须冻结验证。

| G2 工件 | SHA-256 |
|---|---|
| entry-default-unsigned.hap | 200dbcab5e8dc52a03205b096fc0fca0c60371c497a7191cf9028feb47384e1e |
| entry-ohosTest-unsigned.hap | 73429b5e52292539b40032057072ea3781743b40301f94bd15618bb791f90f1f |

均为此 HVD 接受的 **本地 unsigned debug HAP**，不是生产签名或真机安装证明。副本及哈希保存在 `.artifacts/flutter-g2/harmony/cycles-verified-packages/`；实际安装目录 `upgrade-install-packages/` 仅含两个 HAP。

## 操作与结果

1. 读取 G1 安装信息；未卸载、清数据、重新导入或降低版本。
2. G1 在真实 EntryAbility context 运行 `SaveHistoryUpgrade` seed，fixture=`g2-20260930-ready`，**1/1 PASS，2.590秒**。沿用此前通过真实系统文件选择器导入的 `upgrade212.nes`，本轮不重建来源或授权。新夹具拒绝覆盖已有证据。
3. 两模块一起 `hdc install -r <upgrade-install-packages>` 覆盖到3.0.6。
4. 未先运行会改变状态的游戏操作，立即用同fixture执行verify，**1/1 PASS，2.480秒**。
5. `firstInstallTime`、`installTime` 均保持 **1790618362791**；只更新版本和updateTime。

通过的断言包括：非最新head、完整历史记录和备注/pin、存档payload及缩略图字节、playedMs、未完成恢复保护点、幂等旧槽迁移及旧文件保留、有效head绕过损坏旧槽；完整设置JSON、布局编码、30秒保存间隔、收藏和最近顺序、来源UUID/locator/规范ID；真实读取已导入ROM的内容key不变，并实际打开运行核心且帧数前进。鸿蒙采用既有托管导入路径，这不是Android SAF授权证据。

首次开机锁屏使旧测试等待真实Ability而未完成，保留 `upgrade-g1-seed.log`；解锁并结束受阻测试进程后以新fixture重新执行。没有修改产品存储规避失败。首次安装目录包含哈希JSON，被安装器拒绝；改为仅包含同一对HAP的目录后成功，未更换包内容。

## 复现与证据

在该HVD解锁后执行：

```powershell
hdc -t 127.0.0.1:5555 shell aa test -b com.flynes.emu -m entry_test -s unittest OpenHarmonyTestRunner -s saveHistoryUpgradePhase seed -s saveHistoryUpgradeFixture g2-20260930-ready -s saveHistoryUpgradeProduct true -s timeout 120000
hdc -t 127.0.0.1:5555 install -r .artifacts/flutter-g2/harmony/upgrade-install-packages
hdc -t 127.0.0.1:5555 shell aa test -b com.flynes.emu -m entry_test -s unittest OpenHarmonyTestRunner -s saveHistoryUpgradePhase verify -s saveHistoryUpgradeFixture g2-20260930-ready -s saveHistoryUpgradeProduct true -s timeout 120000
```

已有seed不可重复覆盖；复现实验需新的fixture ID。日志位于 `.artifacts/flutter-g2/harmony/`：`upgrade-g1-seed-unlocked.log`、`upgrade-g2-verify.log`、`upgrade-g1-installed.json`、`upgrade-g2-installed.json`。本次不测Release性能，也不替代最终安装工件验收。
