enum Status { ready, running, _hidden }

abstract class Readable<T> {
  T read();
}

mixin Description<T> on Enum {
  String describe() => 'patched:$index:$T';
}

enum Boxed<T> with Description<T> implements Readable<T> {
  number<int>(3),
  text<String>('x');

  const Boxed(this.value);
  final T value;
  T read() => value;
  static int calls = 0;
  static String tick() => '${++calls * 10}';
}

enum Added { fresh }

Enum make() => Added.fresh;
String consume(Enum value) => '${value.name}:$value:${value.runtimeType}';
String classify(Status value) => switch (value) {
  Status.ready => 'ready',
  Status.running => 'running',
  Status._hidden => 'hidden',
};
void main() {
  print(consume(make()));
  print(
    '${Status.values.map((value) => '${value.name}:${value.index}:$value').join('|')}',
  );
  print(
    '${identical(Status.ready, Status.values.first)}:${classify(Status._hidden)}',
  );
  print(
    '${Boxed.number.read()}:${Boxed.text.read()}:${Boxed.number.describe()}:${Boxed.text.describe()}:${Boxed.tick()}',
  );
  var last = '';
  for (int i = 0; i < 100000; i++) {
    last = 'allocation-$i-${i * 17}';
  }
  if (!last.startsWith('allocation-99999-')) throw StateError('GC');
  print('gc:${consume(make())}');
  print('${Boxed.number.runtimeType}:${Boxed.number}:${Boxed.text.name}');
}
