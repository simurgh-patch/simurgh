import 'dart:ffi';

NativeCallable<Int32 Function(Int32)> make(int extra) =>
    NativeCallable<Int32 Function(Int32)>.isolateLocal(
      (int n) => n * 10 + extra,
      exceptionalReturn: -99,
    );
int compute() {
  final native = make(5);
  try {
    final callback = native.nativeFunction.asFunction<int Function(int)>();
    return callback(8);
  } finally {
    native.close();
  }
}

void main() {
  print('callback:${compute()}');
}
