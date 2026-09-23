class Box<T> {
  final T value;
  const Box(this.value);
  T read() => value;
  String label() => 'patched:$value';
}

typedef Data<T> = (T, {String label, Box<T> box});
Data<int> shared = (3, label: 'old', box: Box<int>(4));
Data<int> make() => (15, label: 'patch', box: Added(16));
String consume(Data<int> value) =>
    '${value.$1}:${value.label}:${value.box.label()}';

class Parent<T> {
  Data<T> item;
  Parent(this.item);
  Data<T> read() => item;
}

class Child extends Parent<int> {
  Child(super.item);
  Data<int> read() => super.read();
}

void main() {
  final value = make();
  final (first, label: label, box: box) = value;
  final single = (first,);
  final empty = ();
  Data<int>? nullable;
  print(
    '${consume(value)}:${consume(Child(shared).read())}:$label:${box.label()}:${single.$1}:${empty == ()}:${nullable == null}',
  );
  print('${value == (first, box: box, label: label)}:${value.runtimeType}');
  var last = '';
  for (int i = 0; i < 100000; i++) {
    last = 'allocation-$i-${i * 17}';
  }
  if (!last.startsWith('allocation-99999-')) throw StateError('GC');
  print('gc:${consume(value)}');
  if (value case (int number, label: final label, box: Box<int> held)) {
    print('pattern:$number:$label:${held.read()}');
  }
}

class Added extends Box<int> {
  Added(super.value);
}
