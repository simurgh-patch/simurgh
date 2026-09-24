"""Compare evaluated source metadata with baseline and effective patched Kernel."""
import hashlib
import json
from pathlib import Path


def verify_metadata(kind, folder, destination, execute, report, root, runtime):
    sdk = runtime.parent.parent / 'host_release_arm64/dart-sdk'
    dart = sdk / 'bin/dart'
    packages = root / 'compiler/.dart_tool/package_config.json'
    inspector = root / 'compiler/bin/inspect_kernel_metadata.dart'
    compiler = root / '.engine-workspace/engine/engine/src/flutter/third_party/dart/pkg/vm/bin/gen_kernel.dart'
    snapshots = {}
    hashes = {}

    def inspect(label, kernel, source_root, graph):
        result = execute(kind + '-metadata-' + label, [dart, '--packages=' + str(packages), inspector, kernel, source_root, graph])
        hashes[label] = hashlib.sha256(kernel.read_bytes()).hexdigest()
        return json.loads(result)

    for side in ['baseline', 'patch']:
        graph = folder / side / 'source_graph.json'
        reference = destination / (kind + '-reference-' + side)
        kernel = destination / (kind + '-metadata-source-' + side + '.dill')
        execute(kind + '-metadata-source-' + side + '-kernel', [dart, 'compile', 'kernel', reference / 'app.dart', '-o', kernel])
        snapshots['source_' + side] = inspect('source-' + side, kernel, reference, graph)
        if side == 'baseline':
            kernel = folder / 'baseline/no-aot.dill'
        else:
            kernel = destination / (kind + '-metadata-module.dill')
            execute(kind + '-metadata-module-kernel', [dart, '--packages=' + str(packages), compiler,
                '--no-aot', '--platform', sdk / 'lib/_internal/vm_platform_strong.dill', '--packages', packages,
                '-Ddart.vm.product=true', '-Ddart.vm.profile=false', '--output', kernel, folder / 'patch/module.dart'])
        snapshots[side] = inspect(side, kernel, folder / side, graph)

    def equal(actual, expected, label):
        if actual == expected:
            return
        keys = sorted(set(actual) | set(expected))
        differences = {key: {'expected': expected.get(key), 'actual': actual.get(key)} for key in keys if actual.get(key) != expected.get(key)}
        (destination / (kind + '-metadata-' + label + '-differences.json')).write_text(json.dumps(differences, indent=2) + '\n')
        raise ValueError(f'{kind} {label} metadata differs from original Kernel')

    equal(snapshots['baseline']['declarations'], snapshots['source_baseline']['declarations'], 'baseline')
    manifest = json.loads((folder / 'patch/manifest.json').read_text())
    graph = json.loads((folder / 'patch/source_graph.json').read_text())
    entities = graph['entities']
    effective = snapshots['baseline']['declarations'].copy()

    def remove(path):
        for key in list(effective):
            if key == path or key.startswith(path + '/'):
                del effective[key]

    def class_path(symbol):
        entity = entities[symbol]
        return entity['library'] + '::class:' + entity['name']

    def method_path(entity):
        if entity['kind'].startswith('top-'):
            return entity['library'] + '::function:' + entity['name']
        owner = entities[entity['owner']]
        kind = {'getter': 'Getter', 'setter': 'Setter', 'operator': 'Operator'}.get(entity['kind'].split('-')[-1], 'Method')
        member = entity['name'][len(owner['name']) + 1:]
        return class_path(entity['owner']) + '/' + kind + ':' + member

    for symbol in manifest['replaced_classes']:
        entity = entities[symbol]
        if entity.get('generated') == 'top-accessor-adapter':
            for accessor_kind in ['getter', 'setter']:
                remove(entity['library'] + '::function:' + accessor_kind + ' ' + entity['name'])
        else:
            remove(class_path(symbol))
    for symbol in manifest['replaced_globals']:
        entity = entities[symbol]
        remove(entity['library'] + '::global:' + entity['name'])
    for symbol in set(manifest['changed_functions'] + manifest['added_functions']):
        entity = entities[symbol]
        if 'owner' not in entity:
            remove(entity['library'] + '::function:' + entity['name'])
        else:
            # Method signatures stay on retained wrappers; body-local metadata
            # lives in the replacement helper, and must replace rather than merge.
            prefix = method_path(entity) + '/local'
            for key in list(effective):
                if key.startswith(prefix):
                    del effective[key]
    effective.update(snapshots['patch']['declarations'])
    equal(effective, snapshots['source_patch']['declarations'], 'effective-patch')

    # Helpers carry the source method metadata and bind annotated class type
    # parameters before method parameters; receiver formals have no user metadata.
    for side in ['baseline', 'patch']:
        source = snapshots['source_' + side]
        actual = snapshots[side]['helpers']
        expected = {}
        for entity in entities.values():
            if 'owner' not in entity or entity.get('kind', '').startswith('class'):
                continue
            prefix = entity['library'] + '::function:' + entity['name']
            # Only helpers emitted by this Kernel are compared. A helper without
            # any annotations contributes no metadata entries.
            if not any(k == prefix or k.startswith(prefix + '/') for k in actual):
                continue
            original = method_path(entity)
            class_prefix = class_path(entity['owner'])
            instance = entity['kind'].startswith('instance-')
            count = source['class_type_parameters'][class_prefix] if instance else 0
            for key, value in source['declarations'].items():
                if key == original:
                    expected[prefix] = value
                elif key.startswith(original + '/pos:'):
                    index = int(key[len(original + '/pos:'):])
                    expected[prefix + '/pos:' + str(index + int(instance))] = value
                elif key.startswith(original + '/type:'):
                    index = int(key[len(original + '/type:'):])
                    expected[prefix + '/type:' + str(index + count)] = value
                elif key.startswith(original + '/named:'):
                    expected[prefix + key[len(original):]] = value
                elif instance and key.startswith(class_prefix + '/type:'):
                    expected[prefix + key[len(class_prefix):]] = value
        equal(actual, expected, side + '-helpers')

    if kind == 'metadata':
        # These are the helper metadata sites that must exist, rather than merely
        # checking consistency for whatever the transformer happened to retain.
        for side in ['baseline', 'patch']:
            helper = snapshots[side]['helpers']
            prefix = 'app:entry::function:Box.label'
            for suffix in ['', '/type:0', '/type:1', '/pos:1']:
                if prefix + suffix not in helper:
                    raise ValueError('Missing method/helper annotation site: ' + suffix)
        if len(snapshots['source_baseline']['declarations']) < 24:
            raise ValueError('Metadata fixture unexpectedly lost annotated locations')
    report[kind + '_kernel_metadata_matches_source'] = True
    report[kind + '_metadata_kernel_sha256'] = hashes
    report[kind + '_metadata_sites'] = {
        'baseline': len(snapshots['source_baseline']['declarations']),
        'patch': len(snapshots['source_patch']['declarations']),
        'baseline_helpers': len(snapshots['baseline']['helpers']),
        'patch_helpers': len(snapshots['patch']['helpers']),
    }
    report['metadata_inspector_sha256'] = hashlib.sha256(inspector.read_bytes()).hexdigest()
    (destination / (kind + '-metadata-snapshots.json')).write_text(json.dumps(snapshots, indent=2) + '\n')
