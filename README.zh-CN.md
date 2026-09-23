# simurgh

[English](README.md) | **简体中文**

![Flutter](https://img.shields.io/badge/Flutter-3.44.8-02569B?logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.12.2-0175C2?logo=dart&logoColor=white)
![Stage](https://img.shields.io/badge/Stage-Experimental-orange)

基于 Flutter / Dart 的实验性代码热更新项目，目标是提供可私有部署、在应用冷启动时激活的 Dart 代码更新能力。

**当前处于 M0 工程基础与 M1 受限 AOT / 字节码实验阶段，尚不具备完整 Flutter 热更新能力。** `release`、`patch` 等生产命令仍以退出码 `3` 拒绝执行，不会生成伪补丁。

[快速开始](#快速开始) · [模块](#模块) · [当前能力](#当前能力) · [参与开发](#参与开发) · [路线与验证](#路线与验证)

## 快速开始

使用 [toolchain.lock.json](toolchain.lock.json) 固定的 **Flutter 3.44.8 / Dart 3.12.2**。引擎源码和实验构建使用独立工作区，不修改日常 Flutter SDK。

在项目根目录执行：

```sh
export SIMURGH_FLUTTER_SDK=/path/to/flutter
export SIMURGH_DART="$SIMURGH_FLUTTER_SDK/bin/dart"
"$SIMURGH_DART" pub get
./bin/simurgh --json verify-toolchain
./bin/simurgh --json status
```

依赖缓存齐备时可使用 `pub get --offline`；首次获取依赖需要网络或内部镜像。

准备构建工具并检查环境：

```sh
python3 scripts/bootstrap_tools.py
./bin/simurgh --json doctor --devices
./bin/simurgh --json engine-plan --build-root .engine-workspace
python3 scripts/prepare_engine.py --build-root .engine-workspace
```

源码准备默认只检查；添加 `--execute` 才会下载。默认检查 200 GiB 可用空间并保护非空目录，明确接受空间不足风险时可用 `--ignore-space-check` 仅跳过空间检查。详细步骤见[引擎构建指南](docs/ENGINE.md)。

## 模块

| 模块 | 职责 |
| --- | --- |
| [CLI](bin/) / [工具库](lib/) | 工具链校验、环境诊断、参考构建、制品对比与性能数据判定 |
| [编译器实验](compiler/README.md) | Dart 源码解析与实体链接、AOT 入口改写、变更字节码生成 |
| [运行时补丁](runtime/README.md) | 固定上游 Dart 的混合运行实验补丁及来源校验 |
| [独立样例](examples/runtime_probe/README.md) | 表单、列表、导航、动画、异步与语言语义验证 |
| [构建与验证脚本](scripts/) | 独立源码准备、引擎编译、实验执行和回归检查 |

客户端更新器、发布服务、管理控制台和私有部署闭环仍在规划中，详见[开发计划](docs/PLAN.md)。

## 当前能力

- 固定 Flutter、Dart、Engine 与 depot_tools revision，记录源码来源和制品哈希。
- 已完成宿主及 Android / iOS Release 引擎源码构建和独立样例接入构建；真机运行与性能验收仍待完成。
- 宿主 ARM64 实验支持受限源码图中的本地库、package 与 part 链接，以及 AOT 与变更字节码双向调用。
- 受限实验覆盖函数与方法、类版本重连、泛型、闭包、异步、状态字段、用户类继承与混入，以及已链接 SDK 的部分接口和父类桥接。具体支持与拒绝范围见[编译器文档](compiler/README.md)。
- 工具链诊断、普通测试、宿主原生实验、模拟器验证和真机验收分别记录，不互相替代。

运行时基于锁定官方 Dart 源码中的实验性动态模块机制及本项目补丁。完整语言兼容、Flutter 代码替换、移动端冷启动接入、签名与回退、真机性能门槛尚未完成。

## 参与开发

开始前阅读 [AGENTS.md](AGENTS.md)、[开发计划](docs/PLAN.md) 和 [PROGRESS.md](PROGRESS.md)。所有实现与测试使用本项目内的独立样例。

CLI 和生成代码统一使用 `simurgh`；Dart 包名为 `simurgh_cli` 与 `simurgh_compiler_lab`，环境变量使用 `SIMURGH_*`。名称迁移后需重新生成包配置并重建运行时制品；历史构建记录保留原路径和哈希。详见[运行时迁移说明](runtime/README.md#project-naming)。

### 运行测试

```sh
./scripts/verify.sh
```

该脚本运行 Dart 静态分析与测试、Python 回归，以及 Flutter 样例静态分析与测试。它不执行完整引擎构建或真机性能采集。

### AOT / 字节码实验

完成固定源码准备及宿主 SDK 构建后：

```sh
python3 scripts/runtime_sources.py --apply
python3 scripts/aot_lab.py --build-runtime
```

实验在同一 AOT 基线的不同冷启动进程中比较原始与补丁行为。实验说明、输入限制和证据要求见[编译器文档](compiler/README.md)与[运行时文档](runtime/README.md)。

### 官方参考构建

先使用固定 Flutter SDK 在 `examples/runtime_probe` 中执行 `flutter pub get`，再回到项目根目录：

```sh
./bin/simurgh --json baseline --platform ios
./bin/simurgh --json baseline --platform android
```

iOS 默认未签名，Android 使用开发签名，均不是商店包或热更新补丁。日志、源码清单和制品副本保存在 `output/baselines/`；需要干净重建时追加 `--clean`。

```sh
./bin/simurgh --json compare-artifacts --before output/first/inventory.json --after output/second/inventory.json
./bin/simurgh --json performance --input measurements.json
```

性能命令只检查输入数据与门槛，不采集或认证数据来源。退出码：`0` 操作或数值检查通过；`1` 制品不同或性能超标；`2` 输入、环境或构建错误；`3` 核心关卡未通过。

## 路线与验证

按技术关卡推进：**M0 工程与溯源 → M1 混合运行 → M2 Flutter 与移动端验证 → M3–M7 更新器、发布与私有交付**。当前 M0 真机验收与 M1 完整运行时验收均未完成。

- [开发计划与完成条件](docs/PLAN.md)
- [引擎构建与源码边界](docs/ENGINE.md)
- [性能记录与验收门槛](docs/PERFORMANCE.md)
- [模拟器验证说明](docs/SIMULATORS.md)
- [进度、证据与阻塞](PROGRESS.md)

## 许可

本项目采用 [Apache License 2.0](LICENSE)。上游源码与第三方依赖遵循各自许可证；源码来源清单不等于已完成许可证审计。
