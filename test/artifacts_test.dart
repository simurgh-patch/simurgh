import 'dart:io';

import 'package:simurgh_cli/src/artifacts.dart';
import 'package:simurgh_cli/src/common.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  setUp(
    () async =>
        dir = await Directory.systemTemp.createTemp('simurgh-artifacts-'),
  );
  tearDown(() async => dir.delete(recursive: true));
  test('identical bytes and paths reproduce the same fingerprint', () async {
    await File('${dir.path}/app').writeAsString('baseline');
    final first = await inventory(dir.path);
    final second = await inventory(dir.path);
    expect(compareInventories(first, second)['identical'], isTrue);
  });
  test('reports changed, added and removed files independently', () async {
    await File('${dir.path}/app').writeAsString('baseline');
    await File('${dir.path}/removed').writeAsString('old');
    final before = await inventory(dir.path);
    await File('${dir.path}/app').writeAsString('modified');
    await File('${dir.path}/removed').delete();
    await File('${dir.path}/added').writeAsString('new');
    final diff = compareInventories(before, await inventory(dir.path));
    expect(diff['changed'], ['app']);
    expect(diff['removed'], ['removed']);
    expect(diff['added'], ['added']);
  });
  test(
    'inventory rejects tampering rather than trusting stored hash',
    () async {
      await File('${dir.path}/app').writeAsString('baseline');
      final before = await inventory(dir.path);
      final after = {...before, 'tree_sha256': '0' * 64};
      expect(
        () => compareInventories(before, after),
        throwsA(isA<ToolFailure>()),
      );
    },
  );
  test('rejects symlink escape and empty artifact directory', () async {
    await expectLater(inventory(dir.path), throwsA(isA<ToolFailure>()));
    await Link('${dir.path}/escape').create('/etc/hosts');
    await expectLater(inventory(dir.path), throwsA(isA<ToolFailure>()));
  });
}
