import 'dart:isolate';
import 'dart:io';
import 'dart:ui';
import 'fallback.dart' if (dart.library.ui) 'flutter.dart' as platform;

Color shade() => const Color(0xff123456);
Offset origin() => const Offset(1, 2);
Color Function(Color) blender() =>
    (other) => Color.alphaBlend(shade(), other);
int worker(int value) => value + 1;
Future<int> compute() => Isolate.run(() => worker(2));
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
  print('isolate:${await compute()}');
  print('platform:${platform.label()}');
  print('color:${shade().toARGB32()}');
  print('point:${origin().dx}:${origin().dy}');
  print('blend:${blender()(const Color(0xff000000)).toARGB32()}');
}
