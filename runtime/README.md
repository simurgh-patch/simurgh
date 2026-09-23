# Runtime source patches

The independent checkout uses the exact Dart revision in `toolchain.lock.json`. The reviewed changes in `patches/manifest.json` form the local fork; no changes are made to the daily Flutter SDK. The files are patch sources, not prebuilt runtime binaries.

Apply and verify the patch set before a dynamic runtime build:

```sh
python3 scripts/runtime_sources.py --apply
python3 scripts/aot_lab.py --build-runtime
```

The source verifier never resets a checkout. It rejects a wrong revision, a modified patch, a modified base file, conflicting changes, staged changes and unrelated tracked changes. An already applied and matching patch is accepted. Patch set identity and exact resulting source hashes enter runtime provenance; the patch manifest also participates in baseline/compiler fingerprints. Existing verified runtime binaries are archived under `output/runtime-archive/` before replacement.

`dart-static-late-final-setter.patch` fixes annotated static late final setter retention in the AOT precompiler. Previously, only static getters entered the retained accessor set, so dynamic bytecode could reference a setter removed from the snapshot. The fix preserves the existing implicit setter, with Dart's native single-assignment check, only when the entry-point policy allows writes and the field needs a setter.

This patch has been built for the host ARM64 dynamic runtime experiment. The Android and iOS engine binaries built before this patch do not contain it. Their replacement mixed-runtime engine builds completed on 2026-09-22 (see `docs/qa/mixed-mobile-build-20260922.json`); startup integration and device acceptance remain outstanding. The general engine build tool accepts this exact patch set with `--profile mixed`; the default reference profile still requires pristine upstream sources. Mixed builds use separate output directories, and resume requires the same source patch identity as the failed attempt. Neither this patch nor the existing tests establish complete Flutter hot-update support.


Build patched mobile engines without replacing the original reference outputs:

```sh
python3 scripts/build_engine.py --build-root .engine-workspace \
  --profile mixed --targets android ios --ignore-space-check --execute
```

`--targets host` builds a full matching host engine/toolchain in `host_release_arm64_mixed`; it is distinct from the smaller `host_release_arm64_dynamic` runtime lab. Mobile outputs are `android_release_arm64_mixed` and `ios_release_mixed`. A successful engine compile alone does not validate bytecode startup, Flutter code replacement, iOS distribution constraints or performance. The application startup integration is still outstanding.

`dart-original-class-names.patch` adds a display-name ABI for the experimental
source linker. In a `DART_DYNAMIC_MODULES` runtime, classes in libraries explicitly
named `simurgh_generated_v1` may encode their source spelling as
`msbEntity_class_<64 lowercase SHA-256 hex digits>__<original name>`. Only the
user-visible class-name path decodes this form. The full identifier remains in
class/type identity and module linking. Ordinary libraries, older hash-only
names and malformed encodings remain unchanged. Internal-name diagnostics retain
the full name. This convention is not an authenticity or signature boundary.

The new host runtime and snapshot compiler require rebuilding from the updated
manifest. Existing mobile engine binaries predate this change; their historical
provenance is not upgraded by changing these source files. Obfuscated builds,
method/stack-frame name restoration and full Flutter semantics are not established
by the class display-name experiment.

`dart-original-enum-names.patch` applies the same guarded display-name ABI in
the pinned frontend's synthesized enum `_enumToString` body. The actual enum
value names, canonical identity and user/mixin/super dispatch are preserved.
Ordinary libraries and malformed names are unchanged. This frontend source is
used by the laboratory Kernel and bytecode commands; previously built frontend
snapshots and mobile engines do not acquire the patch automatically. The manifest
binds the original and patched frontend source hashes along with runtime sources.

## Project naming

The current compiler emits the `simurgh` namespace and the
`simurgh_generated_v1` library marker. Runtime patches and their manifest hashes
use the same marker. Rebuild the host runtime with
`python3 scripts/aot_lab.py --build-runtime` when migrating an existing checkout;
previous compiled artifacts retain their historical provenance and are not
retagged. Mobile engines also require rebuilding before using the renamed ABI.
