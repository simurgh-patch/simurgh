import 'dart:io';

import 'package:path/path.dart' as p;

import 'common.dart';

/// Exact artifact inventory. No volatile files are silently ignored.
Future<Map<String, dynamic>> inventory(String directory) async {
  final root = await Directory(directory).resolveSymbolicLinks();
  final entries = <String, Object?>{};
  await for (final entity in Directory(
    root,
  ).list(recursive: true, followLinks: false)) {
    final name = p
        .relative(entity.path, from: root)
        .split(p.separator)
        .join('/');
    if (entity is File) {
      entries[name] = {
        'kind': 'file',
        'bytes': await entity.length(),
        'sha256': await digestFile(entity),
        'executable': (await entity.stat()).mode & 0x49 != 0,
      };
    } else if (entity is Link) {
      final target = await entity.target();
      final resolved = p.normalize(p.join(p.dirname(entity.path), target));
      if (p.isAbsolute(target) || !p.isWithin(root, resolved)) {
        throw ToolFailure('Artifact symlink escapes root: $name');
      }
      entries[name] = {'kind': 'symlink', 'target': target};
    }
  }
  if (entries.isEmpty) throw ToolFailure('Artifact directory is empty');
  return {
    'schema_version': 1,
    'kind': 'artifact-inventory',
    'tree_sha256': digestJson(entries),
    'entries': canonicalize(entries),
  };
}

Map<String, dynamic> compareInventories(
  Map<String, dynamic> before,
  Map<String, dynamic> after,
) {
  for (final manifest in [before, after]) {
    if (manifest['schema_version'] != 1 ||
        manifest['kind'] != 'artifact-inventory' ||
        manifest['entries'] is! Map ||
        (manifest['entries'] as Map).isEmpty ||
        manifest['tree_sha256'] != digestJson(manifest['entries'])) {
      throw ToolFailure('Invalid or corrupted artifact inventory');
    }
  }
  final left = before['entries'] as Map;
  final right = after['entries'] as Map;
  final names = {
    ...left.keys.cast<String>(),
    ...right.keys.cast<String>(),
  }.toList()..sort();
  final added = <String>[];
  final removed = <String>[];
  final changed = <String>[];
  for (final name in names) {
    if (!left.containsKey(name)) {
      added.add(name);
    } else if (!right.containsKey(name)) {
      removed.add(name);
    } else if (digestJson(left[name]) != digestJson(right[name])) {
      changed.add(name);
    }
  }
  return {
    'identical': added.isEmpty && removed.isEmpty && changed.isEmpty,
    'added': added,
    'removed': removed,
    'changed': changed,
    'note':
        'No differences were excluded. This is not proof of runtime compatibility.',
  };
}
