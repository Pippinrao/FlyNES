# Android 跨版本覆盖升级验证

日期：2026-09-29；分支 `codex/flutter-foundation`，3.0.3 未提交工作区。
设备为本轮新建 API35/x86_64 AVD `FlyNES_G1_Upgrade_20260929`，serial `emulator-5584`。
此结果证明模拟器上的本地 debug 签名覆盖安装，不代表商店证书或真机验收。

## 原版来源与安装链

使用 `git archive 3a2dc426` 导出到忽略目录 `.artifacts/n21`，补入该 revision
记录的 Nestopia 子模块 `4470a2e`，未创建新分支、未复制其他工作树改动。
原版 `VERSION=2.1.2` / `versionCode=2001002`，按现有 Gradle 工程构建 x86_64 debug。
`-Pandroid.injected.build.abi=x86_64` 产生 test-only 包，安装显式使用 `-t`。
原版与候选使用同一现有本地 debug 签名，包身份均为 `com.flynes.emu`。

1. 在空白任务 AVD 安装原版 2.1.2 和当前测试 APK。
2. 运行 `G1UpgradeRetentionTest` seed，实际 **1/1通过**。
3. 通过系统 DocumentsUI 选择专用 `Documents/FlyNES-G1` 文件夹并点击授权。
   文件夹只含从共享 manifest 选出的许可内置 ROM；未使用私人 ROM。
4. 运行 `G1CatalogUpgradeRetentionTest` seed，实际 **1/1通过**。
5. 强制停止应用，`adb install -r` 覆盖当前 3.0.3 主包及测试包。
6. 在新进程运行两个 verify 及 `AudioThreadLifecycleIntegrationTest`，实际 **3/3通过**。

安装前后 `firstInstallTime=2026-09-28 17:33:22`（设备输出）不变，
`versionCode` 从 2001002 变为 3000003，`lastUpdateTime` 更新为17:42:31。
未卸载、清数据、重新导入或重授权。当前测试 APK 的 seed 分支只调用原版已有 API；
它在原版实际运行成功，不能把新版本 seed 当作原版数据。

## 实际断言

- 生产 `files/save-history.sqlite` 使用夹具独占内容 key；选中旧记录作为 head，
  同时保留时间更新的自动记录。覆盖后逐项比对 ID、时间、备注、session、parent、
  kind、pin、head、payload、thumbnail 字节。首次运行保存间隔观测值为默认60000ms；
  这不能证明非默认设置保留；评审后在另一全新任务AVD `FlyNES_G1_History_20260929`
  / `emulator-5586` 中补跑2.1.2 seed300000ms → install-r 3.0.3 → verify，
  seed与verify均 **1/1通过**，实际 `save_history.xml` 仍有 `interval_ms=300000`。
  完成后正常关闭该任务模拟器，userdata保留。
- 有效新 head 旁存在损坏旧槽数据；恢复时旧档 loader 必须不被调用。
- 未完成恢复的 operation/backup 跨安装保留；新进程按恢复契约原子恢复保护点、
  清除 pending，内存状态及累计运行时间等于保护点。
- 旧单槽迁入历史后可恢复，旧文件原字节和 SRAM 保留，再次初始化不重复迁移。
- 原生生产目录中的 canonical ID、variant ID、source ID、收藏保留。
- 非默认 buttonScale、deadZone、locale、音频开关、完整布局编码保留。
- OS persisted read grant 保留；通过 `ExactRomLoader` 打开相同授权目录下的实际 ROM，
  payload SHA-256 与升级前一致。不是只检查授权 URI 的字符串。

## 音频前置取消回归

真实旧版 `AudioThreadLifecycleIntegrationTest.stopBeforeStartRemainsStopped`
失败：先 `stopLoop()` 再 `start()`，线程仍运行。原实现初值false与停止false无法区分，
`run()` 的 CAS(false,true) 重新开启被取消的线程。修正为实例初值true、取消单向变false，
run只检查状态。升级后的同一断言通过，且核心状态字节不变。该竞态也由 texture owner
连续交接测试暴露；完整 texture 回归另见容器记录。

## 证据与限制

忽略证据目录 `.artifacts/flutter-g0/android-upgrade/` 包含 `n21-seed.log`、
`n21-catalog-seed.log`、`n21-to-g1-verify.log`、安装前后 package 信息、
OS grant 信息及原版 APK SHA-256。原版构建日志为
`.artifacts/flutter-g0/native-2.1.2-build-quoted.log`。
非默认间隔追加证据为 `n21-nondefault-interval-seed.log`、
`n21-nondefault-interval-verify.log`、`nondefault-interval-after.xml`。
音频 RED 记录为 `.artifacts/flutter-g0/android-foundation/audio-stop-before-start-red.log`。

测试为选定夹具，不声称穷举所有历史数据/schema 或所有设置值。
模拟器上的 debug 签名安装不证明物理设备性能或生产证书升级。
旧版只构建 x86_64，不能拿其包体大小直接比较候选多 ABI 包。
