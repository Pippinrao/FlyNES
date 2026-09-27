# 仓库整理（2026-09-27）

以 main@fe12f9ac604a 上 9 月 24–25 日的未提交工作区为来源，整理三端附近联机页面、空房间选游戏、回滚呈现、音频与输入修复及既有测试。用户要求先提交，再执行安卓与鸿蒙真机测试。

- 删除三个本地旧分支：codex/mvp-device-functional-test（已是 main 祖先）、codex/nearby-three-platform-bidirectional、codex/nearby-landscape-ux（已被当前主干与工作区取代，保留原历史）。
- 两个旧 worktree 的全部文件复制到忽略目录 out/consolidation-20260927/，用 robocopy 只读比较确认无差异；原分支保存在已验证的 retired-branches.bundle。旧 worktree 的未提交版本文件、两份验证记录和忽略证据均保留在副本中。
- Git worktree 登记只保留 main。nearby-three-platform 原目录删除时遇到 Windows 长路径残留；后续递归删除被自动审批策略拒绝，残留保留，未声称磁盘清理完整完成。
- 当前鸿蒙本地签名配置单独保存在忽略目录，提交只保留无签名材料的仓库构建配置。设备安装使用本地测试签名。
- 提交前重新通过 Android testDebugUnitTest、共享层相关 CTest 14/14、7 款内置内容 gate、git diff --check。此前全平台模拟器结果见 9 月 25 日记录，本次不重复全平台测试。
- pre-commit hook 已安装，提交自动增加 PATCH；主版本保持 1。

本记录不证明真机扫码、双人游玩、扬声器、触控延迟、温度或功耗通过。真机结果另行记录。没有推送或删除远端分支。
