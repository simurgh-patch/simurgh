import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

class ToolFailure implements Exception {
  ToolFailure(this.message, {this.code = 2, this.details});
  final String message;
  final int code;
  final Object? details;
  @override
  String toString() => message;
}

Object? canonicalize(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: canonicalize(value[key])};
  }
  if (value is List) return value.map(canonicalize).toList();
  return value;
}

String digestJson(Object? value) =>
    sha256.convert(utf8.encode(jsonEncode(canonicalize(value)))).toString();

Future<String> digestFile(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

Future<Map<String, dynamic>> readObject(String file) async {
  final value = jsonDecode(await File(file).readAsString());
  if (value is! Map<String, dynamic>) {
    throw ToolFailure('Expected a JSON object: $file');
  }
  return value;
}

Future<ProcessResult> runChecked(
  String executable,
  List<String> arguments, {
  String? directory,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: directory,
    environment: {'LC_ALL': 'C', 'DEPOT_TOOLS_UPDATE': '0'},
  );
  final out = process.stdout.transform(utf8.decoder).join();
  final err = process.stderr.transform(utf8.decoder).join();
  final status = await process.exitCode.timeout(
    timeout,
    onTimeout: () {
      process.kill(ProcessSignal.sigkill);
      throw ToolFailure('$executable exceeded ${timeout.inSeconds}s');
    },
  );
  final result = ProcessResult(process.pid, status, await out, await err);
  if (status != 0) {
    throw ToolFailure('$executable exited $status', details: result.stderr);
  }
  return result;
}
