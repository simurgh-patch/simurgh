import 'dart:io';

File dataFile(Directory root) => File('${root.path}/data.txt');
Future<String> diskValue(File file) async {
  final handle = await file.open(mode: FileMode.write);
  try {
    await handle.writeString('patch');
    await handle.flush();
  } finally {
    await handle.close();
  }
  dynamic nativeFile = file;
  return '${await nativeFile.readAsString()}:${(await file.stat()).size}';
}

Future<void> main() async {
  final root = await Directory.systemTemp.createTemp('simurgh-io-');
  try {
    print('io:${await diskValue(dataFile(root))}');
  } finally {
    await root.delete(recursive: true);
  }
}
