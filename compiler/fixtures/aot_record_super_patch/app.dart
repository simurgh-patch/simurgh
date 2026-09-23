typedef Row<T> = (T, {T? optional, T Function(T) map});

class Base<T> {
  Row<T> slot;
  Row<T>? pending;
  Base(this.slot);
  Row<T> read() => slot;
}

mixin Updates<T> on Base<T> {
  Row<T> fromSuper() => super.slot;
  Row<T> write(Row<T> value) => super.slot = value;
  Row<T> optional(Row<T> value) => super.pending ??= value;
  Future<Row<T>> later(Row<T> value) async {
    await Future<void>.value();
    super.slot = value;
    return super.read();
  }
}

class Child extends Base<int> with Updates<int> {
  Child(super.slot);
}

int transform(int value) => value + 10;
Row<int> make() => (13, optional: 14, map: transform);
String consume(Row<int> value) =>
    '${value.$1}:${value.optional}:${value.map(5)}';
String through<T>(Base<T> value) {
  final row = value.read();
  return '${row.map(row.$1)}:${row.optional}';
}

Future<void> main() async {
  final child = Child(make());
  print('read:${consume(child.fromSuper())}:${through(child)}');
  print('write:${consume(child.write((7, optional: null, map: transform)))}');
  print(
    'optional:${consume(child.optional(make()))}:${consume(child.optional((99, optional: 99, map: transform)))}',
  );
  print('async:${consume(await child.later(make()))}');
  var last = '';
  for (int i = 0; i < 100000; i++) {
    last = 'allocation-$i-${i * 17}';
  }
  if (!last.startsWith('allocation-99999-')) throw StateError('GC');
  print('gc:${consume(child.fromSuper())}');
}
