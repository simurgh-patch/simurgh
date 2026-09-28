import 'dart:developer' as developer;
import 'dart:isolate';
import 'dart:io';
import 'dart:ui';
import 'fallback.dart' if (dart.library.ui) 'flutter.dart' as platform;

Color shade() => const Color(0xff654321);
Offset origin() => const Offset(10, 20);
Color Function(Color) blender() =>
    (other) => Color.alphaBlend(shade(), other);
@pragma('vm:platform-const-if', true)
int get platformMarker => 50;
int instrumentation() => developer.Timeline.timeSync('worker', () => worker(3));
int worker(int value) => value + 10;
Future<int> compute() => Isolate.run(() => worker(2));
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
  print('platform-value:$platformMarker');
  print('timeline:${instrumentation()}');
  print('isolate:${await compute()}');
  print('platform:${platform.label()}');
  print('color:${shade().toARGB32()}');
  print('point:${origin().dx}:${origin().dy}');
  print('blend:${blender()(const Color(0xff000000)).toARGB32()}');
}
