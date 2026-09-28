# Harmony G1 external texture 实验

范围：REQ-007 媒体容器，`codex/flutter-foundation` 未提交工作区。只用共享 manifest 首项许可内容，不接入用户存档；Mac 按用户要求未测。

## 实现与 SDK 证据

固定 Flutter-OH 3.41.10-ohos-1.0.0 / `244a0e8abb3085e8675589b13e219af8c41cb7aa`，API20，任务专用 x64 HVD `127.0.0.1:5557`。未操作 5555。

此 SDK `FlutterRenderer.ets` 的 `createSurfaceTexture` 调用 `registerSurfaceTexture`，后者只构造 entry，未注册真实 surface；`SurfaceTextureRegistryEntry.release()` 直接抛 `Method not implemented`。实验使用可运行实现路径 `getTextureId → registerTexture → setTextureBufferSize → getNativeWindowId`，释放调用 renderer 的 `unregisterTexture`。没有因此切换 native view，也未修改 SDK。

借用的 OHNativeWindow 交给已有 HarmonyRenderer EGL 线程，256×240，帧从原 NativePlayRuntime 直接交给渲染器；PCM 沿原 OHAudio 消费。新增独立 probe runtime 只占用一个媒体 owner，禁止与已打开的生产 play 并存，不读写 checkpoint 或历史数据库。Dart 仅收 texture ID、诊断计数和发送小型输入/生命周期消息。

清理顺序为清输入、暂停 runtime、停止并 join EGL 线程、unregister texture。Widget detach 保留 runtime，native host dispose 才关闭；每页 owner 隔离旧页面清理、输入和 active 消息，`hostActive && pageActive && attached` 防止后台迟到消息重新启动核心。独立 Flutter UI 线程沿用已验证的公开 shell 参数。

## 当前验证

- `node --test harmony/tests/flutter_texture_test.cjs`：先 RED 3/3（native texture owner 缺失），实现后 GREEN 3/3。覆盖二十次释放不销毁核心、旧 owner 无效、后台 active 竞态。
- `.artifacts/oh/368d3956/`：含新增 C++ 接口的主包与测试包构建 exit0。
- `ctest --test-dir .artifacts/flutter-g0/harmony-host/build -C Debug --parallel 2 --output-on-failure`：15/15。证据 `.artifacts/flutter-g0/harmony-texture/host-ctest.log`。
- 目录/路由/媒体桥联合 `node --test harmony/tests/flutter_texture_test.cjs harmony/tests/flutter_foundation_test.cjs harmony/tests/flutter_route_test.cjs`：12/12，`bridge-tests.log`。

## 5557 真实媒体验证

增量主包和测试包均 `BUILD SUCCESSFUL`，通过 `hdc -t 127.0.0.1:5557 install -r` 覆盖安装，未卸载或清数据。此 HVD 接受 unsigned 包；不是签名真机安装证明。执行：

```powershell
hdc -t 127.0.0.1:5557 shell aa test -b com.flynes.emu -m entry_test `
  -s unittest OpenHarmonyTestRunner -s flutterTextureOnly true -s timeout 120000
```

首轮 `hypium-first.log`：3/4，唯一失败是实验自己设置的初始 2 秒 `presentedFrames > 10` 阈值，真实计数为 9；sourceFrames=166、PCM produced=134076、consumed=133254、callbackCount=168、presentFailures=0。该阈值并非已冻结的性能预算，因此改为两个时间点的真实呈现计数和 PCM 消费计数持续增长；没有把这一调整解释为性能达标。

最终 `hypium-second.log`：**4/4 pass，0 failure，0 error，34.03 秒**：

1. Flutter `Texture` 显示真实游戏画面、原生帧与音频消费持续增长；UiTest 两指通过 Flutter A/B 控件注入，native 帧实际采样 `appliedButtons & 3 == 3`，松开后为 0。截图 `flutter-texture-probe.png` 已人工目检。
2. 系统 Home 后 source frame 停止、OHAudio 停止，前台继续同一核心并恢复音频，输入为 0。
3. 20 次页面 detach/attach：每次 detach 暂停核心和音频、释放 surface、保留 runtime；attach 后核心进度继续增长、真实呈现继续。快速重挂后等稳定 1 秒，OHAudio 已恢复。末次快速采样 sourceFrames=666、presentedFrames=394、presentFailures=0、audioProducedSamples=532613。短暂音频 priming 中 `audioStarted=false` 不当作音频丢失；稳定后有独立断言。
4. native host 改回目录，实验 runtime 与 surface 都已关闭。

两轮合计 40 次 texture surface 重挂，HVD 进程7628持续存活。此次包含协作代理针对共享 EGL display 的修正：渲染器只销毁自身 surface/context，不在局部清理调用 `eglTerminate(EGL_DEFAULT_DISPLAY)` 终止 Flutter 仍使用的 display；普通原生页面20次往返由该代理另行验证，不能由本实验替代。

主包 SHA-256 `731978BD3A6A5A6B6AF7FDE81DCDE56E075AC8996644205CF825013B4D4B9446`；测试包 `8EE48D84DA509772D15FB4891A66A6B4C6168CCDAC97A36B4B18AB736E51554D`，完整路径记录 `package-hashes.json`。

已验证双指 release 和后台清输入；真实操作系统 `PointerCancel` 事件尚未单独注入，不把共享 Dart 的 cancel 单测写作 OH 设备证据。音频计数证明原生生产/消费链，未进行主观听音或波形质量测量；初期 underflow 存在（首轮32，第二轮末25），不认证低延迟或音频质量预算。

设备记录和截图保存在 ignored `.artifacts/flutter-g0/harmony-texture/`。模拟器不认证物理延迟、刷新率、温度或功耗；G1 整体验收仍取决于其他未完成项。
