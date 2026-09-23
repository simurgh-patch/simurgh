# M0：源码构建入口与当前边界

## 已核实的源码事实

固定 Flutter stable 3.44.8、Dart 3.12.2。`toolchain.lock.json` 中 Dart revision 从固定 engine revision 的 `DEPS` 提取；不能用版本号相同的另一个 Dart 分支代替。

Flutter 引擎已合入 flutter/flutter 仓库。本机 SDK 包含引擎源码，但未同步完整 third_party/dart 及编译依赖，不能将其视为已经可以编译自研运行时。

`docs/source-provenance.json` 保存本次只读检查的源码链接与 SHA-256。引擎的 `runtime/dart_isolate.cc` 和 `runtime/dart_vm.cc` 是后续隔离启动和 VM 初始化研究入口；未修改这些文件，不声称已有字节码链接器。

## 环境准备

```sh
python3 scripts/bootstrap_tools.py
python3 scripts/prepare_engine.py --build-root .engine-workspace
python3 scripts/prepare_engine.py --build-root .engine-workspace --execute
```

准备脚本依次建立两个独立 checkout：framework 对应 framework revision，engine 对应 engine revision；后者使用官方 standard.gclient 和锁定 DEPS。同步完成后再核对 Dart checkout revision。

depot_tools 固定到锁中的 revision，并关闭自动更新。它的 Python/CIPD 引导仍可能需要网络，故“源码可控”不代表首次安装已离线。完全离线构建镜像要在依赖实际同步后建立，当前未完成。

空间门槛为 200 GiB，既有非空目录不能被覆盖。准备失败保留 partial checkout 和 prepare-state.json；检查日志后选择新的空目录重试，不自动删除用户目录。2026-09-20 用户明确要求不考虑空间、直接编译；新增显式参数 `--ignore-space-check` 允许本轮尝试，记录实际剩余空间及覆盖标志，版本/目录校验仍保留。

## 构建编排入口

`scripts/build_engine.py --build-root .engine-workspace` 默认只读检查。加 `--execute` 才构建；按本轮授权可加 `--ignore-space-check`。要求准备标记、四个锁定 checkout、干净源码、固定 gclient 模板及 Xcode/Ninja 工具。默认拒绝已有目标输出，失败目录保留。`--resume-build <本项目失败build.json>` 仅允许复用同workspace、源码锁和配方、且此前确实启动GN的输出目录；重新验证源码并运行GN/Ninja，新日志保留对原失败清单的哈希引用。成功记录不能作为续编授权。

顺序执行 host Release（源码构建 Dart SDK）、Android ARM64 Release、iOS ARM64 Release，使用固定 DEPS 同步的 `engine/third_party/ninja/ninja`（不依赖 depot_tools 的 Python 包装器引导），默认 Ninja `-j2`，不启用 RBE/Goma，不关闭优化和 LTO。每轮日志在产品仓库 `output/engine-builds/<唯一目录>/`，含源锁/脚本哈希、宿主工具版本、gclient 实际依赖 revisions、逐命令退出码、GN 参数副本及关键制品大小/哈希。关键制品清单并非完整分发包归档。源码/依赖版本在构建后复核；任一命令、文件或一致性检查失败均返回 2。

编译成功状态仅为 `compiled-not-device-validated`，`m0_passed` 和 `runtime_implemented` 始终 false。对应 Python 测试以合成文件和模拟子进程验证编排，绝不作为真实引擎证据。实际宿主/Android/iOS编译已通过；样例接入、真机安装、性能与完整许可证清单仍需逐项完成。

## 同步后的官方基线构建步骤

以下为固定源码文档支持的构建配方。**2026-09-21安装Metal后，宿主、Android ARM64及iOS ARM64的GN/Ninja均退出0，关键制品已记录哈希；尚未通过真机验收**。需要先完成源码准备，确认每个输出目录及日志实际成功；不能靠文档勾选 M0。

```sh
export DEPOT_TOOLS_UPDATE=0
export PATH="/absolute/path/to/simurgh/.tools/depot_tools:$PATH"
cd /absolute/path/to/build-root/engine/engine/src
python3 flutter/tools/gn --runtime-mode release --mac-cpu arm64 --no-prebuilt-dart-sdk
ninja -j2 -C out/host_release_arm64
python3 flutter/tools/gn --android --android-cpu arm64 --runtime-mode release
ninja -j2 -C out/android_release_arm64
python3 flutter/tools/gn --ios --runtime-mode release
ninja -j2 -C out/ios_release
```

必须保留优化与 LTO；不能用 unoptimized 或关闭 LTO 的包冒充性能验收包。宿主与目标产物必须来自相同 Dart revision。使用独立 framework checkout 的 `flutter --local-engine-src-path <engine/engine/src> --local-engine <target> --local-engine-host host_release_arm64 ...` 接入样例，不能替换日常 SDK 的缓存。

构建编排记录 GN 参数、宿主版本、源码 revision、依赖来源和关键产物哈希，保存执行脚本与锁文件副本。完整分发制品归档尚未完成。当前 `m0-...` ID 仅标识锁文件，不代表自研运行时 ABI。

## M1 的首批反例

1. 旧 AOT 调用更新函数时不能继续走旧实现。
2. 被内联的方法变化必须使调用者失效。
3. 虚方法变化不能被去虚拟化旧入口绕过。
4. 变更字段布局后，复用 AOT 不能沿用错误偏移。
5. GC 和异常跨混合栈边界保持对象存活和语义正确。

现有样例的普通 Dart 单元测试只给出官方运行结果；只有在自研补丁实际替换后再次通过，才是混合运行时证据。

## 基础来源

- Flutter 源码及引擎：BSD-3-Clause，保留上游 LICENSE 和通知。
- Dart SDK：BSD-3-Clause，保留上游 LICENSE 和通知。
- depot_tools：以固定 checkout 的 LICENSE 及各目录声明为准。
- Dart CLI 第三方依赖：pubspec.lock 锁定内容哈希；后续正式交付需生成完整依赖许可证清单，当前未完成法律许可审计。

## 本轮真实失败与恢复

源码同步已经成功，宿主GN生成1928个目标；Ninja在ANGLE的Metal着色器构建步骤失败。`xcrun metal --version`确认缺工具链；`xcodebuild -showComponent MetalToolchain -json`显示17F109未安装。两次官方下载均退出70，系统日志返回41 / `MADownloadServerAuthFailure`。不能仅从此信息断定具体账号或网络原因。

需要先在当前Xcode可用的官方组件渠道取得匹配的Metal Toolchain（已有官方组件包可用`xcodebuild -importComponent MetalToolchain -importPath <bundlepath>`导入）。以`xcrun metal --version`成功为准，然后继续：

```sh
python3 scripts/build_engine.py --build-root .engine-workspace --ignore-space-check --resume-build output/engine-builds/20260920T081431Z-qg2x57xy/build.json --execute
```

以上为初次失败记录。2026-09-21用户安装Metal后受控续编成功，清单为`output/engine-builds/20260921T022422Z-hr6hl4vg/build.json`，状态`compiled-not-device-validated`。原失败证据仍见`docs/qa/engine-build-attempt.json`。未修改上游源码或执行真机验收。

## 源码来源与许可证候选清单

```sh
python3 scripts/source_inventory.py --build-root .engine-workspace
```

此命令不编译引擎，不需要Metal，不执行.gclient_entries中的Python代码；按字面量解析依赖列表，用gclient实际清单确认依赖集合，核对Git checkout边界、固定对象、对应提交及洁净状态。固定对象可以是带注释标签，不能直接把标签对象SHA与HEAD提交SHA比较。逐项记录Git追踪的LICENSE/COPYING/NOTICE等候选文件的哈希，CIPD包记录实际实例来源；共享安装目录中的CIPD许可证暂未扫描，输出明确标记待审计。

2026-09-21实测记录103项组件（85个Git checkout、18个CIPD包）及449份许可证候选文件，Git版本和洁净检查通过。这不是完整SBOM、许可证合规结论或M0通过证据。原始清单保存在output/source-inventories独立目录，概要见docs/qa/m0-followup-20260921.json。

同日重试Metal官方下载仍失败。系统下载服务日志进一步确认：Pallas目录请求返回HTTP 401，响应是Authorization Required页面，下载量为0；不是磁盘写入失败。连接及TLS握手已完成，但尚不能从此确定账号、服务端版本目录或网络代理中哪一项导致拒绝。没有更改系统代理、账号或Xcode安装。

## 独立framework版本标签

只按commit浅检出时，Flutter可能识别为`0.0.0-unknown`，导致flutter_test的依赖版本约束失败。使用独立framework前，需从可信上游或已验证的本地官方SDK取得`3.44.8`标签，并验证`refs/tags/3.44.8^{commit}`等于锁定framework revision；不得仅为绕过约束伪造版本。已生成的错误`bin/cache/flutter.version.json`可移入本次构建日志目录保留，再由Flutter重新生成。2026-09-21已从本机官方SDK只读导入匹配标签，独立工具版本恢复为3.44.8，未修改日常SDK。

## 使用源码引擎编译独立样例

在产品仓库根目录运行（不使用日常SDK、不接触OA）：

```sh
PROJECT_ROOT="$PWD"
export GRADLE_USER_HOME="$PROJECT_ROOT/.tools/gradle"
cd examples/runtime_probe
"$PROJECT_ROOT/.engine-workspace/framework/bin/flutter" pub get --offline
"$PROJECT_ROOT/.engine-workspace/framework/bin/flutter" \
  --local-engine-src-path "$PROJECT_ROOT/.engine-workspace/engine/engine/src" \
  --local-engine android_release_arm64 --local-engine-host host_release_arm64 \
  build apk --target-platform android-arm64 --release --no-pub
"$PROJECT_ROOT/.engine-workspace/framework/bin/flutter" \
  --local-engine-src-path "$PROJECT_ROOT/.engine-workspace/engine/engine/src" \
  --local-engine ios_release --local-engine-host host_release_arm64 \
  build ios --release --no-codesign --no-pub
```

Flutter工具首次运行仍会准备平台工具缓存；`pub get --offline`仅限制pub依赖解析，不表示整个首次构建离线。APK使用样例开发签名，iOS产物未签名，不是商店交付。包内引擎需以ELF build ID/Mach-O UUID与本次引擎输出核对，不能仅凭命令退出0认定接入；这些检查也不替代真机运行。


## 自有补丁与混合引擎构建

自有Dart修改由 `runtime/patches/manifest.json` 及差异文件维护，`scripts/runtime_sources.py --apply` 只允许在匹配固定版本的干净源码上应用，并核对修改前后哈希。普通 `reference` 构建仍要求上游源码无修改；混合引擎使用单独的配置：

```sh
python3 scripts/build_engine.py --build-root .engine-workspace \
  --profile mixed --targets android ios --ignore-space-check --execute
```

`mixed` 保持 Release 优化、启用 `--dart-dynamic-modules` 并从源码构建 Dart，输出到 `android_release_arm64_mixed`、`ios_release_mixed`。完整宿主工具链使用 `--targets host`，输出为 `host_release_arm64_mixed`；先前的小型宿主实验目录 `host_release_arm64_dynamic` 不被复用。`--targets` 仅选择本次平台，不降低选定平台的制品检查。

构建清单记录运行时补丁身份、实际工具版本、命令和制品哈希；日志目录同时归档补丁及核验脚本。续编必须匹配工作区、锁、构建配置和补丁身份。运行中若Dart补丁发生变化，构建不能标为成功。已编译旧Android/iOS参考引擎没有这份补丁，不能把它们当作混合运行时制品。

混合引擎编译与Flutter启动加载、代码替换、真机及性能验收分别记录，编译退出0不会开启生产 `release` / `patch` 命令。
