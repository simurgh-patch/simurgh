import 'dart:ui';
import 'fallback.dart' if (dart.library.ui) 'flutter.dart' as platform;

Color shade() => const Color(0xff654321);
Offset origin() => const Offset(10, 20);
Color Function(Color) blender() =>
    (other) => Color.alphaBlend(shade(), other);
void main() {
  print('platform:${platform.label()}');
  print('color:${shade().toARGB32()}');
  print('point:${origin().dx}:${origin().dy}');
  print('blend:${blender()(const Color(0xff000000)).toARGB32()}');
}
