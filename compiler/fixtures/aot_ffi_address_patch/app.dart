import 'dart:ffi';

@Native<Int32 Function(Int32)>()
external int abs(int value);
int compute() {
  final pointer = Native.addressOf<NativeFunction<Int32 Function(Int32)>>(abs);
  return pointer.asFunction<int Function(int)>()(-17);
}

void main() {
  if (abs(-1) != 1) throw StateError('native abs');
  print('address:${compute()}');
}
