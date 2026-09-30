# G2 鸿蒙模拟器 Release 同包配对测量

范围：FlyNESFlutterG1 API20 HVD、相同 Release 主 HAP（SHA-256 `3160E0CF01249D17989F8BC4D49880F98E724826B07E3F37CE4A839E41A8D36A`）、同一真实内置 ROM 内容 key、90 条起始历史记录、60 秒自动保存。两路均是实际 `debug=false` 的主 Ability，测试 HAP 单独安装，不替换主原生库。证据在 `.artifacts/flutter-g2/harmony/release-paired-quiet-02/`；启动和保存的预算 JSON 均在候选测量前写定。此处是模拟器软件回归测量，不是物理刷新率、触摸到光子或真机热功耗认证。

| 指标 | 原生入口 | Flutter 入口 | 冻结门槛 | 本批 |
| --- | ---: | ---: | ---: | --- |
| 冷启动可交互 P95，2 预热＋12 正式，ms | 2070 | 1548 | ≤3570 且≤4000 | 通过 |
| 原生所有者就绪 P95，ms | 152 | 134 | ≤267.2 | 通过 |
| 游戏 PSS P95，KiB | 144081 | 211476 | Flutter≤275153（增量≤128 MiB） | 通过，增量 67395 KiB |
| 源帧增长观测 P95，ms | 22 | 23 | ≤26.2 | 通过 |
| 显示增长观测 P95，ms | 43 | 43 | ≤49.3 | 通过 |
| 自动保存上下文源／显示观测最大，ms | 102／102 | 93／93 | 各≤122 | 通过 |
| 软件输入首次应用上界 P95，ms | 25 | 33 | ≤45 | 通过 |
| 音频欠载增量下界，同等 65230.895 ms 模拟进度 | 600 | 583 | ≤660 | 通过 |

两路均实际模拟 65230.895 ms，各新增一条权威 AUTO 记录；候选 67 个有效 PSS 样本，保存/输入/帧观察由原始 JSON 严格校验。原生启动有一次 2070 ms 离群样本，原生保存窗口有一次 102 ms 观察空档，均保留在阈值计算里；这些样本说明模拟器观测有波动，本批数值不可解读为物理逐帧停顿。

20 次 Flutter 大厅↔原生游戏返回专用测试 PASS：每轮实际模拟帧增长，返回后核心关闭、音频停止、渲染器停止，引擎身份保持。测试进程内 `executeShellCommand(hidumper … --gc)` 在 Release 返回 11；原失败报告保留于 `release-paired-quiet-01/memory-flutter-second-failure.json`。改由宿主 `hdc shell hidumper --mem-jsheap <pid> -T <tid> --gc` 对同一主 Ark 线程在第 5/20 次返回时执行，外部命令各为 exit 0，测试内 GC 计数分别 5→7、12→14。GC 后平台 VM 已用堆 9454→9621 KiB，增长 167 KiB（门槛≤16384 KiB）。原始报告 `memory-flutter.json` 的 `roundTripsComplete`、`memoryCaptureComplete`、`arkGcObservedAtBothCheckpoints` 均为 true。Native allocator API 在这台镜像返回不可用；未把 -1 写成零或宣称全进程分配量无增长。

第一次同包批次 `release-paired-quiet-01` 中 Flutter 原生所有者就绪 421 ms 超过 322.2 ms，且保存窗口观测 99 ms 超过 83 ms；两项失败没有删掉。前者追踪到 Flutter 引擎/Dart 首次请求之后才 `appOpen`，改为 Ability 在建页前真实打开同一幂等所有者，失败仍留给页面重试。后者 99 ms 内源帧和显示计数各推进 3 帧，无法证明核心停顿 99 ms；按冻结的观察指标仍为失败。生产入口改动后，原生和 Flutter 在上述第二批里全部重新采集并按新原生数据先冻结门槛；没有把第一批的失败改判。

本记录不覆盖 G1 原生首卡 200 ms 和 debug 内存历史失败；最终包体、覆盖升级及其余 G2 功能门禁另行记录。
