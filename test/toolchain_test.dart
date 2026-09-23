import 'dart:io';

import 'package:simurgh_cli/src/common.dart';
import 'package:simurgh_cli/src/toolchain.dart';
import 'package:test/test.dart';

void main() {
  late Toolchain chain;
  setUp(() async {
    chain = Toolchain(await readObject('toolchain.lock.json'));
  });
  test('lock is valid and identity is stable across JSON key order', () {
    chain.validate();
    expect(digestJson({'a': 1, 'b': 2}), digestJson({'b': 2, 'a': 1}));
    expect(chain.id, startsWith('m0-'));
    expect(chain.lock['runtime_implemented'], isFalse);
  });
  test('rejects same version with a different engine build', () {
    final installed = {
      'frameworkVersion': chain.lock['flutter_version'],
      'dartSdkVersion': chain.lock['dart_version'],
      'frameworkRevision': chain.lock['framework_revision'],
      'engineRevision': '0' * 40,
      'channel': 'stable',
    };
    expect(
      chain.versionMismatches(installed).single,
      startsWith('engineRevision:'),
    );
  });
  test('space gate boundary cannot be rounded up', () {
    const minimum = 214748364800;
    expect(workspaceCheck(minimum - 1, minimum)['passed'], isFalse);
    expect(workspaceCheck(minimum, minimum)['passed'], isTrue);
  });
  test('cannot reduce engine workspace budget in lock', () {
    chain.lock['engine_workspace_min_free_bytes'] = 1;
    expect(chain.validate, throwsA(isA<ToolFailure>()));
  });
  test('production command fails closed without generating a patch', () async {
    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'bin/simurgh.dart',
      '--json',
      'patch',
    ]);
    expect(result.exitCode, 3);
    expect(result.stdout, contains('M0–M2 have not passed'));
  });
  test('release platform invocation is also gated with exit 3', () async {
    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'bin/simurgh.dart',
      '--json',
      'release',
      'android',
    ]);
    expect(result.exitCode, 3);
    expect(result.stdout, contains('No patch or release was created'));
  });
}
