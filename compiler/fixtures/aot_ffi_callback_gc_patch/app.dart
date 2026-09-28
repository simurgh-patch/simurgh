import 'dart:ffi';
import 'dart:async';

NativeCallable<Int32 Function(Int32)> make(List<int> values) =>
    NativeCallable<Int32 Function(Int32)>.isolateLocal((int n) {
      if (n < 0) throw StateError('callback');
      return n * 10 + values.first;
    }, exceptionalReturn: -99);
NativeCallable<Void Function(Int32)> listen(void Function(int) target) =>
    NativeCallable<Void Function(Int32)>.listener(
      (int value) => target(value * 10),
    );
int invoke(Pointer<NativeFunction<Int32 Function(Int32)>> pointer, int value) =>
    pointer.asFunction<int Function(int)>()(value);
int churn() {
  var sum = 0;
  for (var round = 0; round < 160; round++) {
    final rows = List<List<int>>.generate(2000, (int i) => <int>[i, round]);
    sum += rows[round][0];
  }
  return sum;
}

Future<void> main() async {
  final values = <int>[5];
  final native = make(values);
  final completed = Completer<int>();
  final listener = listen((int n) => completed.complete(n * 10 + values.first));
  try {
    print('allocation:${churn()}');
    await Future<void>.value();
    print(
      'local:${invoke(native.nativeFunction, 7)}:${invoke(native.nativeFunction, -1)}',
    );
    listener.nativeFunction.asFunction<void Function(int)>()(2);
    print('listener:${await completed.future}');
  } finally {
    native.close();
    listener.close();
  }
}
