import 'dart:collection';

class Base<T> {
  final T value;
  final int extra;
  const Base(this.value, [this.extra = 2]);
  const Base.named({required this.value, this.extra = 3});
  const Base._hidden(this.value) : extra = 4;
  T read() => value;
}

mixin Label<T> on Base<T> {
  String label() => '${super.read()}:${extra}';
}
class Named<T> = Base<T> with Label<T>;
class Again<T> = Named<T> with Label<T>;

class Child extends Again<int> {
  Child(super.value, [super.extra]);
  Child.named({required super.value, super.extra}) : super.named();
}

mixin IntList implements List<int> {
  int get length => 1;
  set length(int value) {}
  int operator [](int index) => 5;
  void operator []=(int index, int value) {}
}
class Numbers = ListBase<int> with IntList;
String run() {
  final named = Named<int>.named;
  final hidden = Again<int>._hidden;
  const first = Named<int>(7);
  const second = Named<int>(7);
  return '${Child(8).label()}:${Child.named(value: 8).label()}:${named(value: 9).label()}:${hidden(10).label()}:${identical(first, second)}:${Numbers().join(",")}';
}

Base<int> make() => Named<int>(12);
String consume(Base<int> value) => '${value.read()}:${value.runtimeType}';
String churn(Base<int> value, String Function() callback) {
  var last = '';
  for (int i = 0; i < 100000; i++) {
    last = 'allocation-$i-${i * 17}';
  }
  if (!last.startsWith('allocation-99999-')) throw StateError('GC');
  return callback();
}

void main() {
  print(run());
  final value = make();
  print('added:${consume(value)}');
  print('gc:${churn(value, () => consume(value))}');
}
