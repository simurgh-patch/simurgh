import 'dart:ffi';

int target(int value) => value + 1;
int compute() {
  final lib = DynamicLibrary.process();
  final abs = lib.lookupFunction<Int32 Function(Int32), int Function(int)>(
    'abs',
  );
  final callback = Pointer.fromFunction<Int32 Function(Int32)>(target, -99);
  return abs(-7) + callback.asFunction<int Function(int)>()(3);
}

void main() {
  print('lookup:${compute()}');
}
