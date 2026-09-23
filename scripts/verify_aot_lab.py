#!/usr/bin/env python3
"""Native checks for the fixed experimental M1 acceptance fixtures only."""
import argparse
import hashlib
import json
import re
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / '.engine-workspace/engine/engine/src/out/host_release_arm64_dynamic/dartaotruntime'


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run-dir', type=Path, required=True)
    parser.add_argument('--gc-run-dir', type=Path, required=True)
    parser.add_argument('--entities-run-dir', type=Path)
    parser.add_argument('--closures-run-dir', type=Path)
    parser.add_argument('--libraries-run-dir', type=Path)
    parser.add_argument('--classes-run-dir', type=Path)
    parser.add_argument('--new-classes-run-dir', type=Path)
    parser.add_argument('--accessors-run-dir', type=Path)
    parser.add_argument('--parameters-run-dir', type=Path)
    parser.add_argument('--async-run-dir', type=Path)
    parser.add_argument('--generics-run-dir', type=Path)
    parser.add_argument('--generic-classes-run-dir', type=Path)
    parser.add_argument('--layout-run-dir', type=Path)
    parser.add_argument('--globals-run-dir', type=Path)
    parser.add_argument('--late-final-run-dir', type=Path)
    parser.add_argument('--inference-run-dir', type=Path)
    parser.add_argument('--signatures-run-dir', type=Path)
    parser.add_argument('--dynamic-calls-run-dir', type=Path)
    parser.add_argument('--sdk-run-dir', type=Path)
    parser.add_argument('--sdk-interfaces-run-dir', type=Path)
    parser.add_argument('--sdk-mixins-run-dir', type=Path)
    parser.add_argument('--sdk-mixin-relink-run-dir', type=Path)
    parser.add_argument('--sdk-super-run-dir', type=Path)
    parser.add_argument('--sdk-super-checks-run-dir', type=Path)
    parser.add_argument('--sdk-super-gc-run-dir', type=Path)
    parser.add_argument('--sdk-super-interfaces-run-dir', type=Path)
    parser.add_argument('--packages-run-dir', type=Path)
    parser.add_argument('--multilang-run-dir', type=Path)
    parser.add_argument('--multilang-added-run-dir', type=Path)
    parser.add_argument('--multilang-packages-run-dir', type=Path)
    parser.add_argument('--type-names-run-dir', type=Path)
    parser.add_argument('--super-parameters-run-dir', type=Path)
    parser.add_argument('--super-fields-run-dir', type=Path)
    parser.add_argument('--typedefs-run-dir', type=Path)
    parser.add_argument('--typedef-relink-run-dir', type=Path)
    parser.add_argument('--typedef-multilang-run-dir', type=Path)
    parser.add_argument('--typedef-ancestors-run-dir', type=Path)
    parser.add_argument('--named-mixins-run-dir', type=Path)
    parser.add_argument('--named-mixin-interfaces-run-dir', type=Path)
    parser.add_argument('--named-mixin-relink-run-dir', type=Path)
    parser.add_argument('--named-mixin-multilang-run-dir', type=Path)
    parser.add_argument('--named-mixin-retire-run-dir', type=Path)
    parser.add_argument('--private-interfaces-run-dir', type=Path)
    parser.add_argument('--private-interface-added-run-dir', type=Path)
    parser.add_argument('--private-interface-removed-run-dir', type=Path)
    parser.add_argument('--static-run-dir', type=Path)
    parser.add_argument('--interfaces-run-dir', type=Path)
    parser.add_argument('--mixins-run-dir', type=Path)
    parser.add_argument('--factories-run-dir', type=Path)
    parser.add_argument('--late-fields-run-dir', type=Path)
    parser.add_argument('--late-references-run-dir', type=Path)
    parser.add_argument('--operators-run-dir', type=Path)
    parser.add_argument('--operator-removal-run-dir', type=Path)
    parser.add_argument('--operator-checks-run-dir', type=Path)
    parser.add_argument('--parts-run-dir', type=Path)
    parser.add_argument('--parts-packages-run-dir', type=Path)
    parser.add_argument('--parts-private-run-dir', type=Path)
    args = parser.parse_args()
    run, gc_run = args.run_dir.resolve(), args.gc_run_dir.resolve()
    destination = run / 'native-checks'
    destination.mkdir(exist_ok=False)
    report = {'complete_runtime_implemented': False, 'm1_passed': False, 'checks': []}

    def execute(name, command, expected_exit=0, contains=(), lines=()):
        process = subprocess.run(list(map(str, command)), cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        (destination / (name + '.log')).write_text(process.stdout)
        valid = ((process.returncode == 0) if expected_exit == 0 else (process.returncode != 0))
        valid = valid and all(text in process.stdout for text in contains)
        valid = valid and all(line in process.stdout.splitlines() for line in lines)
        report['checks'].append({'name': name, 'command': list(map(str, command)), 'exit_code': process.returncode, 'passed': valid})
        (destination / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
        if not valid:
            raise RuntimeError(f'{name} failed; inspect {destination}')
        return process.stdout

    folders = [run, gc_run] + [p.resolve() for p in [args.typedefs_run_dir, args.typedef_relink_run_dir, args.typedef_multilang_run_dir, args.typedef_ancestors_run_dir, args.named_mixins_run_dir, args.named_mixin_interfaces_run_dir, args.named_mixin_relink_run_dir, args.named_mixin_multilang_run_dir, args.named_mixin_retire_run_dir, args.private_interfaces_run_dir, args.private_interface_added_run_dir, args.private_interface_removed_run_dir, args.super_fields_run_dir, args.entities_run_dir, args.closures_run_dir, args.libraries_run_dir, args.classes_run_dir, args.new_classes_run_dir, args.accessors_run_dir, args.parameters_run_dir, args.async_run_dir, args.generics_run_dir, args.generic_classes_run_dir, args.layout_run_dir, args.globals_run_dir, args.late_final_run_dir, args.inference_run_dir, args.signatures_run_dir, args.dynamic_calls_run_dir, args.sdk_run_dir, args.sdk_interfaces_run_dir, args.sdk_mixins_run_dir, args.sdk_mixin_relink_run_dir, args.sdk_super_run_dir, args.sdk_super_checks_run_dir, args.sdk_super_gc_run_dir, args.sdk_super_interfaces_run_dir, args.packages_run_dir, args.multilang_run_dir, args.multilang_added_run_dir, args.multilang_packages_run_dir, args.type_names_run_dir, args.super_parameters_run_dir, args.static_run_dir, args.interfaces_run_dir, args.mixins_run_dir, args.factories_run_dir, args.late_fields_run_dir, args.late_references_run_dir, args.operators_run_dir, args.operator_removal_run_dir, args.operator_checks_run_dir, args.parts_run_dir, args.parts_packages_run_dir, args.parts_private_run_dir] if p]
    manifests = [json.loads((p / 'build.json').read_text()) for p in folders]
    if len({manifest['compiler_sha256'] for manifest in manifests}) != 1:
        raise ValueError('Acceptance fixtures were built with different compilers')
    for folder, manifest in zip(folders, manifests):
        if manifest['state'] != 'executed-not-m1-accepted':
            raise ValueError(f'Build did not finish successfully: {folder}')
        if digest(RUNTIME) != manifest['runtime_provenance']['artifacts']['dartaotruntime']:
            raise ValueError(f'Runtime differs from build evidence: {folder}')
        for path, record in manifest['artifacts'].items():
            if digest(folder / path) != record['sha256']:
                raise ValueError(f'Artifact changed: {folder / path}')
    aot_hash = digest(run / 'baseline/app.aot')
    execute('baseline', [RUNTIME, run / 'baseline/app.aot'], lines=['calculate=207', 'caller=208', 'caught=Bad state: baseline'])
    execute('patched', [RUNTIME, run / 'baseline/app.aot', run / 'patch/patch.bytecode'], lines=['calculate=407', 'caller=408', 'caught=Bad state: patched'])
    text = execute('mixed-gc', [RUNTIME, '--new_gen_semi_max_size=1', '--verbose_gc', gc_run / 'baseline/app.aot', gc_run / 'patch/patch.bytecode'], contains=['Scavenge('], lines=['calculate=407', 'caller=408', 'caught=Bad state: patched'])
    report['observed_scavenges'] = text.count('Scavenge(')
    # New entity links and returned closures exercise actual bytecode/AOT calls,
    # not merely the shape of generated Dart. Every comparison is a cold process.
    def private_error(receiver, kind, name, call, prefix=''):
        return [f"{prefix}NoSuchMethodError: Class '{receiver}' has no instance {kind} '{name}'.",
                f"Receiver: Instance of '{receiver}'", f'Tried calling: {call}']

    def private_output(receiver):
        result = []
        for current in [receiver, 'Mock']:
            for kind, name, call in [
                ('getter', '_field', '_field'), ('setter', '_field=', '_field=3'),
                ('method', '_method', '_method(1)'), ('getter', '_property', '_property'),
                ('setter', '_property=', '_property=8'),
                ('method', '_generic', '_generic<int>(2, suffix: "default")'),
                ('method', '_collision', '_collision<int>(7, suffix: "c")')]:
                result += private_error(current, kind, name, call)
        result += ['live:5:6', 'home:8:77']
        for current, prefix in [('Back', 'back:'), ('Both', 'left:'), ('Both', 'right:'), (receiver, 'gc:')]:
            result += private_error(current, 'getter', '_field', '_field', prefix)
        return result

    for kind, folder, expected_base, expected_patch in [
        ('typedefs', args.typedefs_run_dir,
         ['delayed:4', 'static:3:3:3', '7:5:6:Box<int>:7:2.5:8', 'true:true:true:true:true', 'left:2:String:int:right:3:String:int:9:10:11', 'added:box:12:Box<int>', 'gc:box:12'],
         ['delayed:4', 'static:4:4:4', '17:5:6:Box<int>:7:2.5:8', 'true:true:true:true:true', 'left:2:String:int:right:3:String:int:9:10:12', 'added:patched:12:Added', 'gc:patched:12']),
        ('typedef_relink', args.typedef_relink_run_dir,
         ['left:3:7:left:4', 'types:true:true:Holder', 'gc:left:4'],
         ['right:3:five!:right:4', 'types:false:false:Holder', 'gc:right:4']),
        ('typedef_multilang', args.typedef_multilang_run_dir,
         ['type:_Hidden<int>', 'old:7:old:8:old:9', '4:old:6:true:5'],
         ['type:Added', 'old:7:old:8:old:9', '4:old:6:true:5']),
        ('typedef_ancestors', args.typedef_ancestors_run_dir, ['4:3'], ['4:8']),
        ('named_mixins', args.named_mixins_run_dir,
         ['8:2:8:3:9:3:10:4:true:5', 'added:12:Named<int>', 'gc:12:Named<int>'],
         ['patched:8:2:patched:8:3:patched:9:3:patched:10:4:true:5', 'added:12:Added<int>', 'gc:12:Added<int>']),
        ('named_mixin_relink', args.named_mixin_relink_run_dir,
         ['8:2:8:3:9:3:10:4:true:5', 'added:12:Named<int>', 'gc:12:Named<int>'],
         ['patched:8:20:patched:8:30:patched:9:30:patched:10:4:true:5', 'added:12:Added<int>', 'gc:12:Added<int>']),
        ('named_mixin_interfaces', args.named_mixin_interfaces_run_dir,
         ['8:2:9:3:10:4:true:5', 'mock:77'] + private_error('AliasPrivate', 'getter', '_secret', '_secret', 'private:'),
         ['patched:8:2:patched:9:3:patched:10:4:true:5', 'mock:77'] + private_error('AliasPrivate', 'getter', '_secret', '_secret', 'private:')),
        ('named_mixin_retire', args.named_mixin_retire_run_dir,
         ['8:2:9:3:10:4:true:5', 'mock:77'] + private_error('AliasPrivate', 'getter', '_secret', '_secret', 'private:'),
         ['patched:8:2:patched:9:3:patched:10:4:true:5', 'mock:77', 'private:null']),
        ('named_mixin_multilang', args.named_mixin_multilang_run_dir,
         ['7:3:Named<int>', '10:4:Named<int>', 'forward:6'],
         ['7:3:Added<int>', '10:4:Named<int>', 'forward:6']),
        ('private_interfaces', args.private_interfaces_run_dir, private_output('Plain'), private_output('Added')),
        ('private_interface_added', args.private_interface_added_run_dir, ['4:3'], private_error('Added', 'getter', '_secret', '_secret')),
        ('private_interface_removed', args.private_interface_removed_run_dir, private_error('Added', 'getter', '_secret', '_secret'), ['4:3']),
        ('super_fields', args.super_fields_run_dir,
         ['update:12:7:1000', 'first:1000', 'final:7', 'late:21', 'repeat:true:20', 'optional:4:4:1', 'async:10:2', 'accessors:105:205', 'private:6', 'mock:77', 'implemented:6:5', 'gc:10:10'],
         ['update:32:17:1000', 'first:17', 'final:7', 'late:21', 'repeat:true:20', 'optional:4:4:1', 'async:20:2', 'accessors:105:205', 'private:15', 'mock:77', 'implemented:6:5', 'gc:30:30']),
        ('sdk_mixins', args.sdk_mixins_run_dir,
         ['private-sdk-ancestor:one', 'immutable:true', 'sdk-alias-mixin:3|1|2', 'sorted:1,2,3', 'sdk-on:3|4:3', 'generic:v3,v4:2', 'write:8|4', 'abstract-unused:0', 'abstract-tearoff:5', 'gc:3:8'],
         ['private-sdk-ancestor:two', 'immutable:true', 'sdk-alias-mixin:13:11:12', 'sorted:22,31,33', 'sdk-on:3:4:4', 'generic:v3,v4:2', 'write:8:4', 'abstract-unused:0', 'abstract-tearoff:15', 'gc:30:4']),
        ('sdk_mixin_relink', args.sdk_mixin_relink_run_dir, ['first:3', 'picked:3'], ['first:3', 'picked:4']),
        ('sdk_super_interfaces', args.sdk_super_interfaces_run_dir,
         ['direct:one', 'implemented:own', 'updated:written', 'mock:mock', 'identity:true'],
         ['direct:two', 'implemented:own', 'updated:written', 'mock:mock', 'identity:true']),
        ('sdk_super_gc', args.sdk_super_gc_run_dir,
         ['map:3', 'stack:true:true', 'error:Bad state: old'],
         ['map:30', 'stack:true:true', 'error:fresh error']),
        ('sdk_super', args.sdk_super_run_dir,
         ['fields:2', 'mixed:1:2', 'render:3,1,2:a,b', 'front:3', 'copy:3,1,2:v3,v1,v2', 'default:ab:false', 'setter:z', 'sort:1,2,3', 'view:4:4:5:7:7:6', 'lvalue:4:8:8', 'chain:3', 'error:detail:failure:old:Assertion failed: "failure":true:true', 'new:1:true', 'gc:1:3,1,2'],
         ['fields:11', 'mixed:1:2', 'render:13|11|12:a|b', 'front:13', 'copy:13,11,12:v13,v11,v12', 'default:ab:false', 'setter:z', 'sort:11,12,13', 'view:8:8:9:7:7:14', 'lvalue:4:8:8', 'chain:9', 'error:detail:failure:new:Assertion failed: "failure":true:true', 'new:9:true', 'gc:11:13|11|12']),
        ('sdk_super_checks', args.sdk_super_checks_run_dir,
         ['error:true:false:i'], ['error:true:true:ir']),
        ('sdk_interfaces', args.sdk_interfaces_run_dir,
         ['sort:1,2,3', 'compare:1', 'reject:true', 'sink:[1,2]:true', 'iterator:7', 'caught:FormatException: old', 'gc:2'],
         ['sort:3,2,1', 'compare:-3', 'reject:true', 'sink:patched:[patched:1patched:,patched:2patched:]:true', 'iterator:60', 'caught:new failure', 'gc:-7']),
        ('parts_private', args.parts_private_run_dir,
         ['read:3', 'field:3', 'private:true:true'],
         ['read:13', 'field:3', 'private:true:true']),
        ('parts', args.parts_run_dir,
         ['private:5:3', 'state:1', 'closure:4', 'new:3', 'identity:true', 'isolation:false', 'other:9'],
         ['private:8:3', 'state:10', 'closure:23', 'new:104', 'identity:true', 'isolation:false', 'other:9']),
        ('parts_packages', args.parts_packages_run_dir,
         ['read:4', 'legacy:5:7', 'type:_Box', 'private:8'],
         ['read:115', 'legacy:6:7', 'type:Added', 'private:8']),
        ('operator_checks', args.operator_checks_run_dir, ['error:true:false:i'], ['error:true:true:ir']),
        ('operator_removal', args.operator_removal_run_dir, ['value:3'], ['value:7']),
        ('operators', args.operators_run_dir,
         ['arithmetic:11:5:-8:-9:16:true', 'equality:false:false:true:8', 'dynamic:-8:6:10', 'new:11:9', 'generic:changed:changed!:changed!', 'assign:3:3:irs', 'compound:6:6:igrs', 'prefix:7:7:igs', 'postfix:7:8:igs', 'async:13:13:igars', 'nullFirst:7:igrs', 'nullSecond:7:ig', 'addedSuper:0:13:', 'failed:13:igr', 'writeOnly:rhs:rhs', 'operators:5.5:5:1:2:11:9:44:2:2:true:false:true'],
         ['arithmetic:21:-5:-18:-9:16:true', 'equality:true:false:true:8', 'dynamic:-18:-4:20', 'new:112:110', 'generic:changed:changed!!:changed!!', 'assign:4:4:irs', 'compound:18:8:igrs', 'prefix:9:9:igs', 'postfix:9:10:igs', 'async:15:15:igars', 'nullFirst:7:igrs', 'nullSecond:7:ig', 'addedSuper:60:60:igrs', 'failed:60:igr', 'writeOnly:rhs:rhs', 'operators:5.5:10:1:2:11:9:44:2:2:true:false:true']),
        ('late_references', args.late_references_run_dir,
         ['first:10', 'gc:4', 'next:12', 'gc2:4', 'identity:false'],
         ['first:40', 'gc:14', 'next:42', 'gc2:14', 'identity:false']),
        ('late_fields', args.late_fields_run_dir,
         ['cold:0', 'lazy:3:3:1', 'final:3:3:2', 'missing:true', 'once:7:true', 'write:10:10', 'gc:7', 'other:8:0', 'nil:null:null:1', 'only:-1:false', 'inferred:3:3:3', 'retry:Bad state: retry', 'retried:9:9:2', 'shape:6'],
         ['cold:0', 'lazy:3:3:10', 'final:3:3:20', 'missing:true', 'once:17:true', 'write:20:20', 'gc:17', 'other:8:0', 'nil:null:null:1', 'only:23:true', 'inferred:3:3:30', 'retry:Bad state: retry', 'retried:9:9:2', 'shape:7']),
        ('factories', args.factories_run_dir,
         ['factory:2', 'redirect:3', 'generative:4', 'const:true', 'cache:3:true', 'choice:4', 'tearoff:5', 'redirectTearoff:5', 'caught:true', 'gc:6'],
         ['factory:2', 'redirect:3', 'generative:4', 'const:true', 'cache:7:true', 'choice:14', 'tearoff:5', 'redirectTearoff:5', 'caught:true', 'gc:16']),
        ('mixins', args.mixins_run_dir,
         ['combined:29', 'count:1', 'choose:3', 'label:old', 'new:29', 'type:true:true', 'chooseNew:4', 'accessors:6:4', 'gc:33', 'shape:2', 'fresh:3', 'interface:tag', 'baseMixin:1', 'mixinClass:old'],
         ['combined:49', 'count:1', 'choose:3', 'label:new', 'new:23', 'type:true:true', 'chooseNew:8', 'accessors:8:4', 'gc:55', 'shape:4', 'fresh:203', 'interface:tag', 'baseMixin:2', 'mixinClass:new']),
        ('interfaces', args.interfaces_run_dir,
         ['existing:3:2', 'new:4:3', 'update:5', 'label:box', 'interfaces:true', 'covariance:true', 'tearoff:2:true', 'gc:6', 'closed:1:variant', 'growing:1', 'base:4', 'final:6'],
         ['existing:12:7', 'new:108:7', 'update:10', 'label:added', 'interfaces:true', 'covariance:true', 'tearoff:101:true', 'gc:110', 'closed:2:other', 'growing:3', 'base:5', 'final:7']),
        ('static', args.static_run_dir,
         ['add:5:3', 'get:3', 'set:5', 'compound:6:6', 'tearoff:14', 'tearoffIdentity:true', 'generic:4:s', 'genericIdentity:true', 'async:12', 'closure:19', 'instance:20', 'lazy:10:10:1', 'late:true:true:9', 'fresh:skipped', 'config:3:v3', 'defaults:3:3', 'changing:2', 'private:3:8', 'token:true', 'caught:Bad state: static-baseline', 'inherited:21', 'gc:24'],
         ['add:15:13', 'get:113', 'set:10', 'compound:111:222', 'tearoff:240', 'tearoffIdentity:true', 'generic:4:s', 'genericIdentity:true', 'async:338', 'closure:256', 'instance:267', 'lazy:20:20:1', 'late:true:true:9', 'fresh:17', 'config:7:v7', 'defaults:7:7', 'changing:text', 'private:3:8', 'token:true', 'caught:Bad state: static-patch', 'inherited:278', 'gc:292']),
        ('super_parameters', args.super_parameters_run_dir,
         ['positional:1:2:base', 'explicit:1:5:base', 'named:v:3:base', 'namedExplicit:v:6:base', 'grand:deep:2:base', 'default:4', 'body:4:8:base:5', 'override:3:11:base', 'sdk:3.141592653589793', 'raw:$value', 'private:10:11', 'const:true', 'type:true', 'added:7:2:base'],
         ['positional:1:2:patch', 'explicit:1:5:patch', 'named:v:3:patch', 'namedExplicit:v:6:patch', 'grand:deep:2:patch', 'default:9', 'body:4:8:patch:5', 'override:3:11:patch', 'sdk:3.141592653589793', 'raw:$value', 'private:10:11', 'const:true', 'type:true', 'added:7:2:patch']),
        ('type_names', args.type_names_run_dir,
         ["box:Box<int>|Instance of 'Box<int>'", 'nested:Box<Box<int>>', "local:_Local|Instance of '_Local'", "left:_Hidden|Instance of '_Hidden'", "right:_Hidden|Instance of '_Hidden'", 'privateDifferent:true', 'publicNames:Same|Same', 'publicDifferent:true', 'sameType:true', 'differentType:true', 'isBox:true', "layout:Layout|Instance of 'Layout'", "added:Box<int>|Instance of 'Box<int>'", 'revision:1', 'sdk:int|String'],
         ["box:Box<int>|Instance of 'Box<int>'", 'nested:Box<Box<int>>', "local:_Local|Instance of '_Local'", "left:_Hidden|Instance of '_Hidden'", "right:_Hidden|Instance of '_Hidden'", 'privateDifferent:true', 'publicNames:Same|Same', 'publicDifferent:true', 'sameType:true', 'differentType:true', 'isBox:true', "layout:Layout|Instance of 'Layout'", "added:Added<int>|Instance of 'Added<int>'", 'revision:2', 'sdk:int|String']),
        ('entities', args.entities_run_dir,
         ['calculate=207', 'reference=208', 'identity=true', 'binding=true'],
         ['calculate=407', 'reference=408', 'identity=true', 'binding=false']),
        ('closures', args.closures_run_dir,
         ['closure=12', 'capture=15', 'gc=16', 'exception=Bad state: baseline callback'],
         ['closure=14', 'capture=20', 'gc=22', 'exception=Bad state: patched callback']),
        ('libraries', args.libraries_run_dir,
         ['value=11', 'reference=11', 'private=12', 'cycle=1', 'selected=100'],
         ['value=118', 'reference=118', 'private=12', 'cycle=101', 'selected=200']),
        ('classes', args.classes_run_dir,
         ['base=14', 'virtual=24', 'direct=24', 'tearoff=26', 'captured=18', 'created=24',
          'caught=Bad state: baseline member', 'self=true', 'assignments=16', 'methodIdentity=true'],
         ['base=21', 'virtual=121', 'direct=121', 'tearoff=124', 'captured=30', 'created=124',
          'caught=Bad state: patched member', 'self=true', 'assignments=27', 'methodIdentity=true']),
        ('multilang', args.multilang_run_dir,
         ['wildcard=4', 'binding=3', 'legacy=6', 'bound=6', 'modern=5', 'gc=4', 'identity=true', 'className=Box'],
         ['wildcard=13', 'binding=6', 'legacy=24', 'bound=24', 'modern=14', 'gc=13', 'identity=true', 'className=Box']),
        ('multilang_added', args.multilang_added_run_dir,
         ['virtual=4'], ['virtual=14']),
        ('multilang_packages', args.multilang_packages_run_dir,
         ['compute=8', 'box=4', 'label=label-3', 'message=package'],
         ['compute=54', 'box=15', 'label=label-4', 'message=new-package']),
        ('packages', args.packages_run_dir,
         ['compute=8', 'box=4', 'label=label-3', 'message=package'],
         ['compute=54', 'box=15', 'label=label-4', 'message=new-package']),
        ('sdk', args.sdk_run_dir,
         ['sdkException=false', 'firstUse=baseline', 'bytes=4', 'shared=2', 'words=one:two', 'json=1', 'math=5', 'queue=4', 'iterable=6', 'future=3', 'stream=2', 'date=1'],
         ['sdkException=true', 'firstUse=QUI=', 'bytes=13', 'shared=11', 'words=one:two', 'json=10', 'math=14', 'queue=13', 'iterable=15', 'future=12', 'stream=11', 'date=10']),
        ('dynamic_calls', args.dynamic_calls_run_dir,
         ['retention=baseline', 'dynamic=3', 'callback=4', 'nullable=7:2:true', 'inherited=6:text', 'pattern', 'loop=24', 'async=3', 'futureType=false:false', 'future=1'],
         ['retained=14', 'getter=4', 'setter=6', 'tearoff=9', 'callbackDynamic=9', 'boundedDynamic=2.5', 'argumentCheck=true', 'setterCheck=true', 'boundCheck=true', 'missing=true', 'dynamicGc=10', 'newDynamic=106:106', 'unary=-5:-6', 'dynamic=12', 'callback=13', 'nullable=7:2:true', 'inherited=15:text', 'pattern', 'loop=33', 'async=12', 'futureType=false:false', 'future=1']),
        ('signatures', args.signatures_run_dir,
         ['dynamic=3:4:null:4', 'callback=4', 'nullable=7:2:true', 'inherited=6:text', 'pattern', 'loop=24', 'async=3', 'futureType=false:false', 'future=1'],
         ['dynamic=12:22:fallback:4', 'callback=13', 'nullable=7:2:true', 'inherited=15:text', 'pattern', 'loop=44', 'async=12', 'futureType=false:false', 'future=1']),
        ('inference', args.inference_run_dir,
         ['state=1:1', 'type=1:same', 'stored=3', 'default=2', 'generic=3:a', 'field=1:7'],
         ['state=10:10', 'type=word:same', 'stored=12', 'default=4', 'generic=3:a', 'field=4:7']),
        ('late_final', args.late_final_run_dir,
         ['uninitialized=true', 'shared=3:3', 'singleAssignment=true:3', 'unused=-1', 'lazy=10:10:1'],
         ['uninitialized=true', 'shared=8:8', 'singleAssignment=true:8', 'unused=42', 'lazy=20:20:1']),
        ('globals', args.globals_run_dir,
         ['unready=-1', 'held=12', 'shared=3:3', 'value=11', 'default=3', 'lazy=10:10:1', 'late=5:8'],
         ['unready=-1', 'held=7', 'shared=6:6', 'value=23', 'default=7', 'lazy=20:20:1', 'late=5:8']),
        ('layout', args.layout_run_dir,
         ['compute=8', 'fieldType=false', 'child=9', 'holder=8', 'worker=8', 'aotBase=9', 'default=5', 'type=true', 'gc=9', 'closed=7'],
         ['compute=31', 'fieldType=true', 'child=32', 'holder=31', 'worker=31', 'aotBase=32', 'default=20', 'type=true', 'gc=32', 'closed=14']),
        ('generic_classes', args.generic_classes_run_dir,
         ['virtual=4', 'type=int', 'shadow=String:s', 'map=mapped:4', 'getter=4', 'setter=6', 'futureType=false', 'async=1', 'covariance=true', 'gc=6', 'factory=3', 'factoryType=int', 'newGc=3', 'bounded=1.5'],
         ['virtual=9', 'type=patched:int', 'shadow=patched:String:s', 'map=mapped:4', 'getter=4', 'setter=6', 'futureType=false', 'async=2', 'covariance=true', 'gc=9', 'factory=9', 'factoryType=patched:int', 'newGc=9', 'bounded=2.5']),
        ('generics', args.generics_run_dir,
         ['int=1', 'string=left', 'callback=3', 'tearoff=4', 'bound=3', 'boundError=true', 'type=num:1', 'futureType=false', 'async=1', 'closure=a', 'virtual=4', 'gc=4'],
         ['int=2', 'string=right', 'callback=8', 'tearoff=7', 'bound=8', 'boundError=true', 'type=patched:num:1', 'futureType=false', 'async=2', 'closure=b', 'virtual=9', 'gc=9']),
        ('async', args.async_run_dir,
         ['futureType=false', 'wide=1', 'before=start,caller,', 'identity=true', 'ordered=1', 'after=start,caller,resume,', 'arrow=23', 'calculate=16', 'nested=32', 'method=13', 'closure=12', 'gc=13', 'caught=Bad state: baseline async'],
         ['futureType=false', 'wide=2', 'before=start,caller,', 'identity=true', 'ordered=2', 'after=start,caller,resume,', 'arrow=203', 'calculate=106', 'nested=212', 'method=16', 'closure=14', 'gc=16', 'caught=Bad state: patched async']),
        ('parameters', args.parameters_run_dir,
         ['named=11', 'explicit=19', 'optional=8', 'positional=12', 'method=20', 'methodExplicit=28', 'closure=9', 'closureExplicit=12', 'callback=11', 'tearoff=11'],
         ['named=111', 'explicit=119', 'optional=16', 'positional=24', 'method=165', 'methodExplicit=173', 'closure=27', 'closureExplicit=36', 'callback=111', 'tearoff=111']),
        ('accessors', args.accessors_run_dir,
         ['read=6', 'write=20', 'step=21', 'after=23', 'gc=23'],
         ['read=106', 'write=139', 'step=380', 'after=863', 'gc=863']),
        ('new-classes', args.new_classes_run_dir,
         ['virtual=7', 'field=5', 'label=base', 'tearoff=8', 'type=true', 'exact=true',
          'gc=7', 'nested=-3', 'write=22'],
         ['virtual=117', 'field=15', 'label=new', 'tearoff=118', 'type=true', 'exact=false',
          'gc=117', 'nested=118', 'write=122']),
    ]:
        if folder is None:
            continue
        folder = folder.resolve()
        before = digest(folder / 'baseline/app.aot')
        if kind in ['multilang', 'multilang_added', 'multilang_packages', 'parts_packages', 'named_mixin_multilang', 'typedef_multilang']:
            metadata = json.loads((folder / 'baseline/manifest.json').read_text())
            expected_versions = {'multilang': {'3.0', '3.12'},
                                 'multilang_added': {'3.0'},
                                 'multilang_packages': {'3.0', '3.1'}, 'parts_packages': {'3.0', '3.12'}, 'named_mixin_multilang': {'3.0', '3.12'}, 'typedef_multilang': {'3.0', '3.12'}}[kind]
            if set(metadata['library_language_versions'].values()) != expected_versions:
                raise ValueError('Fixture source language versions were not preserved')
            if kind == 'multilang_packages' and (
                    metadata['library_language_versions']['package:utility/utility.dart'] != '3.1' or
                    metadata['library_language_versions']['app:entry'] != '3.0'):
                raise ValueError('Package configuration language versions were not preserved')
            source_dart = RUNTIME.parent.parent / 'host_release_arm64/dart-sdk/bin/dart'
            inspector = ROOT / 'compiler/bin/inspect_kernel_languages.dart'
            result = execute(kind + '-kernel-languages', [source_dart,
                '--packages=' + str(ROOT / 'compiler/.dart_tool/package_config.json'), inspector,
                folder / 'baseline/no-aot.dill', folder / 'baseline'])
            versions = json.loads(result)
            for uri, name in metadata['emitted_libraries'].items():
                if versions.get(name) != metadata['library_language_versions'][uri]:
                    raise ValueError('CFE Kernel library language does not match original source')
            report[kind + '_kernel_languages'] = versions
            report['kernel_language_inspector_sha256'] = digest(inspector)
            if kind in ['named_mixin_multilang', 'typedef_multilang']:
                sdk = source_dart.parent.parent
                packages = ROOT / 'compiler/.dart_tool/package_config.json'
                kernel = destination / (kind + '-patch.dill')
                compiler = ROOT / '.engine-workspace/engine/engine/src/flutter/third_party/dart/pkg/vm/bin/gen_kernel.dart'
                execute(kind + '-patch-kernel', [source_dart, '--packages=' + str(packages), compiler,
                    '--no-aot', '--platform', sdk / 'lib/_internal/vm_platform_strong.dill', '--packages', packages,
                    '-Ddart.vm.product=true', '-Ddart.vm.profile=false', '--output', kernel, folder / 'patch/module.dart'])
                result = execute(kind + '-patch-kernel-languages', [source_dart, '--packages=' + str(packages), inspector,
                    kernel, folder / 'patch'])
                actual = json.loads(result)
                graph = json.loads((folder / 'patch/source_graph.json').read_text())
                if set(graph['library_language_versions'].values()) != {'3.0', '3.4', '3.12'}:
                    raise ValueError('Named mixin patch version fixture changed')
                for uri, version in graph['library_language_versions'].items():
                    name = 'unit_' + hashlib.sha256(uri.encode()).hexdigest() + '.dart'
                    if actual.get(name) != version:
                        raise ValueError('Patch Kernel language version differs from original library')
                report[kind + '_patch_kernel_languages'] = actual
                report[kind + '_patch_kernel_sha256'] = digest(kernel)


        baseline_output = execute(kind + '-baseline', [RUNTIME, folder / 'baseline/app.aot'], lines=expected_base)
        options = ['--new_gen_semi_max_size=1', '--verbose_gc'] if kind in ['closures', 'classes', 'new-classes', 'accessors', 'async', 'generics', 'generic_classes', 'layout', 'dynamic_calls', 'multilang', 'static', 'interfaces', 'mixins', 'factories', 'late_fields', 'late_references', 'operators', 'parts', 'sdk_interfaces', 'sdk_super', 'sdk_super_gc', 'sdk_mixins', 'super_fields', 'private_interfaces', 'named_mixins', 'named_mixin_relink', 'typedefs', 'typedef_relink'] else []
        output = execute(kind + '-patched', [RUNTIME, *options, folder / 'baseline/app.aot', folder / 'patch/patch.bytecode'],
                         contains=(['Scavenge('] if options else []), lines=expected_patch)
        if options:
            report[{'closures': 'closure_scavenges', 'classes': 'class_scavenges', 'new-classes': 'new_class_scavenges', 'accessors': 'accessor_scavenges', 'async': 'async_scavenges', 'generics': 'generic_scavenges', 'generic_classes': 'generic_class_scavenges', 'layout': 'layout_scavenges', 'dynamic_calls': 'dynamic_scavenges', 'multilang': 'multilang_scavenges', 'static': 'static_scavenges', 'interfaces': 'interface_scavenges', 'mixins': 'mixin_scavenges', 'factories': 'factory_scavenges', 'late_fields': 'late_field_scavenges', 'late_references': 'late_reference_scavenges', 'operators': 'operator_scavenges', 'parts': 'parts_scavenges', 'sdk_interfaces': 'sdk_interface_scavenges', 'sdk_super': 'sdk_super_scavenges', 'sdk_super_gc': 'sdk_super_new_object_scavenges', 'sdk_mixins': 'sdk_mixin_scavenges', 'super_fields': 'super_field_scavenges', 'private_interfaces': 'private_interface_scavenges', 'named_mixins': 'named_mixin_scavenges', 'named_mixin_relink': 'named_mixin_relink_scavenges', 'typedefs': 'typedef_scavenges', 'typedef_relink': 'typedef_relink_scavenges'}[kind]] = output.count('Scavenge(')
        if kind in ['async', 'generics', 'generic_classes', 'layout', 'globals', 'late_final', 'inference', 'signatures', 'dynamic_calls', 'sdk', 'packages', 'multilang', 'multilang_added', 'multilang_packages', 'type_names', 'super_parameters', 'static', 'interfaces', 'mixins', 'factories', 'late_fields', 'late_references', 'operators', 'operator_removal', 'operator_checks', 'parts', 'parts_packages', 'parts_private', 'sdk_interfaces', 'sdk_super', 'sdk_super_checks', 'sdk_super_gc', 'sdk_super_interfaces', 'sdk_mixins', 'sdk_mixin_relink', 'super_fields', 'private_interfaces', 'private_interface_added', 'private_interface_removed', 'named_mixins', 'named_mixin_interfaces', 'named_mixin_relink', 'named_mixin_multilang', 'named_mixin_retire', 'typedefs', 'typedef_relink', 'typedef_multilang', 'typedef_ancestors']:
            # Compare with the unmodified source compiled to ordinary AOT too;
            # the transformer and hand-written expected values are not oracles
            # for scheduling and type semantics by themselves.
            source_dart = RUNTIME.parent.parent / 'host_release_arm64/dart-sdk/bin/dart'
            for side, expected in [('baseline', expected_base), ('patch', expected_patch)]:
                graph = json.loads((folder / side / 'source_graph.json').read_text())
                source = destination / (kind + '-source-' + side + '.dart')
                if kind in ['packages', 'multilang', 'multilang_added', 'multilang_packages', 'type_names', 'super_parameters', 'static', 'interfaces', 'mixins', 'factories', 'late_fields', 'late_references', 'operators', 'operator_removal', 'operator_checks', 'parts', 'parts_packages', 'parts_private', 'sdk_interfaces', 'sdk_super', 'sdk_super_checks', 'sdk_super_gc', 'sdk_super_interfaces', 'sdk_mixins', 'sdk_mixin_relink', 'super_fields', 'private_interfaces', 'private_interface_added', 'private_interface_removed', 'named_mixins', 'named_mixin_interfaces', 'named_mixin_relink', 'named_mixin_multilang', 'named_mixin_retire', 'typedefs', 'typedef_relink', 'typedef_multilang', 'typedef_ancestors']:
                    reference = destination / (kind + '-reference-' + side)
                    reference.mkdir()
                    def library_path(uri):
                        if uri.startswith('package:'):
                            name, relative = uri.removeprefix('package:').split('/', 1)
                            path = reference / 'packages' / name / 'lib' / relative
                        else:
                            path = reference / ('app.dart' if uri == 'app:entry' else uri.removeprefix('app:'))
                        if not path.resolve().is_relative_to(reference.resolve()):
                            raise ValueError('Source archive path escapes reference directory')
                        return path
                    for uri, record in graph['libraries'].items():
                        path = library_path(graph.get('entry_package_uri') or uri) if uri == 'app:entry' else library_path(uri)
                        path.parent.mkdir(parents=True, exist_ok=True)
                        path.write_text(record['source'])
                        if uri == 'app:entry':
                            source = path
                    config = reference / '.dart_tool/package_config.json'
                    config.parent.mkdir()
                    config.write_text(json.dumps({'configVersion': 2, 'packages': [
                        {'name': name, 'rootUri': (reference / 'packages' / name).as_uri() + '/',
                         'packageUri': 'lib/', 'languageVersion': record['language_version'] or graph['language_version']}
                        for name, record in graph['packages'].items()
                    ] + ([] if graph.get('entry_package_uri') else [
                        {'name': 'archived_reference_app', 'rootUri': reference.as_uri() + '/',
                         'packageUri': 'app_lib/', 'languageVersion': graph['library_language_versions']['app:entry']}
                    ])}, indent=2))
                else:
                    if set(graph['libraries']) != {'app:entry'}:
                        raise ValueError('Source-reference fixture expects a single library')
                    source.write_text(graph['libraries']['app:entry']['source'])
                executable = destination / (kind + '-source-' + side)
                execute(kind + '-source-' + side + '-compile', [source_dart, 'compile', 'exe', source, '-o', executable])
                actual = execute(kind + '-source-' + side, [executable], lines=expected)
                report.setdefault(kind + '_source_reference_artifacts', {})[side] = {
                    'source_sha256': digest(source), 'executable_sha256': digest(executable),
                    'sdk_dart_sha256': digest(source_dart),
                    'source_graph_sha256': digest(folder / side / 'source_graph.json')}
                if actual.splitlines() != expected:
                    raise RuntimeError('Untransformed source differs from expected observable behavior')
            report[kind + '_source_aot_reference_matches'] = True
        if kind in ['typedefs', 'typedef_relink', 'typedef_multilang', 'typedef_ancestors']:
            clean = execute(kind + '-patched-clean', [RUNTIME, folder / 'baseline/app.aot', folder / 'patch/patch.bytecode'], lines=expected_patch)
            if baseline_output.splitlines() != expected_base or clean.splitlines() != expected_patch:
                raise RuntimeError('Typedef behavior differs from original-source AOT')
            metadata = json.loads((folder / 'patch/manifest.json').read_text())
            original = json.loads((folder / 'baseline/manifest.json').read_text())
            names = lambda field: sorted(metadata['entities'][symbol]['name'] for symbol in metadata[field])
            if kind == 'typedef_relink':
                if names('replaced_classes') != ['Holder'] or names('replaced_globals') != ['callback', 'selected'] or names('installed_functions') != ['main', 'make']:
                    raise RuntimeError('Changed alias targets must relink typed dependencies')
                if names('module_only_functions') != ['Holder.label', 'Holder.toString', 'consume', 'transform', 'typed']:
                    raise RuntimeError('Changed alias signatures must not enter old AOT slots')
                if sorted(original['entities'][s]['name'] for s in metadata['removed_type_aliases']) != ['Removed']:
                    raise RuntimeError('Removed typedef should not remove a runtime class')
            elif kind == 'typedef_ancestors':
                if names('replaced_classes') != ['Child', 'Parent'] or names('changed_type_aliases') != ['Children', 'ParentAlias']:
                    raise RuntimeError('Typedef must not hide closed ancestor relinking')
            else:
                installed = ['Box.bump', 'Box.label', 'add', 'later', 'make'] if kind == 'typedefs' else ['make']
                if names('replaced_classes') or names('module_only_functions') or names('installed_functions') != installed or names('added_classes') != ['Added']:
                    raise RuntimeError('Stable aliases must keep old AOT consumers and class identity')
            report[kind + '_aot_consumers_and_alias_semantics'] = True
        if kind in ['named_mixins', 'named_mixin_interfaces', 'named_mixin_relink', 'named_mixin_multilang', 'named_mixin_retire']:
            clean = execute(kind + '-patched-clean', [RUNTIME, folder / 'baseline/app.aot', folder / 'patch/patch.bytecode'], lines=expected_patch)
            if baseline_output.splitlines() != expected_base or clean.splitlines() != expected_patch:
                raise RuntimeError('Named mixin application differs from original-source AOT')
            metadata = json.loads((folder / 'patch/manifest.json').read_text())
            names = lambda field: sorted(metadata['entities'][symbol]['name'] for symbol in metadata[field])
            if kind == 'named_mixin_relink':
                if names('replaced_classes') != ['Again', 'Base', 'Child', 'Label', 'Named'] or 'consume' not in names('module_only_functions'):
                    raise RuntimeError('Changed constructor defaults must relink the alias family')
            elif kind == 'named_mixin_retire':
                if names('replaced_classes') != ['AliasPrivate'] or len(metadata['retired_infrastructure_classes']) != 5:
                    raise RuntimeError('Alias must retire only its unused interface helpers')
                if names('module_only_functions') or names('installed_functions') != ['Label.label', 'makePrivate']:
                    raise RuntimeError('Alias retirement must retain unrelated AOT consumers')
            else:
                expected = {'named_mixins': ['Label.label', 'make'], 'named_mixin_interfaces': ['Label.label'], 'named_mixin_multilang': ['make']}[kind]
                if names('replaced_classes') or names('module_only_functions') or names('installed_functions') != expected:
                    raise RuntimeError('Named mixin patch must preserve old classes and consumers')
            report[kind + '_aot_consumers_and_alias_semantics'] = True
        if kind in ['private_interfaces', 'private_interface_added', 'private_interface_removed']:
            clean = execute(kind + '-patched-clean', [RUNTIME, folder / 'baseline/app.aot', folder / 'patch/patch.bytecode'], lines=expected_patch)
            if baseline_output.splitlines() != expected_base or clean.splitlines() != expected_patch:
                raise RuntimeError('Private-interface behavior or error text differs from source AOT')
            metadata = json.loads((folder / 'patch/manifest.json').read_text())
            names = lambda field: sorted(metadata['entities'][symbol]['name'] for symbol in metadata[field])
            if names('installed_functions') != ['make'] or names('module_only_functions'):
                raise RuntimeError('Private-interface callers must retain AOT')
            if kind != 'private_interface_removed' and names('replaced_classes'):
                raise RuntimeError('Private-interface patch must keep baseline classes')
            if kind == 'private_interface_removed' and len(metadata['retired_infrastructure_classes']) != 6:
                raise RuntimeError('Only unused private-interface helpers may retire')
            report[kind + '_aot_consumers_and_private_errors'] = True
        if kind == 'super_fields':
            clean = execute(kind + '-patched-clean', [RUNTIME, folder / 'baseline/app.aot', folder / 'patch/patch.bytecode'], lines=expected_patch)
            if baseline_output.splitlines() != expected_base or clean.splitlines() != expected_patch:
                raise RuntimeError('Super field behavior differs from source AOT')
            metadata = json.loads((folder / 'patch/manifest.json').read_text())
            names = lambda field: sorted(metadata['entities'][symbol]['name'] for symbol in metadata[field])
            if names('replaced_classes') or names('added_classes') != ['Added']:
                raise RuntimeError('Super field patch must preserve baseline storage classes')
            for name in ['main', 'invoke', 'observe', 'churn', 'mockRead', 'Mock.noSuchMethod']:
                if name in names('changed_functions') or name in names('module_only_functions'):
                    raise RuntimeError('Super field consumer must retain AOT: ' + name)
            for name in ['Child.update', 'Child.firstSuper', 'PrivateChild.update', 'make']:
                if name not in names('installed_functions'):
                    raise RuntimeError('Super field method must execute patched code: ' + name)
            report['super_fields_aot_consumers_and_storage'] = True
        if kind in ['sdk_mixins', 'sdk_mixin_relink']:
            clean = execute(kind + '-patched-clean', [RUNTIME, folder / 'baseline/app.aot', folder / 'patch/patch.bytecode'], lines=expected_patch)
            if baseline_output.splitlines() != expected_base or clean.splitlines() != expected_patch:
                raise RuntimeError('SDK mixin behavior differs from source AOT')
            metadata = json.loads((folder / 'patch/manifest.json').read_text())
            names = lambda field: sorted(metadata['entities'][symbol]['name'] for symbol in metadata[field])
            if kind == 'sdk_mixins':
                if names('replaced_classes') or names('added_classes') != ['AddedMap']:
                    raise RuntimeError('SDK mixin fixture must keep baseline classes and add MapMixin application')
                retained = ['main', 'read', 'joined', 'ordered', 'total', 'churn', 'SDKConstraint.mapped', 'SDKConstraint.replace', 'SDKConstraint.count', 'Compared.comparer', 'MockList.noSuchMethod']
                for name in ['View.read', 'Mixed.joined', 'IntMixed.[]', 'SDKConstraint.readFirst', 'SDKConstraint.joined', 'Rank.compareTo']:
                    if name not in names('installed_functions'):
                        raise RuntimeError('SDK mixin method must execute patched code: ' + name)
            else:
                if names('replaced_classes') != ['Choosing', 'Chosen'] or names('added_classes'):
                    raise RuntimeError('First abstract super invocation must relink constraint mixin and application')
                retained = ['main', 'consume', 'Concrete.[]']
            for name in retained:
                if name in names('changed_functions') or name in names('module_only_functions'):
                    raise RuntimeError('SDK mixin consumer must retain AOT: ' + name)
            report[kind + '_aot_consumers_and_super_semantics'] = True
        if kind in ['sdk_super', 'sdk_super_checks', 'sdk_super_gc', 'sdk_super_interfaces']:
            clean = execute(kind + '-patched-clean', [RUNTIME, folder / 'baseline/app.aot', folder / 'patch/patch.bytecode'], lines=expected_patch)
            if baseline_output.splitlines() != expected_base or clean.splitlines() != expected_patch:
                raise RuntimeError('SDK super behavior differs from source AOT')
            metadata = json.loads((folder / 'patch/manifest.json').read_text())
            names = lambda field: sorted(metadata['entities'][symbol]['name'] for symbol in metadata[field])
            if names('replaced_classes'):
                raise RuntimeError('SDK super fixture must retain baseline classes')
            if kind == 'sdk_super':
                if names('added_classes') != ['AddedError', 'FreshMap', 'Node']:
                    raise RuntimeError('SDK fixture must introduce three SDK subclasses')
                for name in ['main', 'make', 'sorted', 'mapTotal', 'caught', 'churn', 'Bag.copy', 'Bag.mapped', 'Joined.marked']:
                    if name in names('changed_functions') or name in names('module_only_functions'):
                        raise RuntimeError('SDK super consumer must retain baseline AOT: ' + name)
                for name in ['Bag.front', 'Bag.render', 'IntBag.[]', 'IntBag.[]=', 'View.step', 'Failure.toString', 'Bounds.nudge']:
                    if name not in names('installed_functions'):
                        raise RuntimeError('SDK super helper must execute patched code: ' + name)
            elif kind == 'sdk_super_gc':
                if names('added_classes') != ['FreshError', 'FreshMap']:
                    raise RuntimeError('GC fixture must retain new SDK subclasses')
                for name in ['main', 'total']:
                    if name in names('changed_functions') or name in names('module_only_functions'):
                        raise RuntimeError('GC consumers must retain original AOT: ' + name)
            elif kind == 'sdk_super_interfaces':
                if names('changed_functions') != ['BaseView.read']:
                    raise RuntimeError('Only the real superclass implementation must change')
                for name in ['main', 'consume', 'update', 'Implemented.read', 'Mock.noSuchMethod']:
                    if name in names('module_only_functions'):
                        raise RuntimeError('Interface consumer must retain AOT: ' + name)
            elif names('changed_functions') != ['Child.index']:
                raise RuntimeError('SDK index check caller must remain in baseline AOT')
            report[kind + '_aot_consumers_and_super_semantics'] = True
        if kind == 'sdk_interfaces':
            clean = execute('sdk-interfaces-patched-clean', [RUNTIME, folder / 'baseline/app.aot', folder / 'patch/patch.bytecode'], lines=expected_patch)
            if baseline_output.splitlines() != expected_base or clean.splitlines() != expected_patch:
                raise RuntimeError('SDK interface behavior differs from source AOT')
            metadata = json.loads((folder / 'patch/manifest.json').read_text())
            names = lambda field: sorted(metadata['entities'][symbol]['name'] for symbol in metadata[field])
            if names('added_classes') != ['AddedRank', 'Numbers', 'Trouble'] or names('replaced_classes'):
                raise RuntimeError('SDK interface fixture must retain baseline classes and add implementations')
            for name in ['main', 'ordered', 'encoded', 'compare', 'consume', 'caught', 'rejects', 'churn']:
                if name in names('changed_functions') or name in names('module_only_functions'):
                    raise RuntimeError('SDK interface consumer must retain baseline AOT: ' + name)
            for name in ['Rank.compareTo', 'TextSink.add']:
                if name not in names('installed_functions'):
                    raise RuntimeError('SDK must call the patched method: ' + name)
            report['sdk_interface_aot_consumers_and_callbacks'] = True
        if kind == 'parts_private':
            clean = execute('parts-private-patched-clean', [RUNTIME, folder / 'baseline/app.aot', folder / 'patch/patch.bytecode'], lines=expected_patch)
            if baseline_output.splitlines() != expected_base or clean.splitlines() != expected_patch:
                raise RuntimeError('Dynamic part privacy differs from original source AOT')
            metadata = json.loads((folder / 'patch/manifest.json').read_text())
            changed = metadata['changed_functions']
            if metadata['replaced_classes'] or len(changed) != 1:
                raise RuntimeError('Dynamic private callers and classes must retain AOT')
            entity = metadata['entities'][changed[0]]
            if entity['name'] != '_Box._read' or entity['library'] != 'app:entry':
                raise RuntimeError('The wrong owning library private method changed')
            report['parts_private_dynamic_owner_isolation'] = True
        if kind in ['parts', 'parts_packages']:
            clean = execute(kind + '-patched-clean', [RUNTIME, folder / 'baseline/app.aot', folder / 'patch/patch.bytecode'], lines=expected_patch)
            if baseline_output.splitlines() != expected_base or clean.splitlines() != expected_patch:
                raise RuntimeError('Part library behavior differs from original source AOT')
            metadata = json.loads((folder / 'patch/manifest.json').read_text())
            graph = json.loads((folder / 'patch/source_graph.json').read_text())
            names = lambda field: sorted(metadata['entities'][symbol]['name'] for symbol in metadata[field])
            if metadata['replaced_classes'] or names('added_classes') != ['Added']:
                raise RuntimeError('Moving a declaration between parts changed its class identity')
            retained = ['main', 'invoke', 'stableRead', 'churn'] if kind == 'parts' else ['main', 'consume']
            for name in retained:
                if name in names('changed_functions'):
                    raise RuntimeError('Part consumer lost baseline AOT: ' + name)
            if kind == 'parts':
                if graph['libraries']['app:moved.dart']['owner'] != 'app:entry' or graph['libraries']['app:other_part.dart']['owner'] != 'app:other.dart':
                    raise RuntimeError('Private library ownership was lost')
                hidden = [key for key, value in metadata['entities'].items() if value['name'] == '_Hidden']
                if len(set(hidden)) != 2 or 'callback' not in names('installed_functions'):
                    raise RuntimeError('Private type separation or bytecode closure missing')
            else:
                if graph['libraries']['package:piece/src/moved.dart']['owner'] != 'package:piece/piece.dart':
                    raise RuntimeError('Package part lost its owner')
                if graph['library_language_versions'] != {'app:entry': '3.12', 'package:piece/piece.dart': '3.0'}:
                    raise RuntimeError('Parts must use their owning library language version')
            report[kind + '_owner_identity_and_aot_consumers'] = True
        if kind == 'operator_checks':
            clean = execute('operator-checks-patched-clean', [RUNTIME, folder / 'baseline/app.aot', folder / 'patch/patch.bytecode'], lines=expected_patch)
            if baseline_output.splitlines() != expected_base or clean.splitlines() != expected_patch:
                raise RuntimeError('Super index argument checking order differs from source AOT')
            metadata = json.loads((folder / 'patch/manifest.json').read_text())
            changed = sorted(metadata['entities'][x]['name'] for x in metadata['changed_functions'])
            if metadata['replaced_classes'] or changed != ['Child.index']:
                raise RuntimeError('Argument checking must be exercised through retained AOT run/main')
            report['operator_index_type_checks_before_rhs'] = True
        if kind == 'operator_removal':
            clean = execute('operator-removal-patched-clean', [RUNTIME, folder / 'baseline/app.aot', folder / 'patch/patch.bytecode'], lines=expected_patch)
            if baseline_output.splitlines() != expected_base or clean.splitlines() != expected_patch:
                raise RuntimeError('Removed operator behavior differs from independent source AOT')
            metadata = json.loads((folder / 'patch/manifest.json').read_text())
            names = lambda field: sorted(metadata['entities'][symbol]['name'] for symbol in metadata[field])
            retired = metadata['retired_infrastructure_classes']
            baseline_metadata = json.loads((folder / 'baseline/manifest.json').read_text())
            if names('replaced_classes') != ['Base', 'Child'] or len(retired) != 1:
                raise RuntimeError('Removed index operator did not relocate its class family')
            if baseline_metadata['entities'][retired[0]].get('generated') != 'super-index-cell':
                raise RuntimeError('Retirement exception allowed a user class')
            report['operator_removal_retires_only_infrastructure'] = True
        if kind == 'operators':
            clean = execute('operators-patched-clean', [RUNTIME, folder / 'baseline/app.aot', folder / 'patch/patch.bytecode'], lines=expected_patch)
            if baseline_output.splitlines() != expected_base or clean.splitlines() != expected_patch:
                raise RuntimeError('Operator behavior differs from independent source AOT')
            metadata = json.loads((folder / 'patch/manifest.json').read_text())
            names = lambda field: sorted(metadata['entities'][symbol]['name'] for symbol in metadata[field])
            if names('replaced_classes') or names('added_classes') != ['Added']:
                raise RuntimeError('Operator-only changes must retain baseline classes')
            for name in ['main', 'invoke', 'negative', 'dynamicOps', 'equal', 'churn', 'IndexChild.asyncAdd', 'IndexChild.failed']:
                if name in names('changed_functions') or name in names('module_only_functions'):
                    raise RuntimeError('Operator consumers must retain baseline AOT: ' + name)
            if not {'Num.-', 'Num.unary-', 'Num.+', 'Num.==', 'IndexChild.addedSuper', 'Strings.append'}.issubset(names('installed_functions')):
                raise RuntimeError('Operator methods and new super-index operations must execute patch code')
            report['operator_aot_consumers_and_super_ordering'] = True
        if kind == 'late_references':
            clean = execute('late-references-patched-clean', [RUNTIME, folder / 'baseline/app.aot', folder / 'patch/patch.bytecode'], lines=expected_patch)
            if baseline_output.splitlines() != expected_base or clean.splitlines() != expected_patch:
                raise RuntimeError('Late reference behavior differs from independent source AOT')
            metadata = json.loads((folder / 'patch/manifest.json').read_text())
            names = lambda field: sorted(metadata['entities'][symbol]['name'] for symbol in metadata[field])
            if names('replaced_classes') or names('changed_functions') != ['fill', 'replace']:
                raise RuntimeError('Late reference storage and AOT consumers must be retained')
            report['late_reference_aot_storage_and_gc'] = True
        if kind == 'late_fields':
            clean = execute('late-fields-patched-clean', [RUNTIME, folder / 'baseline/app.aot', folder / 'patch/patch.bytecode'], lines=expected_patch)
            if baseline_output.splitlines() != expected_base or clean.splitlines() != expected_patch:
                raise RuntimeError('Late field behavior differs from independent source AOT')
            metadata = json.loads((folder / 'patch/manifest.json').read_text())
            names = lambda field: sorted(metadata['entities'][symbol]['name'] for symbol in metadata[field])
            if names('replaced_classes') != ['Shape']:
                raise RuntimeError('Late field storage dependencies were not relinked')
            for name in ['read', 'assign', 'duplicate', 'duplicateOnly', 'uninitialized', 'onlyValue', 'churn']:
                if name in names('changed_functions') or name in names('module_only_functions'):
                    raise RuntimeError('Late field consumers must retain baseline AOT: ' + name)
            if not {'Box.initialize', 'setOnly'}.issubset(names('installed_functions')):
                raise RuntimeError('Late initialization and first-write must execute patch code')
            report['late_field_aot_storage_and_layout_relinking'] = True
        if kind == 'factories':
            clean = execute('factories-patched-clean', [RUNTIME, folder / 'baseline/app.aot', folder / 'patch/patch.bytecode'], lines=expected_patch)
            if baseline_output.splitlines() != expected_base or clean.splitlines() != expected_patch:
                raise RuntimeError('Factory behavior differs from independent source AOT')
            metadata = json.loads((folder / 'patch/manifest.json').read_text())
            names = lambda field: sorted(metadata['entities'][symbol]['name'] for symbol in metadata[field])
            if names('replaced_classes') != ['Cached', 'Choice', 'Original'] or names('added_classes') != ['Added']:
                raise RuntimeError('Factory target dependencies were not relinked')
            for name in ['read', 'build', 'caught', 'churn']:
                if name in names('changed_functions') or name in names('module_only_functions'):
                    raise RuntimeError('Factory consumers must retain baseline AOT: ' + name)
            report['factory_aot_consumers_and_redirect_relinking'] = True
        if kind == 'mixins':
            clean = execute('mixins-patched-clean', [RUNTIME, folder / 'baseline/app.aot', folder / 'patch/patch.bytecode'], lines=expected_patch)
            if baseline_output.splitlines() != expected_base or clean.splitlines() != expected_patch:
                raise RuntimeError('Mixin behavior differs from independent source AOT')
            metadata = json.loads((folder / 'patch/manifest.json').read_text())
            names = lambda field: sorted(metadata['entities'][symbol]['name'] for symbol in metadata[field])
            if names('replaced_classes') != ['Shape', 'Shaped'] or names('added_classes') != ['Added', 'Fresh', 'Freshly']:
                raise RuntimeError('Mixin layout/application dependencies were not relinked')
            for name in ['invoke', 'choose', 'churn']:
                if name in names('changed_functions') or name in names('module_only_functions'):
                    raise RuntimeError('Mixin consumers must retain baseline AOT: ' + name)
            if 'First.callback' not in names('installed_functions'):
                raise RuntimeError('GC callback must originate in patch bytecode')
            if 'shape' not in names('module_only_functions') or 'shape' in names('installed_functions'):
                raise RuntimeError('Changed mixin layout crossed an old typed slot')
            report['mixin_aot_consumers_and_layout_relinking'] = True
        if kind == 'interfaces':
            clean = execute('interfaces-patched-clean', [RUNTIME, folder / 'baseline/app.aot', folder / 'patch/patch.bytecode'], lines=expected_patch)
            if baseline_output.splitlines() != expected_base or clean.splitlines() != expected_patch:
                raise RuntimeError('Interface behavior differs from independent source AOT')
            metadata = json.loads((folder / 'patch/manifest.json').read_text())
            names = lambda field: sorted(metadata['entities'][symbol]['name'] for symbol in metadata[field])
            if names('replaced_classes') != ['BaseFamily', 'BaseImpl', 'Closed', 'FinalFamily', 'FinalImpl', 'Growing', 'GrowingImpl', 'Variant']:
                raise RuntimeError('Closed/interface type families were not completely relinked')
            if names('added_classes') != ['Added', 'BaseOther', 'FinalOther', 'Other']:
                raise RuntimeError('The fixture must exercise new implementations')
            for name in ['read', 'choose', 'update', 'label', 'conforms', 'rejects', 'churn']:
                if name in names('changed_functions') or name in names('module_only_functions'):
                    raise RuntimeError('Open-interface consumers must remain in original AOT: ' + name)
            for name in ['readClosed', 'closedTag', 'readGrowing', 'readBase', 'readFinal']:
                if name not in names('module_only_functions') or name in names('installed_functions'):
                    raise RuntimeError('Closed interface type crossed an old dispatch slot: ' + name)
            report['interface_consumers_and_closed_family_relinking'] = True
        if kind == 'static':
            clean = execute('static-patched-clean', [RUNTIME, folder / 'baseline/app.aot', folder / 'patch/patch.bytecode'], lines=expected_patch)
            if baseline_output.splitlines() != expected_base or clean.splitlines() != expected_patch:
                raise RuntimeError('Static member results differ from independent source AOT')
            metadata = json.loads((folder / 'patch/manifest.json').read_text())
            names = lambda field: sorted(metadata['entities'][symbol]['name'] for symbol in metadata[field])
            if names('replaced_classes') != ['Changing', 'Config', 'Settings']:
                raise RuntimeError('Static state was not shared/relinked at the correct class boundary')
            changed = names('changed_functions')
            if any(name in changed for name in ['stableRead', 'stableToken', 'caught', 'invoke', 'churn']):
                raise RuntimeError('Static state/closure/exception consumers must remain in AOT')
            if 'Changing.read' not in names('module_only_functions') or 'Changing.read' in names('installed_functions'):
                raise RuntimeError('Changed static signature crossed an old dispatch slot')
            if 'Counter.callback' not in names('installed_functions'):
                raise RuntimeError('GC fixture must create its closure from patched bytecode')
            report['static_state_aot_consumers_and_signature_relinking'] = True
        if kind == 'super_parameters':
            if baseline_output.splitlines() != expected_base or output.splitlines() != expected_patch:
                raise RuntimeError('Constructor forwarding differs from independent AOT')
            metadata = json.loads((folder / 'patch/manifest.json').read_text())
            invoke = next(symbol for symbol, entity in metadata['entities'].items()
                          if entity['name'] == 'invoke' and entity['library'] == 'app:entry')
            if invoke in metadata['changed_functions'] or invoke in metadata['module_only_functions']:
                raise RuntimeError('The new subclass consumer must remain in original AOT')
            replaced = sorted(metadata['entities'][symbol]['name'] for symbol in metadata['replaced_classes'])
            if replaced != ['Defaults', 'ForwardDefault']:
                raise RuntimeError('Inherited constructor defaults did not relink exactly the affected classes')
            report['super_parameters_retained_aot_and_default_relinking'] = True
        if kind == 'type_names':
            if baseline_output.splitlines() != expected_base or output.splitlines() != expected_patch:
                raise RuntimeError('Class display results differ from independent AOT')
            metadata = json.loads((folder / 'patch/manifest.json').read_text())
            describe = next(symbol for symbol, entity in metadata['entities'].items()
                            if entity['name'] == 'describe' and entity['library'] == 'app:entry')
            if describe in metadata['changed_functions'] or describe in metadata['module_only_functions']:
                raise RuntimeError('The type display caller must remain in original AOT')
            report['type_name_display_caller_retains_aot'] = True
            # Use the real custom snapshot compiler/runtime with source that
            # bypasses the linker, proving the display ABI does not rewrite
            # ordinary libraries or malformed/legacy names.
            build = json.loads((folder / 'build.json').read_text())
            source = destination / 'display-name-guards.dart'
            kernel = destination / 'display-name-guards.dill'
            snapshot = destination / 'display-name-guards.aot'
            encoded = 'msbEntity_class_' + 'a' * 64 + '__Original'
            malformed = 'msbEntity_class_' + 'g' * 64 + '__Original'
            legacy = 'msbEntity_class_' + 'a' * 64
            short = 'msbEntity_class_a__Original'
            empty = 'msbEntity_class_' + 'a' * 64 + '__'
            dollar_name = 'msbEntity_class_' + 'b' * 64 + '__Dollar$Name'
            names = [encoded, malformed, legacy, short, empty, dollar_name]
            for marked in [False, True]:
                label = 'marked' if marked else 'ordinary'
                source.write_text(('library simurgh_generated_v1;\n' if marked else '') +
                    '\n'.join('class ' + name + ' {}' for name in names) +
                    '\nvoid main() {\n' +
                    '\n'.join('print(' + name + '().runtimeType);' for name in names) + '\n}\n')
                command = next(step['command'].copy() for step in build['steps'] if step['name'] == 'kernel-aot')
                index = command.index('--dynamic-interface')
                del command[index:index + 2]
                command[command.index('--output') + 1] = str(kernel)
                command[-1] = str(source)
                execute('display-guards-' + label + '-kernel', command)
                compiler = next(step['command'].copy() for step in build['steps'] if step['name'] == 'snapshot')
                compiler[-2] = '--elf=' + str(snapshot)
                compiler[-1] = str(kernel)
                execute('display-guards-' + label + '-snapshot', compiler)
                expected = names.copy()
                if marked:
                    expected[0] = 'Original'
                    expected[-1] = 'Dollar$Name'
                actual = execute('display-guards-' + label, [RUNTIME, snapshot], lines=expected)
                if actual.splitlines() != expected:
                    raise RuntimeError('Display-name guard changed ordinary or malformed names')
            report['display_name_guards_passed'] = True
        if kind == 'classes':
            build = json.loads((folder / 'build.json').read_text())
            compiler = next(step['command'].copy() for step in build['steps'] if step['name'] == 'snapshot')
            if digest(Path(compiler[0])) != build['runtime_provenance']['artifacts']['gen_snapshot']:
                raise ValueError('Snapshot compiler differs from class build evidence')
            traced = destination / 'classes-traced.aot'
            compiler = [('--elf=' + str(traced)) if arg.startswith('--elf=') else arg for arg in compiler]
            # These flags only print diagnostics; do not alter inlining policy.
            compiler[1:1] = ['--trace-inlining', '--print-flow-graph-filter=main', '--print-flow-graph-optimized']
            trace = execute('classes-optimizer', compiler)
            class_manifest = json.loads((folder / 'baseline/manifest.json').read_text())
            def class_symbol(name):
                return next(key for key, value in class_manifest['entities'].items()
                            if value['library'] == 'app:child.dart' and value['name'] == name)
            child, helper = class_symbol('Child'), class_symbol('Child.compute')
            candidates = trace.split('\n  => ')
            # The trace heading uses the restored display name. Prove the
            # exact internal class/method identity from its regular-function
            # graph as well, excluding tear-offs with the same display heading.
            display = class_manifest['entities'][child]['name']
            method_graph = r'^==== [^\n]*app.dart_' + re.escape(child) + r'_compute \(RegularFunction\)$'
            inlined = any(chunk.startswith(display + '.compute ') and
                          re.search(method_graph, chunk, re.M) and
                          '\n     Success\n' in chunk for chunk in candidates)
            final_graphs = re.findall(r'After AllocateRegisters\n==== [^\n]*app.dart_::_main \(RegularFunction\)\n(.*?)\*\*\* END CFG', trace, re.S)
            direct = any(re.search(r'StaticCall[^\n]*' + re.escape(helper), graph) for graph in final_graphs)
            evidence = {'name': 'classes-optimizer-evidence', 'method_wrapper_inlined': inlined,
                        'optimized_main_calls_replaceable_entry_directly': direct, 'passed': inlined and direct}
            report['checks'].append(evidence)
            (destination / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
            if not evidence['passed']:
                raise RuntimeError('Class optimizer evidence missing; inspect classes-optimizer.log')
            execute('classes-traced-baseline', [RUNTIME, traced], lines=expected_base)
            execute('classes-traced-patched', [RUNTIME, traced, folder / 'patch/patch.bytecode'], lines=expected_patch)
            report['traced_class_aot_sha256'] = digest(traced)
        if digest(folder / 'baseline/app.aot') != before:
            raise ValueError(f'{kind} baseline AOT binary changed')
    manifest = json.loads((run / 'baseline/manifest.json').read_text())
    key = manifest['baseline_fingerprint']
    def symbol(name):
        return next(key for key, value in manifest['entities'].items()
                    if value['library'] == 'app:entry' and value['name'] == name)
    calculate, fail = symbol('calculate'), symbol('fail')
    base_import = json.dumps((run / 'baseline/app.dart').as_uri())
    modules = {
        'wrong-baseline': ("baseline.simurghInstall('wrong', {});", 1, ['Wrong baseline fingerprint']),
        'wrong-signature-atomic': (f"""
try {{
  baseline.simurghInstall('{key}', {{
    '{calculate}': (int value) => 999,
    '{fail}': (int value) => value,
  }});
}} catch (error) {{
  if (!error.toString().contains('Patch signature mismatch')) rethrow;
  if (baseline.{calculate}(100) != 207) throw StateError('Partial slot mutation');
  print('SIGNATURE_REJECTED_WITHOUT_MUTATION');
  return;
}}
throw StateError('Invalid replacement was accepted');
""", 0, ['SIGNATURE_REJECTED_WITHOUT_MUTATION', 'calculate=207']),
    }
    template = next(s['command'] for s in manifests[0]['steps'] if s['name'] == 'bytecode')
    for name, (body, expected, output) in modules.items():
        source = destination / (name + '.dart')
        source.write_text(f"import {base_import} as baseline;\n@pragma('dyn-module:entry-point')\nvoid main() {{\n{body}\n}}\n")
        bytecode = destination / (name + '.bytecode')
        command = template.copy()
        command[command.index('--output') + 1] = str(bytecode)
        command[-1] = str(source)
        execute(name + '-compile', command)
        execute(name, [RUNTIME, run / 'baseline/app.aot', bytecode], expected_exit=expected, contains=output)
    if args.parameters_run_dir:
        parameter_run = args.parameters_run_dir.resolve()
        parameter_manifest = json.loads((parameter_run / 'baseline/manifest.json').read_text())
        parameter_build = json.loads((parameter_run / 'build.json').read_text())
        def parameter_symbol(name):
            return next(key for key, value in parameter_manifest['entities'].items()
                        if value['library'] == 'app:entry' and value['name'] == name)
        adjust, optional = parameter_symbol('adjust'), parameter_symbol('optional')
        parameter_import = json.dumps((parameter_run / 'baseline/app.dart').as_uri())
        parameter_key = parameter_manifest['baseline_fingerprint']
        source = destination / 'named-signature-atomic.dart'
        source.write_text(f"""import {parameter_import} as baseline;
@pragma('dyn-module:entry-point')
void main() {{
  try {{
    baseline.simurghInstall('{parameter_key}', {{
      '{optional}': (int value, [int delta = 3]) => 999,
      '{adjust}': (int value, {{required int bias}}) => 999,
    }});
  }} catch (error) {{
    if (!error.toString().contains('Patch signature mismatch')) rethrow;
    if (baseline.{optional}(5) != 8) throw StateError('Partial named-slot mutation');
    if (baseline.{adjust}(5, bias: 1) != 11) throw StateError('Invalid named slot installed');
    print('NAMED_SIGNATURE_REJECTED_WITHOUT_MUTATION');
    return;
  }}
  throw StateError('Missing named parameter accepted');
}}
""")
        bytecode = destination / 'named-signature-atomic.bytecode'
        command = next(step['command'].copy() for step in parameter_build['steps'] if step['name'] == 'bytecode')
        command[command.index('--output') + 1] = str(bytecode)
        command[-1] = str(source)
        execute('named-signature-atomic-compile', command)
        execute('named-signature-atomic', [RUNTIME, parameter_run / 'baseline/app.aot', bytecode],
                contains=['NAMED_SIGNATURE_REJECTED_WITHOUT_MUTATION'], lines=['named=11', 'optional=8'])
        if digest(parameter_run / 'baseline/app.aot') != parameter_build['artifacts']['baseline/app.aot']['sha256']:
            raise ValueError('Parameter baseline AOT binary changed')
    if args.generics_run_dir:
        generic_run = args.generics_run_dir.resolve()
        generic_manifest = json.loads((generic_run / 'baseline/manifest.json').read_text())
        generic_build = json.loads((generic_run / 'build.json').read_text())
        def generic_symbol(name):
            return next(key for key, value in generic_manifest['entities'].items()
                        if value['library'] == 'app:entry' and value['name'] == name)
        choose, typed = generic_symbol('choose'), generic_symbol('typed')
        generic_import = json.dumps((generic_run / 'baseline/app.dart').as_uri())
        generic_key = generic_manifest['baseline_fingerprint']
        source = destination / 'generic-signature-atomic.dart'
        source.write_text(f"""import {generic_import} as baseline;
@pragma('dyn-module:entry-point')
void main() {{
  try {{
    baseline.simurghInstall('{generic_key}', {{
      '{typed}': <T>(T value) => 'BAD',
      '{choose}': <T extends num>(T first, T second) => first,
    }});
  }} catch (error) {{
    if (!error.toString().contains('Patch signature mismatch')) rethrow;
    if (baseline.{typed}<num>(1) != 'num:1') throw StateError('Partial generic-slot mutation');
    if (baseline.{choose}<String>('a', 'b') != 'a') throw StateError('Constrained generic slot installed');
    print('GENERIC_SIGNATURE_REJECTED_WITHOUT_MUTATION');
    return;
  }}
  throw StateError('Stricter generic bound accepted');
}}
""")
        bytecode = destination / 'generic-signature-atomic.bytecode'
        command = next(step['command'].copy() for step in generic_build['steps'] if step['name'] == 'bytecode')
        command[command.index('--output') + 1] = str(bytecode)
        command[-1] = str(source)
        execute('generic-signature-atomic-compile', command)
        execute('generic-signature-atomic', [RUNTIME, generic_run / 'baseline/app.aot', bytecode],
                contains=['GENERIC_SIGNATURE_REJECTED_WITHOUT_MUTATION'], lines=['int=1', 'type=num:1'])
        if digest(generic_run / 'baseline/app.aot') != generic_build['artifacts']['baseline/app.aot']['sha256']:
            raise ValueError('Generic baseline AOT binary changed')
    if args.layout_run_dir:
        layout_run = args.layout_run_dir.resolve()
        layout_manifest = json.loads((layout_run / 'baseline/manifest.json').read_text())
        layout_build = json.loads((layout_run / 'build.json').read_text())
        def layout_symbol(name):
            return next(key for key, value in layout_manifest['entities'].items()
                        if value['library'] == 'app:entry' and value['name'] == name)
        check_type, method, box = layout_symbol('isBox'), layout_symbol('Box.compute'), layout_symbol('Box')
        layout_key = layout_manifest['baseline_fingerprint']
        original_module = (layout_run / 'patch/module.dart').read_text()
        source = destination / 'layout-signature-atomic.dart'
        source.write_text(original_module.split("@pragma('dyn-module:entry-point')")[0] + f"""
@pragma('dyn-module:entry-point')
void main() {{
  try {{
    simurghBaseline.simurghInstall('{layout_key}', {{
      '{check_type}': simurghPatch_{check_type},
      '{method}': simurghPatch_{method},
    }});
  }} catch (error) {{
    if (!error.toString().contains('Patch signature mismatch')) rethrow;
    if (!simurghBaseline.{check_type}(simurghBaseline.{box}(1))) {{
      throw StateError('Partial layout-slot mutation');
    }}
    print('LAYOUT_SIGNATURE_REJECTED_WITHOUT_MUTATION');
    return;
  }}
  throw StateError('New class identity accepted in old receiver slot');
}}
""")
        bytecode = destination / 'layout-signature-atomic.bytecode'
        command = next(step['command'].copy() for step in layout_build['steps'] if step['name'] == 'bytecode')
        command[command.index('--output') + 1] = str(bytecode)
        command[-1] = str(source)
        execute('layout-signature-atomic-compile', command)
        execute('layout-signature-atomic', [RUNTIME, layout_run / 'baseline/app.aot', bytecode],
                contains=['LAYOUT_SIGNATURE_REJECTED_WITHOUT_MUTATION'], lines=['compute=8', 'fieldType=false', 'closed=7'])
        if digest(layout_run / 'baseline/app.aot') != layout_build['artifacts']['baseline/app.aot']['sha256']:
            raise ValueError('Layout baseline AOT binary changed')
    if args.signatures_run_dir:
        signature_run = args.signatures_run_dir.resolve()
        build = json.loads((signature_run / 'build.json').read_text())
        source = destination / 'unsupported-dynamic-call.dart'
        source.write_text("dynamic call(dynamic value) => value.simurghUnlistedSelector();\n@pragma('dyn-module:entry-point') dynamic main() => call(1);\n")
        bytecode = destination / 'unsupported-dynamic-call.bytecode'
        command = next(step['command'].copy() for step in build['steps'] if step['name'] == 'bytecode')
        command[command.index('--output') + 1] = str(bytecode)
        command[-1] = str(source)
        execute('unsupported-dynamic-call', command, expected_exit=1,
                contains=['Dynamic calls are not allowed in a dynamic module'])
        if bytecode.exists():
            raise ValueError('Rejected dynamic call unexpectedly produced a bytecode artifact')
        report['dynamic_call_validation_kept_enabled'] = True
    if digest(run / 'baseline/app.aot') != aot_hash:
        raise ValueError('Baseline AOT binary changed')
    report['baseline_aot_unchanged'] = True
    (destination / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'checks_passed': len(report['checks']), 'scavenges': report['observed_scavenges'], 'report': str(destination / 'report.json')}))


if __name__ == '__main__':
    main()
