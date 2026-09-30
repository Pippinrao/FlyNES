# G2 Android：G1 Release 覆盖升级数据保留

日期2026-09-30；工作树`codex/flutter-foundation`，基于`f2c5558c`的未提交G2修改，候选3.0.6。本项是功能数据保留验证，不是最终冻结工件或Release性能认证。

使用已有任务专用AVD `FlyNES_G1_Upgrade_20260929` / `emulator-5584`，没有新建分支/工作树，没有卸载、清数据或重新授权。完成后正常关闭该AVD，userdata保留。日常G2模拟器5582未参与这次种子写入。

1. 保留原AVD已授权目录；`install -r`安装冻结G1 Release `eaafd7d0 / 3.0.5`，SHA256 `C79B32460CFABCDD8F933276DFAED25FC62083D0DF620096F22725DE3D87F417`。使用G1归档测试包，真实G1进程分别执行存档和目录seed，各1/1通过。
2. 夹具名`g2_20260930_g1release`，新建专用存档key，不覆盖现有夹具。写入非最新head、普通/手动记录、备注、保护标记、截图、payload、pending恢复事务、坏旧槽旁的新head、旧单槽及SRAM、300000ms非默认保存间隔。
3. 在G1实际进程复用现存SAF授权读取许可测试ROM，记录canonical/variant/source身份、收藏、内容SHA256、非默认buttonScale/deadZone/音频/语言与完整布局。
4. 直接`install -r`覆盖G2开发包3.0.6及当前测试包；新进程先执行两项verify，再进行任何游戏行为。结果`OK (2 tests)`，0.206秒。未以重新导入或重新授权修复差异。
5. 两项断言逐字段比对上述存档/用户状态；新head旁坏旧槽未被读取；pending按恢复事务恢复保护点后清除；旧槽幂等迁入且原文件/SRAM保留；同一授权实际读取的内容SHA256一致。

`firstInstallTime=2026-09-28 17:33:22`在原3.0.3、G1 3.0.5和G2 3.0.6均不变，版本码3000005→3000006。沿用兼容的本地测试签名，不代表生产/商店证书。

## 归档

证据`.artifacts/flutter-g2/android/`：`g1-release-history-seed.log`、`g1-release-catalog-seed.log`、`g1-to-g2-upgrade-verify.log`、`upgrade-{before,g1,g2}-package.txt`、`upgrade-artifacts.json`。
验证候选已复制到忽略目录`upgrade-verified-packages/`，防止后续构建覆盖：

- app-debug-androidTest.apk：`A1B482059E115A414EFD0C6DF4D1A6A2BF06FE367B266755082E1463BCA637EE`
- app-debug.apk：`372558874117730734348C12DFEF46CDCCA18C9341575307D75D4ABDEA5CB122`

后续交接动画修正尚未包含在这批候选中；最终安装包仍需准确revision/版本/哈希冻结。鸿蒙G1→G2覆盖升级未由本结果代替。
