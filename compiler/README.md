# AOT/bytecode compiler experiment

This is the first implemented part of M1, not a complete Flutter hot-update runtime or a production patch format. The existing CLI `patch` and `release` gates remain closed.

The compiler parses and resolves ordinary Dart with the analyzer from the pinned Dart source checkout. It rejects static errors and lowers references by resolved program element before emission. `lib/source_graph.dart` discovers local relative and configured package imports/exports (including prefixes, show/hide, re-exports and cycles), preserves original library privacy during analysis, and assigns functions stable identities from logical library URI plus declaration name. Generated symbols keep identically named private functions distinct. The graph uses a merged AST for dependency analysis. Uniform-language graphs use one dispatch library; mixed-language graphs emit separate libraries per original URI, compiled by CFE into multi-library Kernel. This is not a general Kernel optimizer or linker.

It generates typed mutable dispatch slots and entry checks, an AOT launcher, a dynamic interface, and manifests. No business annotations or hand-written module bridge are required. It compares lowered function bodies and records calls and function references. An import/export change that rebinds an otherwise unchanged caller changes its lowered references and invalidates that caller. The bytecode module contains changed and newly added functions; references to existing functions go through retained baseline entries. Other functions stay AOT. Optimizations and inlining remain enabled. This is conservative entry instrumentation, not a complete optimizer-assumption tracking system.

`class_lowering.dart` lifts supported instance method bodies into typed dispatch functions taking the real baseline object. Original classes retain native virtual dispatch and stable method wrappers, including bound method tear-offs. Private fields/methods are renamed by original library identity after resolving the unmodified source. Compound assignments use the analyzer's read/write elements; mutable fields and captured `this` are not copied into a proxy object. Generated superclass bridges preserve direct `super.method()` calls, including when a patch first introduces a call to an inherited user method. Explicit getters and setters get separate stable helper identities and retain property syntax in class wrappers. Inherited explicit accessor bridges also preserve super reads, writes, compound assignments and increments. Existing physical class layouts are never mutated. Structural changes trigger module-local class versions and a dependency closure as described below.

New classes can be defined in patch bytecode, including new subclasses of baseline classes and multiple levels of new inheritance. Baseline builds mark eligible classes `extendable` and `can-be-overridden` in the pinned Dart dynamic interface. This prevents closed-hierarchy assumptions from bypassing future method or field-accessor overrides. The module imports existing class types while keeping new class types local; unchanged AOT consumers operate on the actual bytecode-created objects. Final/sealed classes remain closed to cross-module extension. Interface classes can be implemented by a module; extending them across an emitted library boundary remains rejected. Class versioning also reuses this mechanism for structural changes without mutating the physical layout of a baseline class.

The runtime and bytecode compiler build on the experimental dynamic-module implementation in the locked official Dart source. We reuse that interpreter's object/stack/call machinery, with the reviewed AOT retention fix in `runtime/patches/` applied to the independent source checkout. They are not an interpreter newly written by this project, nor artifacts from a third-party code-update product.

## Run

After M0 sources and the host SDK have been built:

```sh
python3 scripts/runtime_sources.py --apply
python3 scripts/aot_lab.py --build-runtime
```

This compiles `dartaotruntime` and `gen_snapshot` with `dart_dynamic_modules=true` in the separate `out/host_release_arm64_dynamic` directory, leaving the original engine outputs intact. It creates the compiler's ignored package configuration from the pinned SDK source rather than resolving arbitrary analyzer versions from pub.dev.

Subsequent runs verify runtime artifact hashes and source revisions before reuse:

```sh
python3 scripts/aot_lab.py
python3 scripts/aot_lab.py --candidate compiler/fixtures/aot_gc_patch/app.dart
python3 scripts/aot_lab.py --baseline compiler/fixtures/aot_entities_baseline/app.dart --candidate compiler/fixtures/aot_entities_patch/app.dart
python3 scripts/aot_lab.py --baseline compiler/fixtures/aot_closures_baseline/app.dart --candidate compiler/fixtures/aot_closures_patch/app.dart
python3 scripts/aot_lab.py --baseline compiler/fixtures/aot_libraries_baseline/app.dart --candidate compiler/fixtures/aot_libraries_patch/app.dart
python3 scripts/aot_lab.py --baseline compiler/fixtures/aot_classes_baseline/app.dart --candidate compiler/fixtures/aot_classes_patch/app.dart
python3 scripts/aot_lab.py --baseline compiler/fixtures/aot_new_classes_baseline/app.dart --candidate compiler/fixtures/aot_new_classes_patch/app.dart
python3 scripts/aot_lab.py --baseline compiler/fixtures/aot_accessors_baseline/app.dart --candidate compiler/fixtures/aot_accessors_patch/app.dart
python3 scripts/aot_lab.py --baseline compiler/fixtures/aot_parameters_baseline/app.dart --candidate compiler/fixtures/aot_parameters_patch/app.dart
python3 scripts/aot_lab.py --baseline compiler/fixtures/aot_async_baseline/app.dart --candidate compiler/fixtures/aot_async_patch/app.dart
python3 scripts/aot_lab.py --baseline compiler/fixtures/aot_generics_baseline/app.dart --candidate compiler/fixtures/aot_generics_patch/app.dart
python3 scripts/aot_lab.py --baseline compiler/fixtures/aot_generic_classes_baseline/app.dart --candidate compiler/fixtures/aot_generic_classes_patch/app.dart
python3 scripts/aot_lab.py --baseline compiler/fixtures/aot_layout_baseline/app.dart --candidate compiler/fixtures/aot_layout_patch/app.dart
python3 scripts/aot_lab.py --baseline compiler/fixtures/aot_globals_baseline/app.dart --candidate compiler/fixtures/aot_globals_patch/app.dart
python3 scripts/aot_lab.py --baseline compiler/fixtures/aot_late_final_baseline/app.dart --candidate compiler/fixtures/aot_late_final_patch/app.dart
python3 scripts/aot_lab.py --baseline compiler/fixtures/aot_inference_baseline/app.dart --candidate compiler/fixtures/aot_inference_patch/app.dart
python3 scripts/aot_lab.py --baseline compiler/fixtures/aot_signatures_baseline/app.dart --candidate compiler/fixtures/aot_signatures_patch/app.dart
```

Each run generates baseline AOT and a bytecode module, then launches the same AOT binary in two cold processes, without and with the module. Logs, commands, exit codes, input identities and artifact hashes are saved in a new `output/m1-aot-*` directory. The original fixture should print `207/208/baseline`; loading the patch should print `407/408/patched`. The original AOT file hash must remain unchanged. A successful arbitrary-input run only proves compilation and process completion; expected output assertions must be supplied by the acceptance fixture.

## Supported boundary

Currently supported: a graph of local libraries under the entry file's directory and resolved pure Dart package libraries, relative/package imports/exports and the linked SDK libraries described below, synchronous or Future/dynamic-returning async public/private top-level and supported instance methods and explicit getters/setters, resolved primitive/linked-SDK/program-class/type-parameter/function return and required/optional positional or named parameter types, new libraries/functions with recursion, unchanged retained-entry signatures, function tear-offs in accepted expression positions, synchronous/async closures and local functions with resolved parameter types, mutable captures, primitive expressions, branches, while/for loops, local pattern bindings and exceptions. Class method changes work for the checked class subset, including generic receiver types, with explicit or inferred instance fields, generative/body-factory/redirecting constructors and single inheritance. Resolved local bindings may shadow ordinary program names. Dispatch slots preserve required named markers and optional parameter groups without putting default expressions in function types. Wrappers forward named arguments by name; methods, super bridges, constructors and closures retain their original defaults. Default-value changes unrelated to dependency relocation are rejected as signature changes because unchanged AOT callers can bake them in. A default that captures a relocated function moves with that function and its callers. Existing function references retain baseline wrapper identity, while new functions refer to module-local entities. Returned bytecode closures can be called by unchanged AOT functions, including across GC and exception boundaries. Function body changes are installed before the user's `main` runs.

Explicitly rejected: unresolved or native-hook/plugin packages, SDK libraries outside the linked set, imports outside the entry source root or configured package library roots, conditional/deferred imports, unsupported inferred global types, deleted globals, deleted standalone functions, unrelated signature changes, unsupported generic bounds, generators and void-async top-level/method declarations, external/annotated constructors, named mixin-application aliases, unsupported inherited record type substitutions, direct super access to user-declared fields, dynamic selectors absent from the baseline contract and reserved generated identifiers. Removing existing classes is rejected. Changes to fields, constructors, hierarchy or member sets create a fresh class version and relocate dependencies; removed method helpers are retired only with their owning class. A newly added class extending a retained final/sealed/interface baseline class is rejected. A relocated existing subclass brings such ancestors into its module as well. Local declarations shadowing the entry name `main` remain conservatively rejected. Not every expression position for tear-offs is supported; SDK on-constraint super method tear-offs are covered by the SDK mixin fixture. Compiler diagnostics remain authoritative for unsupported Dart semantics beyond the syntactic checks. There is no warning-and-publish bypass.

The generated installer checks the baseline fingerprint and all replacement types before mutating slots. The fingerprint binds the complete original source graph, toolchain lock and all three compiler source files. Logical identities are independent of the checkout's absolute location. Baseline and patch archives contain `source_graph.json` with original sources, dependencies and logical-to-generated symbol mappings; archived-source tampering is rejected. Class-shape hashes record the frozen structural baseline. **This is compatibility binding, not authentication:** bytecode is trusted local experimental input. No signature parser, untrusted-bytecode hardening, rollback, mobile startup hook, network service or published update is implemented.

M1 remains incomplete: broader package/remaining SDK linking and library constructs and general Kernel support, general optimization dependencies, general layout/optimization assumptions and broader method semantics, broader generic type substitutions, broader Stream semantics, Isolate support and the full closure/GC/exception matrix, mobile integration and agreed performance gates still need implementation and evidence. The fixed-layout class fixture does not prove general object-model compatibility. M0 physical-device acceptance is also unfinished; current user instruction prioritizes runtime implementation without declaring M0 passed.

## Native acceptance checks

Use the two run directories produced above (the second uses the GC fixture):

```sh
python3 scripts/verify_aot_lab.py --run-dir output/<normal-run> --gc-run-dir output/<gc-run> --entities-run-dir output/<entities-run> --closures-run-dir output/<closures-run> --libraries-run-dir output/<libraries-run> --classes-run-dir output/<classes-run> --new-classes-run-dir output/<new-classes-run> --accessors-run-dir output/<accessors-run> --parameters-run-dir output/<parameters-run> --async-run-dir output/<async-run> --generics-run-dir output/<generics-run> --generic-classes-run-dir output/<generic-classes-run> --layout-run-dir output/<layout-run>
```

This verifies artifact hashes, expected baseline/patched output, unchanged baseline AOT bytes, observed GC with a one-MiB young generation, rejected baseline fingerprints, and rejected function types without partial slot mutation. Logs remain in the run's `native-checks` directory; an existing check directory is never overwritten. These fixture checks are native runtime evidence, not mobile or performance acceptance.

The optional entity fixture also checks new mutually recursive functions, AOT tear-off dispatch, stable function identity, and invalidation of a textually unchanged caller after a new name shadows a core function. The closure fixture checks retained mutable captures, bytecode local functions, AOT invocation of returned bytecode closures, GC survival and callback exceptions caught by AOT. A successful fixture is not a claim of complete Dart closure compatibility.

The library fixture checks duplicate private names, cycles, prefixed function tear-offs, a new dependency library and export-only rebinding. Expected baseline output is `11/11/12/1/100`, patched output is `118/118/12/101/200`. The right library's private function remains unchanged; switching a re-export alone changes the last result, even though the entry source is identical.

The class fixture checks virtual/direct/super calls, cross-library private method separation, bound method identity, ordinary/compound/increment field writes, captured receiver survival across GC, bytecode construction of baseline objects and exceptions caught by AOT. It also builds an independently traced snapshot with diagnostic-only optimizer flags, requires successful wrapper inlining and a direct call to the replaceable entry in optimized `main`, then runs the same patch against that snapshot. This proves the observed wrapper optimization path, not every possible optimizer assumption or field-layout change.

The new-class fixture changes only the existing factory function and adds `New`, `Leaf` and `Payload`. Existing `main`, virtual callers, field readers/writers and type checks remain AOT. It requires the new override result `117`, shadowed field value `15`, exact runtime-type inequality with `Base`, nested-subclass result `118`, and correct old-AOT field writes producing `122`. A GC pressure run holds the new object through an AOT-typed reference, including its reference field pointing to another bytecode-created object.

The accessor fixture changes only the baseline class getter and setter bodies. Unchanged AOT property consumers and subclass super bridges must observe the new bodies, including super compound assignment and post-increment. Expected baseline output is `6/20/21/23/23`, patched output is `106/139/380/863/863`; the retained object is checked after young-generation GC pressure. Accessor signature or member-set changes use class versioning rather than old receiver slots.

The parameter fixture checks optional positional arguments, reordered named arguments, required named parameters, unchanged defaults, a default top-level function tear-off callback, named class constructors, super calls and returned closures. A changed instance method constructs a baseline class using named arguments from bytecode. A deliberately incompatible named function signature must be rejected without mutating another valid slot in the same install request. This does not prove default-value changes are safe; those remain rejected.

Future-returning async declarations keep a synchronous dispatch wrapper. The original async body runs in a local async function with its original declared return type (an inferred closure can incorrectly narrow `Future<num>` to `Future<int>`); a patched entry returns its own Future directly, avoiding a second async dispatch boundary. Async expression bodies preserve `await` and `async`, and a `Future<void> main()` is awaited by the launcher. `Future<T>` is supported for accepted T types; generic function, method and class scopes are also supported within the checked type subset. The pinned runtime dynamic interface now retains callable `dart:async` APIs.

The async fixture checks AOT/bytecode await in both directions, async methods, expression bodies, retained mutable closure state while suspended through GC, asynchronous exceptions caught in AOT, execution order around suspension and Future identity through a synchronous relay and declared Future type preservation. It also compiles archived unmodified baseline/candidate sources to ordinary AOT and requires the same observable outputs. These are semantic checks, not performance or mobile acceptance.

Generic top-level functions, methods, local functions and closures retain type parameter declarations and supported bounds. Dispatch types include generic binders, and wrapper/helper/super calls forward explicit type arguments so `num` does not get re-inferred as `int`. Generic function types and explicit tear-off instantiation are preserved. Standalone function bounds and type-parameter arity changes remain signature incompatibilities. Class parameter changes use class versioning; compiler regression coverage is not full native acceptance for every shape.

The generic fixture checks int/string instantiations, unchanged generic AOT callers, generic callbacks and returned closures, explicit tear-offs, constrained calls and their runtime bound errors, preserved `num` type arguments, generic async Future types, virtual/super generic methods and captured type environments through GC. Original-source ordinary AOT outputs are compared too. A patch with a stricter generic bound must fail type validation without partially updating another valid slot. This does not cover changes to existing generic class layouts or SDK bounds outside the linked libraries.

Generic class type parameters are renamed by resolved element identity, so a method parameter named `T` can shadow a class parameter named `T` without colliding in a lifted helper. Helpers carry class parameters before method parameters and receive the original instantiated object. Super bridge signatures substitute the ancestor type arguments obtained from the analyzer, including multi-level inheritance and concrete specializations. Changes to field layouts, parameter counts/bounds or hierarchy trigger class versioning. Baseline objects are not converted in place.

The generic-class fixture checks `Box<T>`, `Child<U>`, an `int` specialization, bounded classes, generic getters/setters and methods, async return type preservation, method/class type-parameter shadowing, covariance write checks and a bytecode-added generic subclass. Old AOT reads the new object's inherited type and retains it across GC. Both source versions are compiled separately to ordinary AOT for observable-output comparison. Unsupported inherited function/record type substitutions are rejected explicitly.

## Class versioning and dependency closure

For the accepted closed source graph, a structurally changed class is emitted with a fresh module-local class identity. The compiler computes a fixed point over class declarations and complete function declarations. Classes containing versioned field/signature types or module-only helper dependencies move too. Function signatures involving versioned types cannot use their old slots: their callers are rebound to module-local functions. Default expressions capturing those functions are signature dependencies as well. Primitive or unchanged-type boundaries still use the baseline typed slots, and unrelated AOT functions remain in use.

The patch manifest records structurally changed classes, all replaced classes, invalidated functions, module-only functions, installed functions and retired helpers. The install map excludes module-only signatures. An explicit negative native check attempts to install a new-receiver helper into its old-receiver slot and requires rejection without partial mutation.

The layout fixture changes an int field to String, adds a field and method, changes construction and removes an obsolete method. Unchanged descendants, a holder field, a method returning the affected class, a default factory callback and a generic type test must rebind. An unchanged base class, arithmetic helper, base-typed virtual caller, generic callback caller and GC routine remain AOT. A changed final subclass also relocates its final ancestor. Original baseline/candidate source AOT outputs are compared against the mixed runs.

This is cold-start source-graph versioning, not live heap migration or a general Flutter/Kernel layout proof. The graph still excludes unsupported top-level state forms and wider language/SDK features; those boundaries must be revisited before broader linkage is enabled. Only measured native fixtures establish runtime acceptance; front-end emission of other class-shape changes alone does not. Class deletion, cross-process persisted business-data migration and general optimizer dependency invalidation remain incomplete. Performance and mobile acceptance remain pending.


## Top-level state dependency handling

Explicitly typed top-level mutable, final, const and late variables are retained as real Dart declarations. Stable global identities include library identity; getter and setter references resolve to the same global. Unchanged globals are qualified baseline references in module code, so retained AOT and bytecode share storage. Native lazy initialization remains in Dart rather than a copied state map.

Changed declarations and globals depending on relocated classes/functions/globals move into the cold-start module. Multi-variable declarations relocate as a group. Readers and writers invalidate transitively; a changed constant in a default argument makes that function module-only, rebinding its callers so baseline default values cannot leak through. Constants remain const declarations. This does not migrate any state from a previous process.

The globals fixture covers shared writes read back by retained AOT, const dependencies, default argument rebinding, relocated class instances held by globals, uninitialized late reads, and a retained lazy initializer calling an updated function exactly once. Ordinary original-source AOT is a separate semantic reference. String interpolation qualification preserves braces when converting an unqualified identifier to a library-qualified access.

Top-level `late final` is now supported by the patched AOT compiler. The original failure was a missing retained implicit setter for static late final fields without initializers. `Precompiler::AddAnnotatedRoots` now retains that setter when the field's entry-point policy allows writes and `Field::NeedsSetter()` is true. Dart's existing setter performs the initialization check; the compiler does not simulate it using nullable storage or bypass the single-assignment rule. The original failing Kernel and bytecode are retained and were rerun with the patched snapshot compiler.

The `aot_late_final` fixture exercises reads before initialization, patch-to-AOT shared reads, a second write from retained AOT rejecting without changing the value, writes to a field that had no baseline writes, and lazy final initialization using an updated function exactly once. Global deletion and inferred global types outside the supported type set remain rejected. These restrictions, mobile integration and broader Kernel/SDK linkage remain unfinished work; this is not a complete state model for arbitrary Flutter applications.

Runtime patch metadata participates in the compiler fingerprint and baseline identity. `scripts/runtime_sources.py` validates the pinned revision, patch hash, original file hash, resulting file hash and absence of unrelated tracked edits; `--apply` only applies the patch set to a clean matching base. `aot_lab.py --build-runtime` archives previously verified runtime binaries before rebuilding. The original failed experiment remains at `output/m1-aot-20260921T101157Z-vr8dgurz`; this fix does not rewrite its historical result.


## Inferred state declarations

The source resolver now materializes the analyzer's inferred types for untyped top-level variables and instance fields before lowering. It preserves final/const/late modifiers, initializer expressions and library-private field names. Multi-variable inferred declarations are split because their individual inferred types can differ; explicitly typed groups retain their existing conservative group dependency behavior.

The type renderer supports resolved function types with generic bindings, bounds and required/optional/named parameter groups. Program class and class type-parameter identities are rewritten by resolved element, so inferred generic callback fields retain the actual class parameter instead of becoming dynamic. Annotation/external and existing backend type boundaries still apply. Function/method signatures and nullable types in the accepted type set are resolved as described below; public types in the linked SDK libraries can cross dispatch boundaries; other SDK types remain unsupported.

The inference fixture covers shared mutable storage, an int-to-String inferred global change, constant defaults, an inferred stored function tear-off invoking the updated AOT entry, a generic inferred closure, and an inferred field type change causing a generic class plus its global holder to relocate. The unchanged reader and stored-callback caller remain AOT; original-source AOT outputs are compared to mixed execution.


## Resolved signatures and local bindings

Missing top-level/local return annotations and simple parameter annotations are materialized from resolved elements. Instance overrides use the analyzer's inherited types, and generated super bridges substitute the actual ancestor type arguments into inferred types as well as explicit types. Contextually typed lambda parameters retain their inferred types. `dynamic` stays dynamic: the transformer does not guess a narrower return type from a literal or arithmetic expression. Omitted return annotations on top-level async functions may resolve to dynamic; the synchronous dispatcher returns the original async Future rather than adding an async layer or narrowing its type.

The accepted signature types include dynamic, Object, Null, Never and nullable forms of otherwise supported types. Unrelated signature changes, including narrowing a dynamic input to int, still fail closed. An unannotated no-argument main is accepted with its resolved dynamic return type; the launcher awaits its result. Explicit void-async functions remain unsupported because preserving their dynamically observable Future requires further work.

For-loop and local pattern bindings no longer need the old parser-only rejection: library resolution distinguishes their local elements from generated stable program identities before emission. The signatures fixture exercises shadowed function names in loops and record destructuring, inherited generic signature inference, nullable arguments, inferred closures and async return behavior. This does not claim general record signatures, all patterns or all dynamic behavior are complete.

## Dynamic selector contract

The pinned CFE originally rejects all dynamic calls in modules. The reviewed `dart-dynamic-selector-contract.patch` permits only `get:`, `set:` and `invoke:` selectors declared by the baseline. Other interface/type validation remains enabled, and dynamic patterns remain rejected. Compilation uses the pinned source `gen_kernel.dart` and `dart2bytecode.dart` entrypoints so the reviewed CFE policy is actually applied rather than using an older SDK snapshot. These are host compiler processes, not JIT on an iOS client.

The baseline generator derives selector roots from local classes and the linked SDK libraries (including public members on private SDK implementation classes). Callable generated functions seed AOT getter/setter/method, tear-off and dynamic forwarder retention before tree shaking. They are not business dispatch slots and are never invoked at startup. Unary minus is normalized to the Kernel `unary-` selector. Getter-returned functions and closure `call` use explicit invocation roots. This conservative retention has **not** met the mobile startup, frame, memory or size performance gates.

The generated dynamic interface text is hashed in the baseline manifest. Patch generation verifies its archived bytes against the original program's regenerated contract; the AOT run also records the file as an artifact. Unknown selectors fail validation instead of silently bypassing retention. New selector names, dynamic private-name resolution, arbitrary SDK linking and general dynamic pattern semantics are not claimed supported.

The `aot_dynamic_calls` fixtures cover arithmetic, a method absent from baseline business call sites, named arguments, field/accessor reads and writes, method tear-offs, invoking a getter-returned closure, bounded generics, wrong argument/setter/bound errors, missing-method errors, mixed GC and a new bytecode subclass. Acceptance requires native results and an independent original-source AOT comparison. Historical failures remain in their original output directories; the initial failure is `output/m1-aot-20260922T023909Z-mt0vj7yj/bytecode.log`.

Run the fixture using:

```sh
python3 scripts/aot_lab.py --baseline compiler/fixtures/aot_dynamic_calls_baseline/app.dart --candidate compiler/fixtures/aot_dynamic_calls_patch/app.dart
```

Pass its output directory to `scripts/verify_aot_lab.py --dynamic-calls-run-dir` alongside the other fixture directories. Host fixture acceptance does not establish Flutter compatibility or mobile cold-start patch installation. Previously built Android/iOS mixed binaries predate this CFE policy; their historical build identities remain unchanged.

## Linked SDK libraries

The resolver accepts `dart:core`, `dart:async`, `dart:collection`, `dart:math`, `dart:convert` and `dart:typed_data`. Imports/exports, prefixes and show/hide clauses are resolved on the original source. Public SDK references then use canonical library aliases in the lowered source, baseline and module; same-spelled symbols from separate imports cannot be merged by text alone. Existing primitive and Future spellings are preserved. An explicit unprefixed core import accompanies the aliases because a prefixed core import disables Dart's implicit core import.

All six libraries are part of the baseline contract, even if a particular application has no calls to one of them yet. The baseline retains callable SDK APIs and dynamic selectors so patches can first use an API (the fixture first uses base64Encode). This is a conservative code-retention choice with unmeasured performance/size costs, not permission to change SDK code or native libraries in a patch. The locked toolchain pins the SDK implementation.

Resolved public SDK types, nested generics and accepted function types are usable in globals, parameters, results and generic bounds. Existing signature compatibility checks still apply. The `aot_sdk` fixture passes real Uint8List/List/Map/Queue/DateTime/Stream/Future objects across the boundary, preserves shared typed-array storage, calls SDK APIs from bytecode and catches a SDK FormatException in unchanged AOT. Its main and typed-array reader remain AOT. Independent source AOT is the output oracle. This is not a claim that every method in these libraries or every Stream lifecycle has passed runtime tests.

Package constructs outside the supported lowered source subset, other SDK libraries (including io/isolate/ffi), general extension declarations, broader SDK coverage and record signature types remain incomplete. Their existing fail-closed boundaries are preserved.

```sh
python3 scripts/aot_lab.py --baseline compiler/fixtures/aot_sdk_baseline/app.dart --candidate compiler/fixtures/aot_sdk_patch/app.dart
```

Supply the output with `--sdk-run-dir` to the native verifier alongside the other fixture runs.

## Package source graphs and language versions

The loader uses the pinned SDK's package_config parser and the nearest resolved `.dart_tool/package_config.json`. It does not fetch packages or change application dependencies. Resolve the application with its normal package manager first. Public package library roots extend the permitted source graph; relative imports inside those roots, transitive package imports and re-exports join the same entity/dependency analysis as app sources.

Package entity identities use canonical `package:name/path.dart` URIs, not cache or checkout paths. Private names retain their library identity. The archive contains each reached library's original source and hash, used package names/versions, pubspec hashes and language versions. Physical roots and unused packages do not enter entity identity. The configuration, reached source files and package manifests are checked for concurrent changes. Unknown packages, aliases/escaping symlinks, Flutter plugin package manifests and native build hooks fail closed. This is a pure Dart compiler experiment; it does not authorize patching native implementations or resource files.

The analyzer's effective language version is recorded for each original library. Uniform graphs preserve that version on the generated dispatch library. Mixed graphs emit separate business libraries with their original versions; a facade at the highest version contains only installation/retention infrastructure and exports the business libraries. An existing library's version change still requires a new baseline; a patch may add a new library at a different version. This removes the former mixed-version rejection within the supported source subset, but does not establish compatibility with arbitrary Flutter dependency graphs.

The `aot_packages` fixture uses local path packages with Dart 3.0 language semantics. It tests a transitive package upgrade, re-exported class method replacement, same-spelled private functions in separate packages, unchanged AOT callers and a newly added package/function. Unit tests copy the package tree to prove location-independent identity and exercise missing mappings, symlink escape, native-hook rejection and language-version boundaries. The native verifier reconstructs the archived package graph in an isolated reference directory and compares ordinary original-source AOT with mixed execution.

Resolve the local fixture dependencies without network access, then build:

```sh
(cd compiler/fixtures/aot_packages_baseline && ../../../.engine-workspace/framework/bin/dart pub get --offline)
(cd compiler/fixtures/aot_packages_patch && ../../../.engine-workspace/framework/bin/dart pub get --offline)
python3 scripts/aot_lab.py --baseline compiler/fixtures/aot_packages_baseline/app.dart --candidate compiler/fixtures/aot_packages_patch/app.dart
```

Pass its output directory using `--packages-run-dir` alongside the other native fixture directories. All fixture source and generated project files stay inside simurgh; no OA project is used.

## Mixed-version source emission

`writeLinkedSources` partitions generated business functions, class helpers, classes and state by their resolved original library identities when the graph contains multiple language versions. Each unit imports the common facade for cross-library references; circular source imports remain supported. The baseline facade owns typed dispatch slots, signature checks and the atomic installer. The patch facade installs replacement functions exported by its units. Classes in the dynamic interface refer to their actual emitted library, so extension/override retention applies to the class definition instead of an export alias.

A single-version baseline can therefore receive a patch that adds a library at another version, while unchanged classes/functions remain in the original baseline. All emitted Dart files are included in the run artifact hashes. `source.dart` is the merged analysis representation and is not the executable entry point for mixed graphs; run the generated launcher.

Underscore formal parameters receive stable generated argument names based on their parameter position. Resolved references to legacy bound parameters are renamed with them; modern wildcard parameters gain an internal forwarding name without becoming user-visible bindings. This also makes wrappers and generated super bridges independent of underscore binding differences between language versions. Ordinary local `_` variables stay in their original-version library.

The multilang fixtures cover Dart 3.0 bound `_` parameters/locals and Dart 3.12 wildcard parameters/patterns, cyclic references, closures crossing AOT/bytecode with observed GC, and a new 3.12 subclass extending a class in a 3.0 baseline. The package fixture uses package_config versions 3.0/3.1 and a bound underscore parameter in the older dependency. `inspect_kernel_languages.dart` reads the actual baseline Kernel library versions; original archived sources are independently compiled to ordinary AOT and compared with mixed execution.

```sh
python3 scripts/aot_lab.py --baseline compiler/fixtures/aot_multilang_baseline/app.dart --candidate compiler/fixtures/aot_multilang_patch/app.dart
python3 scripts/aot_lab.py --baseline compiler/fixtures/aot_multilang_added_baseline/app.dart --candidate compiler/fixtures/aot_multilang_added_patch/app.dart
(cd compiler/fixtures/aot_multilang_packages_baseline && ../../../.engine-workspace/framework/bin/dart pub get --offline)
(cd compiler/fixtures/aot_multilang_packages_patch && ../../../.engine-workspace/framework/bin/dart pub get --offline)
python3 scripts/aot_lab.py --baseline compiler/fixtures/aot_multilang_packages_baseline/app.dart --candidate compiler/fixtures/aot_multilang_packages_patch/app.dart
```

Pass the respective directories as `--multilang-run-dir`, `--multilang-added-run-dir` and `--multilang-packages-run-dir` to the native verifier. General SDK/mixin coverage and Kernel optimization dependencies still need work; mobile and performance acceptance remain open. Parts, mixins and factory support are described in their later sections.

## Original class display names

Class linkage uses the stable library/class hash plus an original-name suffix.
Generated business libraries carry `library simurgh_generated_v1;`, including
separately emitted mixed-language units. The matching runtime patch decodes only
this explicitly marked display ABI, so `runtimeType.toString()` and inherited
`Object.toString()` show the original class spelling, including private names and
nested generic arguments. Different libraries' same-spelled classes retain
separate identities; display text is never used for equality or subtype checks.
Class versions recreated in a patch retain the same source display spelling.

```sh
python3 scripts/aot_lab.py --build-runtime \
  --baseline compiler/fixtures/aot_type_names_baseline/app.dart \
  --candidate compiler/fixtures/aot_type_names_patch/app.dart
```

Pass the run directory as `--type-names-run-dir` to the native verifier alongside
the other fixture runs. It compares original-source AOT output and tests ordinary
libraries and malformed display encodings against the real custom VM. Mixed
language fixtures separately exercise names from generated per-library units.
This does not restore source names in all stack traces or establish obfuscation
support; those remain separate compiler/runtime work.

## Super constructor parameters and lifted interpolation

Constructors in the supported source graph accept Dart super parameters such as
`Child(super.value, {super.step})` and
`Child.named({required super.value}) : super.named()`. Their syntax stays intact
in the lowered class, allowing CFE to resolve inferred types and inherited
optional defaults against the linked superclass. This covers generic and
multi-level inheritance, named constructors, explicit superclass arguments,
parameter use in initializer lists, overridden defaults and const construction.
Invalid forwarding is rejected by analysis of the original source before output.
Changing a superclass constructor default participates in class dependency
relinking, even when the forwarding child's source does not change. Factory,
external and annotated constructors remain outside this path. Redirecting factories are covered by the separate factory fixture below.

Identifier substitutions in unbraced string interpolation now add expression
braces. Lifting `$field` to an explicit receiver must produce `${receiver.field}`;
otherwise Dart interpolates only the receiver and leaves `.field` as literal
text. The same rule applies to qualified SDK symbols. Raw strings and unchanged
local identifiers retain their original semantics.

```sh
python3 scripts/aot_lab.py \
  --baseline compiler/fixtures/aot_super_parameters_baseline/app.dart \
  --candidate compiler/fixtures/aot_super_parameters_patch/app.dart
```

Supply `--super-parameters-run-dir` to the native verifier. It compares complete
stdout against independently compiled original-source AOT and verifies that the
consumer of a newly added subclass remains in baseline AOT while only classes
that depend on a changed constructor default are recreated. This is a host
language-semantics check, not Flutter Widget or mobile startup acceptance.


## Static members and class storage

Supported source classes keep static fields as real Dart class fields, including
inferred declarations, const/final values, lazy initializers and static late
fields. Static method/getter/setter bodies use typed dispatch helpers without an
instance receiver or class type parameters. Method-owned type parameters remain
independent, including when they shadow the class's parameter spelling. Source
analysis still rejects references to instance type parameters from static code
and attempts to inherit static members.

Resolved unqualified static references are qualified by their actual declaring
class before lifting. This applies inside instance methods, static methods and
initializers; private members remain isolated by original library identity.
Static wrappers preserve tear-off identity, generic instantiation and native
property assignment evaluation. Static members do not receive super bridges or
instance dynamic selectors.

Unchanged classes retain their baseline storage while patched helpers read and
write it. Changing static declarations uses the existing class-version dependency
closure: dependent constants, default parameters and classes relink. Helpers
owned by a replaced class remain module-local even without a receiver in their
signature, so a changed static signature cannot be installed into its old slot.
This is cold-start class replacement, not migration of already-running state.

```sh
python3 scripts/aot_lab.py \
  --baseline compiler/fixtures/aot_static_baseline/app.dart \
  --candidate compiler/fixtures/aot_static_patch/app.dart
```

Pass `--static-run-dir` to the native verifier. The fixture checks retained AOT
readers, setters and compound updates, private methods across libraries, static
generic/async methods, exceptions caught in old AOT, lazy initialization once,
late-final errors and a patch-first setter call. A bytecode-created closure crosses
to an AOT allocation loop and is invoked after observed GC. Independent source AOT
provides complete-output comparison. No mobile, Flutter or performance acceptance
is implied by these host checks.


## User-defined interfaces and closed type families

Classes may implement one or more supported program interfaces, including generic
interfaces, abstract interface classes and interfaces composed using implements.
Original-source analysis enforces required members, privacy and Dart class
modifiers before lowering. The generated header retains implements edges using
resolved class identities, so member dispatch, covariance checks, casts and
runtime type tests remain VM operations on real objects.

Eligible interface classes join the dynamic contract's extendable and override
sets, which the pinned CFE uses for both implementation and inheritance checks.
This permits new bytecode implementations of retained open interfaces. It does
not permit extending an interface class across its library boundary. Implementing
Public SDK interfaces, superclass bridges and checked SDK mixin applications are described below.

When an interface changes, implementations and typed dependencies enter the
existing class-version closure. A new implementation of a final/base/sealed type
allowed in the original source requires recreating its closed family together;
the full implements graph participates in dependency propagation. Typed readers
and exhaustive sealed switches then use the module-local types, never an old
signature slot. Original-source illegal cross-library implementations are still
rejected. This is conservative cold-start relinking, not live heap migration.

```sh
python3 scripts/aot_lab.py \
  --baseline compiler/fixtures/aot_interfaces_baseline/app.dart \
  --candidate compiler/fixtures/aot_interfaces_patch/app.dart
```

Pass `--interfaces-run-dir` to the native verifier. Acceptance compares complete
original-source AOT results, verifies retained open-interface consumers and
relocated closed-family consumers, and runs the new implementation through an
AOT allocation loop with observed GC. It covers multiple/generic interfaces,
getter/setter calls, covariance rejection, method tear-off equality, interface
member additions and final/base/sealed family additions. Full Flutter, broader SDK mixin combinations,
mobile startup and performance remain separate work.


## Mixins and application chains

The resolver preserves both `mixin` and `mixin class` declarations as distinct
Dart AST/Kernel declarations. It supports type parameters, user-defined `on`
constraints, implemented interfaces and ordered `with` clauses. The implicit
Object constraint on an unconstrained mixin is accepted. Checked linked SDK
mixins and on-constraints are described in the SDK mixin section below. Original analysis
enforces `on` satisfaction, base modifiers and the absence of mixin constructors.
Named application aliases (`class C = Base with M;`) are still rejected.

Mixin bodies use the same typed receiver dispatch as instance methods. Generated
super bridges search the applicable mixins from right to left, then superclass
members; a constrained mixin builds bridges against its constraint. Generic
receiver substitutions use the analyzer's instantiated supertypes. Bridge names
remain distinct per declaring type, so invoking a lifted method does not turn
its super call into an ordinary virtual call to the wrong layer. Actual mixin
application classes and field storage are constructed by CFE/VM, not copied into
proxy objects. Getters/setters and captured receivers follow the same path.

Method-only changes replace helpers while retained AOT consumers continue using
the baseline mixin types. A changed mixin layout recreates its application classes
and typed consumers through dependency closure. Patches can add an application
of an existing mixin and introduce a new constrained mixin/application. No active
heap or stack migration is performed.

```sh
python3 scripts/aot_lab.py \
  --baseline compiler/fixtures/aot_mixins_baseline/app.dart \
  --candidate compiler/fixtures/aot_mixins_patch/app.dart
```

Pass `--mixins-run-dir` to the native verifier. The fixture compares full output
with independently compiled original-source AOT, requires the invoke/choose/GC
consumers to remain AOT, and keeps a bytecode-created mixin callback alive through
observed collection. It covers generic `on`, ordered super method calls, super
accessors, mixin fields, changed layout, new mixins/applications, implemented
interfaces, base mixins and directly instantiated mixin classes. This does not
establish arbitrary multiple-on constraint combinations, SDK mixins or complete
Flutter/mobile compatibility.


## Factory and redirecting constructors

User-class factory bodies and redirecting constructors remain real Dart
constructors, including generic targets, private named targets, const redirects,
and constructor tear-offs. The source analyzer and CFE enforce return-type,
parameter and const legality. Constructor changes conservatively recreate their
class and dependent classes; they do not hot-swap an already allocated object or
migrate a running factory cache. Activation is before application main.

The `aot_factories` fixture covers cached identity, canonical const identity,
generative forwarding, an abstract factory redirected to a newly added subtype,
exceptions and factory tear-offs held across GC by an unchanged AOT consumer.
Use `--factories-run-dir` with the native verifier for independent original-source
AOT output comparisons and retained-consumer checks. This fixture does not
establish all cross-library private-constructor or SDK-factory combinations.


## Late instance fields

Supported class fields may use `late` and `late final`, with explicit or inferred
types, an initializer or first assignment. They remain native Dart fields; the
compiler does not emulate initialization flags or intercept errors in business
code. Retained class storage is shared by AOT and patch code. Initializer method
updates use the existing dispatch wrappers; structural field changes recreate
the class and its typed dependencies before main.

The `aot_late_fields` fixture covers deferred execution, one-time nullable
initialization, inferred generic fields, reads before assignment, duplicate
late-final assignment, retry after initializer failure, and a patch's first write
to a baseline field that had no baseline writes. It also checks an updated
initializer called from retained AOT field access, GC, and int-to-String late
field layout relinking. `--late-fields-run-dir` enables original-source AOT
comparison and retained-consumer assertions in the native verifier. This does
not establish all reentrant initialization, isolate or mobile-runtime cases.

The companion `aot_late_references` fixture retains main/read/churn in AOT while
patching only field-writing functions. It writes fresh objects after a GC phase,
then runs another GC phase and checks reference values and lazy-field identity.
Use `--late-references-run-dir` for its independent AOT comparison and checks.


## User-defined operators and indexed super assignments

User-class unary, binary, equality and index operators use typed dispatch
helpers with real Dart operator wrappers. Unary and binary minus have distinct
stable identities even though analyzer names both `-`. Baseline typed and dynamic
consumers can invoke changed operators and operators on new patch subclasses.
Inherited user operators have pre-created super bridges; equality bridges keep
nullable RHS behavior. Direct SDK super calls remain outside this support.

A lifted `super[index]` write uses a generated typed index forwarding object.
The object exposes `[]` and `[]=` with the original index and value types. Dart
handles the resulting indexed lvalue, retaining index evaluation once, read-before-
RHS order, assignment-expression values, `??=` short-circuiting, prefix/postfix
results and `await` on the RHS. Read-only super indexing uses a direct bridge.
An invalid dynamic index fails before RHS evaluation. The forwarding object
carries typed read/write closures; its allocation cost has not
been measured, and this is not a performance acceptance claim.

Access adapters are immutable compiler infrastructure. If removing an index
setter makes one unused, patch generation checks that no current declarations
reference it, leaves the old object class in the baseline snapshot and records
its retirement. This does not permit deleting ordinary user classes.

`aot_operators` checks arithmetic/bitwise/comparison/index operators, equality
with null, generic index access, changed super operations, throwing RHS,
async assignment ordering, dynamic dispatch, new subclasses and GC. The
`aot_operator_removal` fixture checks removal of an index setter and the unused
adapter. `aot_operator_checks` covers invalid dynamic index/RHS checking order.
Use `--operators-run-dir`, `--operator-removal-run-dir` and
`--operator-checks-run-dir` for original-
source AOT comparisons and retained-consumer/class-dependency assertions.
Operators requiring unsupported SDK super calls, explicit covariant parameters,
and broader mixed-library/Isolate combinations remain outside verified scope.


## Part files and owning-library identity

The source graph discovers and archives `part` files while distinguishing each
physical file URI from its owning library URI. `part of` by library name or URI
is checked by the original analyzer. Declarations, private member names, class
identities, super privacy checks and generated infrastructure use the owning
library; file hashes and source reconstruction retain the physical file paths.
Moving a declaration between parts of the same library therefore preserves its
link identity. An entry library may define main in a part.

Only owning libraries receive emitted library files and language-version entries.
Local and package parts retain their owner's effective language version, including
mixed-version graphs. Source validation rejects orphan/imported parts, conflicting
owners, mismatched part-of/language versions, illegal private access and paths
outside the established source/package boundaries. Original source files and
part directives remain in the archive for independent ordinary-AOT comparison.
This does not enable conditional/deferred imports, unsupported declarations or
experimental enhanced-part features.

`aot_parts` moves a class and a private function between parts, adds a new part
and subclass, shares private state/constructors/super calls, preserves const
identity and distinguishes equal private names in different owners. A returned
patch closure is consumed by retained AOT through GC. `aot_parts_packages` adds
and moves Dart 3.0 package parts under a 3.12 entry, including legacy `_` binding.
The native verifier accepts `--parts-run-dir` and `--parts-packages-run-dir`,
compares archived original-source AOT and checks actual Kernel language versions.
Run `dart pub get --offline` in each parts-package fixture before native builds;
the fixture pubspecs and lockfiles record the local dependency.

The `aot_parts_private` companion fixture (`--parts-private-run-dir`) checks
unresolved dynamic private selectors from a different part of the same owner.
Retained AOT callers observe the changed private method, while private method
and field access to another owner's same-named class throws NoSuchMethodError.


## Public SDK interfaces

The analyzer now permits `implements` of public, externally implementable SDK
classes from the six linked libraries. It continues to enforce the original
SDK `base`/`final`/`sealed` restrictions and missing-member/type checks.
SDK superclass and mixin support are described below.

The baseline dynamic contract retains all eligible public SDK interface classes
and their public overridable members, including interfaces first implemented by
a future patch. The set is derived from the locked analyzer's resolved class
modifiers and exported entities and is archived in `source_graph.json` as
`sdk_interfaces`. This conservative retention has unmeasured size and performance
costs; it does not permit replacing SDK code.

`aot_sdk_interfaces_{baseline,patch}` exercises SDK sorting through a patched
`Comparable` implementation, JSON encoder callbacks to patched `Sink.add`, a
new subclass, patch-only `Iterator` and `Exception` implementations, runtime
argument checks, and retained AOT consumers/tear-offs across GC. Run it with
`aot_lab.py` and pass its directory as `--sdk-interfaces-run-dir` to
`verify_aot_lab.py` for original-source AOT comparisons and metadata assertions.


## SDK superclasses and super bridges

Public externally extendable classes from the linked SDK libraries can be used
as superclasses. The original analyzer validates interface/base/final/sealed and
constructor restrictions. The baseline retains the union of `sdk_interfaces`
and `sdk_superclasses` in its dynamic inheritance/override contract, including
base SDK classes such as `LinkedListEntry` that permit extension but not external
implementation. Both sets are archived with the source graph.

The transformer resolves the locked SDK ancestor declarations and generates
real `super` forwarding methods inside user classes. It preserves source
parameter defaults, method type parameters, instantiated superclass types,
getters/setters/operators, and accesses to public SDK fields. SDK method bodies
and storage remain in the SDK. Bridges are present in the baseline so a patch
can introduce a first super call without replacing an otherwise unchanged
class. Business mixins constrained to a business class can find its inherited
SDK implementations. SDK mixin applications and SDK mixin ancestors are covered
in the following increment; direct super access to user fields remains unsupported.

Explicit super-call type arguments are rewritten by resolved identity. Indexed
writes use the existing typed indexed adapter with distinct read and write key
and value types. This preserves assignment, compound assignment, postfix,
null-aware write, and index-before-RHS type-check order.

The `aot_sdk_super` fixture exercises `ListBase`, `MapView`, `MapBase`,
`MutableRectangle`, `AssertionError`/`Error`, and a patch-only `LinkedListEntry`
subclass. It covers SDK sort calling patched operators, generic super calls,
defaults, SDK field access/mutation, inherited stack traces, new SDK subclasses,
business mixin lookup, and object/method-reference lifetime across GC.
`aot_sdk_super_checks` independently checks bad index/value evaluation order.
Pass their run directories as `--sdk-super-run-dir` and
`--sdk-super-checks-run-dir` to the native verifier for original-source AOT
comparisons and retained-AOT assertions.

This is host ARM64 evidence for the checked source subset, not complete SDK or
Flutter compatibility. Unsupported source signatures/defaults still fail
compilation. Eager bridges and conservative SDK contract retention have not
been measured against the mobile performance gates.


Super bridges are also members of Dart's implicit class interfaces. For an
`implements` relationship, generated exact-signature members satisfy only those
reserved infrastructure obligations; source members and `noSuchMethod` remain
unchanged. These bodies are unreachable from accepted source code, and the
original analyzer checks all business interface obligations before lowering.
Actual superclass/mixin inheritance keeps the real forwarding implementations.
The `aot_sdk_super_interfaces` fixture covers direct inheritance, generic
implementation across libraries, SDK index-adapter return types, and a custom
`noSuchMethod` implementation. The initial mixin regression that exposed this
issue is retained in the run logs.

`aot_sdk_super_gc` keeps a patch-only `MapBase` object through an SDK values view,
and a patch-only `Error` object's inherited stack trace, across GC. Its unchanged
AOT consumer then calls back into the new class. Pass these additional fixtures
as `--sdk-super-interfaces-run-dir` and `--sdk-super-gc-run-dir`.

## Linked SDK mixins and on-constraints

The source graph accepts exported SDK mixable classes and mixins from the linked
libraries. SDK aliases such as `ListMixin` and `MapMixin` resolve through their
actual class elements. The archived `sdk_mixins` contracts are retained before
patches first introduce new SDK mixin applications. Original Dart analysis still
enforces base/final restrictions, valid applications and required members.

SDK superclass chains can include private SDK mixin declarations, as exercised
by `UnmodifiableMapView`. Their public signatures supply real super bridges;
implementation bodies, private state and SDK storage remain in the SDK.
Business mixins can have direct public linked SDK superclass/interface
on-constraints. Abstract members supplied by the applying superclass are bridged
only when the business source actually uses super. This avoids introducing new
concrete-super obligations into abstract or noSuchMethod-based applications.
A patch introducing such a bridge uses the existing class-version relinking
path instead of changing the retained baseline class in place.

`aot_sdk_mixins` covers generic SDK mixins, SDK callbacks to patched operators,
private SDK mixin ancestry, abstract constrained index reads/writes and length,
generic super.map, an abstract super method tear-off, preserved noSuchMethod,
and patch-only MapMixin objects retained through SDK views across GC. Original
AOT callers and baseline class layouts remain unchanged in this fixture.
`aot_sdk_mixin_relink` adds a first abstract super call and requires only the
constraint mixin and its application to relink; independent AOT consumers stay.
The native verifier independently compiles archived original source for both
fixtures. These are bounded host ARM64 cases, not full SDK/Flutter or mobile
acceptance. Multiple-on intersection signatures and broader mixin ordering,
retention cost and performance remain unverified.


### User superclass fields

User-declared instance fields share the SDK field-accessor bridge path. Generated
bridges use actual `super.field` access with the ancestor's instantiated generic
type, preserving native storage, final/late checks, and independent getter/setter
resolution. Public fields work across libraries; private field symbols retain
the declaring library's identity. No field values are copied into helper storage.

The `aot_super_fields` fixtures cover parent/child same-name storage, generic
ancestors, first super use in a patch, compound/prefix/postfix and awaited updates,
nullable short-circuit writes, late-final repeat errors, private access within a
library, and custom noSuchMethod on an implementing class. A patch-only payload
is read through the inherited field by retained AOT consumers after GC.
Run native checks with `--super-fields-run-dir` in `scripts/verify_aot_lab.py`;
these include independently compiled original-source AOT comparisons. Broader
covariant-field, part/private-field combinations, and mobile behavior are not
accepted by this fixture. Class layout changes remain subject to class-version
relinking, not live object migration.

### Foreign private interface members

Concrete external implementations may omit private interface members declared
in another source library. Their generated members now throw NoSuchMethodError,
as the original Dart front end does, without invoking a business noSuchMethod.
Existing concrete superclass/mixin implementations and implementations inside
the declaring library keep their original behavior.

Compiler-generated contracts and forwarding objects let Dart create its native
Invocation data, preserving the original error text, generic arguments, defaults,
and named arguments. Public helper entry points keep private selectors local
when a new implementation arrives in a bytecode module. These helpers use no
application annotations or hand-written bridges. They are allocated only on
these missing-member paths; their performance has not been measured.

The private-interface fixtures cover fields, accessors, generic methods,
receiver-name collisions, part-library ownership, duplicate private names in
different libraries, custom noSuchMethod, patch-first implementations, and
unused helper retirement. The native verifier compares full exception text
against separately compiled original-source AOT and checks retained AOT callers
and actual GC. Mobile behavior and broader covariant declarations remain
outside this acceptance scope.
