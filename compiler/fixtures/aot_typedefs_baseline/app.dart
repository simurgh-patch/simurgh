import 'dart:collection';
import 'dart:typed_data';

class Box<T extends num> {
  static int shared = 2;
  static int bump() => shared += 1;
  final T value;
  const Box(this.value);
  const Box.named(this.value);
  const Box._hidden(this.value);
  T read() => value;
  Identity<Async<T>> delayed() async => value;
  String label() => 'box:$value';
}

class Pair<A, B> {
  final A first;
  final B second;
  const Pair(this.first, this.second);
  String label() => '$first:$second:$A:$B';
}

typedef IntBox = Box<int>;
typedef Boxes<T extends num> = Box<T>;
typedef Fixed<T extends num> = Pair<String, T>;
typedef Swapped<A, B> = Pair<B, A>;
typedef Callback<T> = T Function(T value, {required int delta});
typedef GenericCallback = T Function<T extends num>(T value);
typedef Nested<T> = R Function<R extends T>(R value);
typedef Legacy<T>(T value);
typedef Async<T> = Future<T>;
typedef Identity<T> = T;
typedef Void = void;
typedef Optional<T> = T?;
typedef QueueOf<T> = ListQueue<T>;
typedef Bytes = Uint8List;
int add(int value, {required int delta}) => value + delta;
T identity<T extends num>(T value) => value;
int consume(IntBox box, Callback<int> callback) =>
    callback(box.read(), delta: 3);
Callback<int> makeCallback() => add;
Box<int> make() => IntBox(12);
String stableRead(Box<int> value) => value.label();
String churn(Box<int> value) {
  var last = '';
  for (int i = 0; i < 100000; i++) {
    last = 'allocation-$i-${i * 17}';
  }
  if (!last.startsWith('allocation-99999-')) throw StateError('GC');
  return stableRead(value);
}

Identity<Async<int>> later(int value) async => value + 1;
Void nothing() {}
Async<void> main() async {
  const IntBox box = IntBox(4);
  final constructor = Boxes<int>.named;
  final privateConstructor = Boxes<int>._hidden;
  final rawConstructor = Boxes.new;
  final fixed = Fixed.new;
  final swapped = Swapped<int, String>.new;
  GenericCallback generic = identity;
  Nested<num> nested = identity;
  Legacy<int> legacy = (int value) => value;
  Optional<int> empty;
  final queue = QueueOf<int>()..add(9);
  final bytes = Bytes.fromList([10]);
  nothing();
  print('delayed:${await box.delayed()}');
  print('static:${IntBox.bump()}:${IntBox.shared}:${Boxes.shared}');
  print(
    '${consume(box, makeCallback())}:${constructor(5).read()}:${privateConstructor(6).read()}:${rawConstructor(6).runtimeType}:${generic<int>(7)}:${nested<double>(2.5)}:${legacy(8)}',
  );
  print(
    '${IntBox == Box<int>}:${Boxes == Box<num>}:${identical(box, const Box<int>(4))}:${IntBox.new == Box<int>.new}:${empty == null}',
  );
  print(
    '${fixed("left", 2).label()}:${swapped("right", 3).label()}:${queue.first}:${bytes.first}:${await later(10)}',
  );
  final value = make();
  print('added:${stableRead(value)}:${value.runtimeType}');
  print('gc:${churn(value)}');
}
