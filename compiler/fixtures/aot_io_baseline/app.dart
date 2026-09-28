import 'dart:io';

File dataFile(Directory root) => File('${root.path}/data.txt');
Future<String> diskValue(File file) async {
  await file.writeAsString('base');
  return await file.readAsString();
}

Future<void> main() async {
  final root = await Directory.systemTemp.createTemp('simurgh-io-');
  try {
    print('io:${await diskValue(dataFile(root))}');
  } finally {
    await root.delete(recursive: true);
  }
}
