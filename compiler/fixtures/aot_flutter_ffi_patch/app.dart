import 'dart:ffi';
import 'dart:ui' as ui;

@Native<Int32 Function(Int32)>(symbol: 'abs')
external int magnitude(int value);
int compute() {
  final native = NativeCallable<Int32 Function(Int32)>.isolateLocal(
    (int value) => magnitude(value) + 20,
    exceptionalReturn: -1,
  );
  try {
    return native.nativeFunction.asFunction<int Function(int)>()(-3);
  } finally {
    native.close();
  }
}

ui.Offset origin() => ui.Offset(compute().toDouble(), 8);
ui.Offset Function() blender() => origin;
void main() {
  final point = origin();
  final callback = blender()();
  print('ffi:${point.dx}:${point.dy}');
  print('callback:${callback.dx}:${callback.dy}');
}
