import 'dart:convert';
import 'dart:io';
import 'package:kernel/kernel.dart';

void main(List<String> args) {
  if (args.length != 2)
    throw ArgumentError('Expected Kernel file and source directory');
  final root = Directory(args[1]).absolute.uri.toString();
  final component = loadComponentFromBinary(args[0]);
  stdout.writeln(
    jsonEncode({
      for (final library in component.libraries)
        if (library.fileUri.toString().startsWith(root))
          library.fileUri.toString().substring(
            root.length,
          ): '${library.languageVersion.major}.${library.languageVersion.minor}',
    }),
  );
}
