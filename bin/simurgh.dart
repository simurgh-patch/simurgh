import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:simurgh_cli/src/artifacts.dart';
import 'package:simurgh_cli/src/common.dart';
import 'package:simurgh_cli/src/performance.dart';
import 'package:simurgh_cli/src/toolchain.dart';

final parser = ArgParser()
  ..addFlag('json', negatable: false, help: 'Emit a single JSON result.')
  ..addFlag('help', abbr: 'h', negatable: false)
  ..addOption(
    'flutter-sdk',
    defaultsTo: Platform.environment['SIMURGH_FLUTTER_SDK'],
  )
  ..addCommand(
    'doctor',
    ArgParser()
      ..addOption('build-root')
      ..addFlag('devices', negatable: false),
  )
  ..addCommand('verify-toolchain')
  ..addCommand(
    'engine-plan',
    ArgParser()..addOption('build-root', mandatory: true),
  )
  ..addCommand('status')
  ..addCommand(
    'inventory',
    ArgParser()..addOption('directory', mandatory: true),
  )
  ..addCommand(
    'compare-artifacts',
    ArgParser()
      ..addOption('before', mandatory: true)
      ..addOption('after', mandatory: true),
  )
  ..addCommand('performance', ArgParser()..addOption('input', mandatory: true))
  ..addCommand(
    'baseline',
    ArgParser()
      ..addFlag(
        'clean',
        negatable: false,
        help:
            'Clean the independent sample and resolve cached dependencies before building.',
      )
      ..addOption('platform', mandatory: true, allowed: ['android', 'ios']),
  )
  ..addCommand('release')
  ..addCommand('patch')
  ..addCommand('init')
  ..addCommand('preview')
  ..addCommand('promote')
  ..addCommand('rollback');

final root = p.normalize(p.join(p.dirname(Platform.script.toFilePath()), '..'));

void emit(Object result, bool json) {
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(result));
}

Future<String> flutterSdk(ArgResults args) async {
  final explicit = args['flutter-sdk'] as String?;
  if (explicit != null && explicit.isNotEmpty) return p.absolute(explicit);
  final dart = await File(Platform.resolvedExecutable).resolveSymbolicLinks();
  final inferred = p.normalize(p.join(p.dirname(dart), '../../../..'));
  if (await File(p.join(inferred, 'bin/flutter')).exists()) return inferred;
  throw ToolFailure('Set --flutter-sdk or SIMURGH_FLUTTER_SDK');
}

Future<Map<String, dynamic>> inspectDoctor(
  Toolchain chain,
  String sdk,
  ArgResults command,
) async {
  final checks = <String, Object?>{};
  try {
    checks['toolchain'] = await chain.verify(sdk);
  } on Object catch (error) {
    checks['toolchain'] = {'passed': false, 'error': '$error'};
  }
  final workspace =
      command['build-root'] as String? ?? p.join(root, '.engine-workspace');
  checks['engine_workspace'] = workspaceCheck(
    await freeBytes(workspace),
    chain.lock['engine_workspace_min_free_bytes'] as int,
  );
  for (final tool in ['git', 'python3', 'rustc', 'cargo', 'go', 'gclient']) {
    try {
      final executable = tool == 'gclient'
          ? p.join(root, '.tools/depot_tools/gclient')
          : tool;
      final result = await runChecked(executable, [
        tool == 'go' ? 'version' : (tool == 'gclient' ? '--help' : '--version'),
      ]);
      if (tool == 'gclient') {
        final revision = await runChecked('git', [
          'rev-parse',
          'HEAD',
        ], directory: p.dirname(executable));
        checks[tool] = {
          'passed':
              revision.stdout.toString().trim() ==
              chain.lock['depot_tools_revision'],
          'revision': revision.stdout.toString().trim(),
        };
      } else {
        checks[tool] = {'passed': true, 'version': '${result.stdout}'.trim()};
      }
    } on Object {
      checks[tool] = {
        'passed': false,
        'error': 'Tool unavailable or version probe failed',
      };
    }
  }
  if (Platform.isMacOS) {
    try {
      final xcode = await runChecked('xcodebuild', ['-version']);
      checks['xcode'] = {'passed': true, 'version': '${xcode.stdout}'.trim()};
    } on Object {
      checks['xcode'] = {'passed': false};
    }
  } else {
    checks['xcode'] = {'passed': false, 'error': 'iOS builds require macOS'};
  }
  if (command['devices'] == true) {
    try {
      final result = await runChecked(p.join(sdk, 'bin/flutter'), [
        'devices',
        '--machine',
      ], timeout: const Duration(seconds: 60));
      final devices = (jsonDecode(result.stdout as String) as List).cast<Map>();
      // Never persist personal device names or UDIDs in diagnostic reports.
      final ios = devices
          .where((d) => d['targetPlatform'] == 'ios' && d['emulator'] == false)
          .length;
      final android = devices
          .where(
            (d) =>
                d['targetPlatform'] == 'android-arm64' &&
                d['emulator'] == false,
          )
          .length;
      checks['devices'] = {
        'passed': ios > 0 && android > 0,
        'ios_physical': ios,
        'android_arm64_physical': android,
      };
    } on Object {
      checks['devices'] = {
        'passed': false,
        'error': 'Device enumeration failed',
      };
    }
  }
  return {
    'schema_version': 1,
    'checks_passed': checks.values.every(
      (v) => v is Map && v['passed'] == true,
    ),
    'checks': checks,
    'toolchain_id': chain.id,
    'runtime_available': false,
    'm0_complete': false,
    'note':
        'Environment diagnostics do not certify a source-built engine or device validation.',
  };
}

Future<Map<String, dynamic>> buildBaseline(
  Toolchain chain,
  String sdk,
  String platform,
  bool clean,
) async {
  final verification = await chain.verify(sdk);
  if (verification['passed'] != true) {
    throw ToolFailure('Toolchain mismatch', details: verification);
  }
  if (platform == 'ios' && !Platform.isMacOS)
    throw ToolFailure('iOS build requires macOS');
  if (await freeBytes(root) < 8 * 1024 * 1024 * 1024) {
    throw ToolFailure(
      'Official sample build requires 8 GiB free workspace budget',
    );
  }
  final app = p.join(root, 'examples/runtime_probe');
  if (clean) {
    await runChecked(
      p.join(sdk, 'bin/flutter'),
      ['clean'],
      directory: app,
      timeout: const Duration(minutes: 2),
    );
    await runChecked(
      p.join(sdk, 'bin/flutter'),
      ['pub', 'get', '--offline'],
      directory: app,
      timeout: const Duration(minutes: 2),
    );
  }
  if (!await File(p.join(app, '.dart_tool/package_config.json')).exists()) {
    throw ToolFailure('Run flutter pub get in examples/runtime_probe first');
  }
  final files = await runChecked('git', [
    'ls-files',
    '-z',
    '--cached',
    '--others',
    '--exclude-standard',
    '--',
    '.',
  ], directory: app);
  final source = <String, String>{};
  for (final name in files.stdout.toString().split('\u0000')) {
    if (name.isNotEmpty && await File(p.join(app, name)).exists()) {
      source[name] = await digestFile(File(p.join(app, name)));
    }
  }
  if (source.isEmpty) throw ToolFailure('No source inputs found');
  final command = platform == 'android'
      ? [
          'build',
          'apk',
          '--release',
          '--target-platform',
          'android-arm64',
          '--no-pub',
        ]
      : ['build', 'ios', '--release', '--no-codesign', '--no-pub'];
  final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
  final output = Directory(
    p.join(root, 'output/baselines', '$platform-$stamp'),
  );
  await output.create(recursive: true);
  final log = File(p.join(output.path, 'build.log')).openWrite();
  stderr.writeln(
    'Building official $platform reference; log: ${output.path}/build.log',
  );
  final process = await Process.start(
    p.join(sdk, 'bin/flutter'),
    command,
    workingDirectory: app,
    environment: {'GRADLE_USER_HOME': p.join(root, '.tools/gradle')},
  );
  final out = process.stdout.listen(log.add).asFuture<void>();
  final err = process.stderr.listen(log.add).asFuture<void>();
  final status = await process.exitCode;
  await Future.wait([out, err]);
  await log.close();
  if (status != 0)
    throw ToolFailure('Reference build failed; see ${output.path}/build.log');
  final artifact = platform == 'android'
      ? p.join(app, 'build/app/outputs/flutter-apk')
      : p.join(app, 'build/ios/iphoneos/Runner.app');
  final manifest = await inventory(artifact);
  final archive = p.join(output.path, platform == 'ios' ? 'Runner.app' : 'apk');
  await runChecked('cp', [
    '-a',
    artifact,
    archive,
  ], timeout: const Duration(minutes: 2));
  final archived = await inventory(archive);
  if (archived['tree_sha256'] != manifest['tree_sha256']) {
    throw ToolFailure('Archived artifact differs from build output');
  }
  final manifestFile = File(p.join(output.path, 'inventory.json'));
  await manifestFile.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
  );
  final report = {
    'schema_version': 1,
    'kind': 'official-reference-build',
    'platform': platform,
    'mode': 'release',
    'clean_build': clean,
    'toolchain_id': chain.id,
    'command': command,
    'source_sha256': digestJson(source),
    'source_files': source,
    'source_unchanged_during_build': await sourceUnchanged(app, source),
    'artifact_directory': archive,
    'build_artifact_directory': artifact,
    'artifact_inventory': manifestFile.path,
    'artifact_tree_sha256': manifest['tree_sha256'],
    'created_utc': DateTime.now().toUtc().toIso8601String(),
    'signing': platform == 'ios' ? 'unsigned' : 'development-key-not-for-store',
    'runtime_available': false,
    'device_validated': false,
    'note':
        'Official reference artifact archived and verified. Not a hot-update release.',
  };
  await File(
    p.join(output.path, 'build.json'),
  ).writeAsString('${const JsonEncoder.withIndent('  ').convert(report)}\n');
  if (report['source_unchanged_during_build'] != true) {
    throw ToolFailure(
      'Source changed during build; result is not a reproducible baseline. See ${output.path}/build.json',
    );
  }
  return report;
}

Future<bool> sourceUnchanged(String app, Map<String, String> before) async {
  final files = await runChecked('git', [
    'ls-files',
    '-z',
    '--cached',
    '--others',
    '--exclude-standard',
    '--',
    '.',
  ], directory: app);
  final after = <String, String>{};
  for (final name in files.stdout.toString().split('\u0000')) {
    final file = File(p.join(app, name));
    if (name.isNotEmpty && await file.exists())
      after[name] = await digestFile(file);
  }
  return digestJson(before) == digestJson(after);
}

Future<void> main(List<String> arguments) async {
  final json = arguments.contains('--json');
  try {
    final args = parser.parse(arguments);
    if (args['help'] == true || args.command == null) {
      stdout.writeln(
        'simurgh: M0 toolchain and acceptance tools\n${parser.usage}\n'
        'Commands: doctor, verify-toolchain, engine-plan, status, baseline, inventory, compare-artifacts, performance\n'
        'Production commands are gated until the custom runtime passes M0–M2.',
      );
      return;
    }
    final command = args.command!;
    if ([
      'release',
      'patch',
      'init',
      'preview',
      'promote',
      'rollback',
    ].contains(command.name)) {
      throw ToolFailure(
        'M0–M2 have not passed: ${command.name} is unavailable. No patch or release was created.',
        code: 3,
      );
    }
    if (command.rest.isNotEmpty)
      throw ToolFailure('Unexpected arguments: ${command.rest}');
    final chain = Toolchain(
      await readObject(p.join(root, 'toolchain.lock.json')),
    )..validate();
    Object result;
    switch (command.name) {
      case 'status':
        result = {
          'stage': 'M0-in-progress',
          'implemented': [
            'toolchain-verification',
            'environment-doctor',
            'artifact-inventory',
            'performance-evaluator',
            'official-reference-build',
          ],
          'not_implemented': [
            'source-built-engine',
            'patch-compiler',
            'hybrid-runtime',
            'updater',
            'publication-service',
            'console',
          ],
          'm0_complete': false,
          'toolchain_id': chain.id,
        };
      case 'verify-toolchain':
        final verification = await chain.verify(await flutterSdk(args));
        if (verification['passed'] != true) exitCode = 2;
        result = verification;
      case 'doctor':
        final report = await inspectDoctor(
          chain,
          await flutterSdk(args),
          command,
        );
        if (report['checks_passed'] != true) exitCode = 2;
        result = report;
      case 'engine-plan':
        final workspace = p.absolute(command['build-root'] as String);
        final check = workspaceCheck(
          await freeBytes(workspace),
          chain.lock['engine_workspace_min_free_bytes'] as int,
        );
        if (check['passed'] != true) exitCode = 2;
        result = {
          'workspace': workspace,
          'space': check,
          'will_download': false,
          'next_command': [
            'python3',
            p.join(root, 'scripts/prepare_engine.py'),
            '--build-root',
            workspace,
            '--execute',
          ],
          'note':
              'prepare_engine rechecks space and refuses existing destination paths. No full dependency download before the space gate passes.',
        };
      case 'inventory':
        result = await inventory(command['directory'] as String);
      case 'compare-artifacts':
        final comparison = compareInventories(
          await readObject(command['before'] as String),
          await readObject(command['after'] as String),
        );
        if (comparison['identical'] != true) exitCode = 1;
        result = comparison;
      case 'performance':
        final report = evaluatePerformance(
          await readObject(command['input'] as String),
        );
        if (report['thresholds_passed'] != true) exitCode = 1;
        result = report;
      case 'baseline':
        result = await buildBaseline(
          chain,
          await flutterSdk(args),
          command['platform'] as String,
          command['clean'] as bool,
        );
      default:
        throw ToolFailure(
          'M0–M2 have not passed: ${command.name} is unavailable. No patch or release was created.',
          code: 3,
        );
    }
    emit(result, json);
  } on ToolFailure catch (error) {
    exitCode = error.code;
    emit({
      'error': error.message,
      if (error.details != null) 'details': error.details,
      'exit_code': exitCode,
    }, json);
  } on Object catch (error) {
    exitCode = 2;
    emit({'error': '$error', 'exit_code': exitCode}, json);
  }
}
