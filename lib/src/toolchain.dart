import 'dart:io';

import 'package:path/path.dart' as p;

import 'common.dart';

class Toolchain {
  Toolchain(this.lock);
  final Map<String, dynamic> lock;
  String get id => 'm0-${digestJson(lock)}';

  void validate() {
    if (lock['schema_version'] != 1) {
      throw ToolFailure('Unsupported toolchain lock schema');
    }
    for (final key in [
      'framework_revision',
      'engine_revision',
      'dart_revision',
    ]) {
      if (!RegExp(r'^[0-9a-f]{40}$').hasMatch('${lock[key]}')) {
        throw ToolFailure('Invalid revision: $key');
      }
    }
    if (lock['engine_workspace_min_free_bytes'] is! int ||
        (lock['engine_workspace_min_free_bytes'] as int) < 214748364800) {
      throw ToolFailure('Engine workspace budget must be at least 200 GiB');
    }
  }

  List<String> versionMismatches(Map<String, dynamic> installed) {
    const fields = {
      'frameworkVersion': 'flutter_version',
      'dartSdkVersion': 'dart_version',
      'frameworkRevision': 'framework_revision',
      'engineRevision': 'engine_revision',
      'channel': 'channel',
    };
    return [
      for (final field in fields.entries)
        if (installed[field.key] != lock[field.value])
          '${field.key}: expected ${lock[field.value]}, got ${installed[field.key]}',
    ];
  }

  Future<Map<String, dynamic>> verify(String sdk) async {
    validate();
    final root = await Directory(sdk).resolveSymbolicLinks();
    final installed = await readObject(
      p.join(root, 'bin/cache/flutter.version.json'),
    );
    final mismatches = versionMismatches(installed);
    final git = await runChecked('git', ['rev-parse', 'HEAD'], directory: root);
    if (git.stdout.toString().trim() != lock['framework_revision']) {
      mismatches.add('Flutter checkout HEAD differs from lock');
    }
    final dirty = await runChecked('git', [
      'status',
      '--porcelain',
      '--untracked-files=no',
    ], directory: root);
    if (dirty.stdout.toString().trim().isNotEmpty) {
      mismatches.add('Flutter checkout has tracked modifications');
    }
    final deps = await runChecked('git', [
      'show',
      '${lock['engine_revision']}:DEPS',
    ], directory: root);
    final dartRevision = RegExp(
      r"'dart_revision':\s*'([0-9a-f]{40})'",
    ).firstMatch(deps.stdout.toString())?.group(1);
    if (dartRevision != lock['dart_revision']) {
      mismatches.add('Dart revision from engine DEPS differs from lock');
    }
    final dartVersion = await File(
      p.join(root, 'bin/cache/dart-sdk/version'),
    ).readAsString();
    if (dartVersion.trim() != lock['dart_version']) {
      mismatches.add('Cached Dart SDK version differs from lock');
    }
    final engineVersion = await File(
      p.join(root, 'bin/internal/engine.version'),
    ).readAsString();
    if (engineVersion.trim() != lock['engine_revision']) {
      mismatches.add('bin/internal/engine.version differs from lock');
    }
    return {
      'passed': mismatches.isEmpty,
      'toolchain_id': id,
      'sdk': root,
      'dart_revision_source': '${lock['engine_revision']}:DEPS',
      'mismatches': mismatches,
      'custom_runtime_available': false,
    };
  }
}

Future<int> freeBytes(String directory) async {
  if (!Platform.isMacOS && !Platform.isLinux) {
    throw ToolFailure('Workspace probe currently supports macOS and Linux');
  }
  var existing = p.absolute(directory);
  while (!await Directory(existing).exists()) {
    final parent = p.dirname(existing);
    if (parent == existing)
      throw ToolFailure('Cannot find containing filesystem');
    existing = parent;
  }
  final result = await runChecked('df', ['-Pk', existing]);
  final line = result.stdout.toString().trim().split('\n').last;
  final columns = line.trim().split(RegExp(r'\s+'));
  if (columns.length < 6)
    throw ToolFailure('Cannot parse filesystem free space');
  return int.parse(columns[3]) * 1024;
}

Map<String, dynamic> workspaceCheck(int available, int required) => {
  'passed': available >= required,
  'available_bytes': available,
  'required_bytes': required,
  'missing_bytes': available >= required ? 0 : required - available,
};
