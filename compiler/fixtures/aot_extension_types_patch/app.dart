import 'other.dart' as other;

extension type const Value._(int _value) implements int {
  const Value.named(int n) : this._(n);
  factory Value.make(int n) => Value._(n);
  int compute() => _value + 10;
  int operator +(int n) => _value + n + 10;
  static int state = 3;
  static int read() => state + 10;
}

extension type const Child(Value _value) implements Value {}
extension type const Pair<T>((T, int) _pair) {
  T get first => _pair.$1;
  int count() => _pair.$2 + 10;
  R transform<R>(R Function(T) f) => f(first);
}
extension type Maybe(int? _value) {
  int read() => _value ?? -1;
}
extension type Work(List<int> values) {
  int call({int add = 1}) => values.first * 10 + add;
  Future<int> later() async {
    await Future<void>.value();
    return values.first * 10 + 2;
  }

  Iterable<int> sequence() sync* {
    yield values.first * 10 + 3;
  }

  Stream<int> stream() async* {
    yield values.first * 10 + 4;
  }
}
int retained(Value value) => value.compute();
int churn() {
  var sum = 0;
  for (var round = 0; round < 160; round++) {
    final rows = List<List<int>>.generate(2000, (int i) => <int>[i, round]);
    sum += rows[round][0];
  }
  return sum;
}

Future<void> main() async {
  const value = Value.named(4);
  final make = Value.make;
  final ctor = Value.named;
  final callback = value.compute;
  Value.state = 9;
  print(
    'value:${retained(value)}:${callback()}:${make(5).compute()}:${ctor(6).compute()}:${value + 2}',
  );
  print(
    'erased:${identical(value, 4)}:${value.runtimeType}:${value is int}:${const Child(value).compute()}',
  );
  print('static:${Value.read()}:${Value.state}');
  const pair = Pair<String>(('ok', 7));
  final transform = pair.transform;
  print(
    'pair:${pair.first}:${pair.count()}:${transform<int>((String s) => s.length)}',
  );
  print('nullable:${Maybe(null).read()}:${Maybe(8).read()}');
  print('remote:${const other.Remote.named(8).measure()}');
  final work = Work(<int>[7]);
  final captured = work.call;
  final later = work.later;
  print('allocation:${churn()}');
  await Future<void>.value();
  print(
    'captured:${captured(add: 3)}:${await later()}:${work.sequence().toList()}:${await work.stream().toList()}',
  );
}
