# simurgh

**English** | [简体中文](README.zh-CN.md)

![Flutter](https://img.shields.io/badge/Flutter-3.44.8-02569B?logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.12.2-0175C2?logo=dart&logoColor=white)
![Stage](https://img.shields.io/badge/Stage-Experimental-orange)

An experimental code-update project for Flutter and Dart, aiming to provide self-hosted Dart code updates activated on application cold start.

**Currently at M0 infrastructure and M1 restricted AOT / bytecode experiments. Full Flutter code updates are not available.** Production commands such as `release` and `patch` still exit with code `3` and do not generate placeholder patches.

[Getting Started](#getting-started) · [Modules](#modules) · [Current Capabilities](#current-capabilities) · [Contributing](#contributing) · [Roadmap and Validation](#roadmap-and-validation)

## Getting Started

Use **Flutter 3.44.8 / Dart 3.12.2**, pinned in [toolchain.lock.json](toolchain.lock.json). Engine sources and experimental builds use an independent workspace without modifying your everyday Flutter SDK.

Run from the project root:

```sh
export SIMURGH_FLUTTER_SDK=/path/to/flutter
export SIMURGH_DART="$SIMURGH_FLUTTER_SDK/bin/dart"
"$SIMURGH_DART" pub get
./bin/simurgh --json verify-toolchain
./bin/simurgh --json status
```

Use `pub get --offline` when all dependencies are cached. Initial dependency resolution requires network access or an internal mirror.

Prepare build tools and inspect the environment:

```sh
python3 scripts/bootstrap_tools.py
./bin/simurgh --json doctor --devices
./bin/simurgh --json engine-plan --build-root .engine-workspace
python3 scripts/prepare_engine.py --build-root .engine-workspace
```

Source preparation performs checks by default; add `--execute` to download sources. It checks a 200 GiB free-space budget and protects nonempty directories. Use `--ignore-space-check` only when you explicitly accept insufficient-space risks; it bypasses only the space check. See the [engine build guide](docs/ENGINE.md) for details.

## Modules

| Module | Responsibility |
| --- | --- |
| [CLI](bin/) / [tooling library](lib/) | Toolchain verification, environment diagnostics, reference builds, artifact comparison, performance data evaluation |
| [Compiler experiment](compiler/README.md) | Dart source analysis and entity linking, AOT entry rewriting, changed-bytecode generation |
| [Runtime patches](runtime/README.md) | Mixed-execution patches for pinned upstream Dart sources and provenance checks |
| [Standalone sample](examples/runtime_probe/README.md) | Forms, lists, navigation, animation, asynchronous behavior, language semantics |
| [Build and verification scripts](scripts/) | Independent source preparation, engine builds, experiments, regression checks |

The client updater, release service, administration console, and complete private deployment workflow remain planned work. See the [development plan](docs/PLAN.md).

## Current Capabilities

- Pinned Flutter, Dart, Engine, and depot_tools revisions, with source provenance and artifact hashes.
- Completed host and Android / iOS Release engine source builds and standalone sample integration builds. Physical-device execution and performance acceptance remain outstanding.
- Host ARM64 experiments support local libraries, packages, and parts within a restricted source graph, with bidirectional calls between AOT and changed bytecode.
- Restricted experiments cover functions and methods, class-version relinking, generics, closures, asynchronous code, state fields, user-class inheritance and mixins, and selected linked SDK interfaces and superclass bridges. See the [compiler documentation](compiler/README.md) for supported and rejected cases.
- Toolchain diagnostics, ordinary tests, native host experiments, simulator checks, and physical-device acceptance are recorded separately.

The runtime builds on the experimental dynamic-module machinery in the pinned official Dart sources, together with this project's patches. Full language compatibility, Flutter code replacement, mobile cold-start integration, signing and rollback, and physical-device performance gates remain incomplete.

## Contributing

Read [AGENTS.md](AGENTS.md), the [development plan](docs/PLAN.md), and [PROGRESS.md](PROGRESS.md) before making changes. Implementations and tests use standalone samples within this project. These planning and progress documents are maintained in Chinese.

The project uses `simurgh` for its CLI and generated code, `simurgh_cli` and
`simurgh_compiler_lab` for its Dart packages, and `SIMURGH_*` for environment
variables. After a naming migration, regenerate package configuration and rebuild
runtime artifacts; historical build records keep their original paths and hashes.
See the [runtime migration notes](runtime/README.md#project-naming).

### Running Tests

```sh
./scripts/verify.sh
```

This runs Dart analysis and tests, Python regression tests, and Flutter sample analysis and tests. It does not perform a full engine build or collect physical-device performance measurements.

### AOT / Bytecode Experiment

After preparing the pinned sources and building the host SDK:

```sh
python3 scripts/runtime_sources.py --apply
python3 scripts/aot_lab.py --build-runtime
```

The experiment compares baseline and patched behavior in separate cold-start processes using the same AOT baseline. See the [compiler](compiler/README.md) and [runtime](runtime/README.md) documentation for instructions, input restrictions, and evidence requirements.

### Official Reference Builds

Use the pinned Flutter SDK to run `flutter pub get` inside `examples/runtime_probe`, then return to the project root:

```sh
./bin/simurgh --json baseline --platform ios
./bin/simurgh --json baseline --platform android
```

iOS builds are unsigned by default; Android builds use development signing. Neither is a store package or a code-update patch. Logs, source inventories, and artifact copies are stored in `output/baselines/`. Add `--clean` for a clean rebuild.

```sh
./bin/simurgh --json compare-artifacts --before output/first/inventory.json --after output/second/inventory.json
./bin/simurgh --json performance --input measurements.json
```

The performance command evaluates supplied data against thresholds; it does not collect or authenticate measurements. Exit codes: `0` for successful operations or numeric checks; `1` for artifact differences or exceeded performance thresholds; `2` for input, environment, or build errors; `3` for unmet core gates.

## Roadmap and Validation

Development follows technical gates: **M0 infrastructure and provenance → M1 mixed execution → M2 Flutter and mobile validation → M3–M7 updater, releases, and private delivery**. M0 physical-device acceptance and M1 complete-runtime acceptance are both outstanding.

- [Development plan and acceptance criteria](docs/PLAN.md)
- [Engine builds and source boundaries](docs/ENGINE.md)
- [Performance records and thresholds](docs/PERFORMANCE.md)
- [Simulator validation](docs/SIMULATORS.md)
- [Progress, evidence, and blockers](PROGRESS.md)

## License

This project is licensed under [Apache License 2.0](LICENSE). Upstream sources and third-party dependencies retain their respective licenses. A source provenance inventory does not constitute a completed license audit.
