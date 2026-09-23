import 'dart:collection';

class View extends UnmodifiableMapView<int, String> {
  View(super.map);
  String? read(int key) => super[key + 1];
}

class Mixed<T> extends Object with ListMixin<T> {
  final List<T> values;
  Mixed(this.values);
  int get length => values.length;
  set length(int value) => values.length = value;
  T operator [](int index) => values[index];
  void operator []=(int index, T value) => values[index] = value;
  String joined() => super.join(':');
}

mixin SDKConstraint<T> on ListBase<T> {
  String joined() => super.join(':');
  List<R> mapped<R>(R Function(T) convert) => super.map<R>(convert).toList();
  int count() => super.length;
  void replace(T value) {
    super[0] = value;
  }

  T readFirst() => super[1];
}

class Concrete<T> extends ListBase<T> {
  final List<T> values;
  Concrete(this.values);
  int get length => values.length;
  set length(int value) => values.length = value;
  T operator [](int index) => values[index];
  void operator []=(int index, T value) => values[index] = value;
}

class Applied<T> extends Concrete<T> with SDKConstraint<T> {
  Applied(super.values);
}

mixin UnusedConstraint<T> on ListBase<T> {}

class MockList extends ListBase<int> with UnusedConstraint<int> {
  dynamic noSuchMethod(Invocation invocation) => 0;
}

mixin Compared on Comparable<int> {
  int Function(int) comparer() => super.compareTo;
}

class Rank implements Comparable<int> {
  int compareTo(int other) => 17 - other;
}

class ComparedRank extends Rank with Compared {}

abstract class StillAbstract<T> extends ListBase<T> with UnusedConstraint<T> {}

class IntMixed extends Mixed<int> {
  IntMixed(super.values);
  int operator [](int index) => super[index] + 10;
}

Map<int, int> makeMap() => AddedMap();
String read(View view) => view.read(1)!;
String joined(Mixed<int> list) => list.joined();
String ordered(List<int> list) {
  list.sort();
  return list.join(',');
}

int total(Iterable<int> values) =>
    values.fold<int>(0, (sum, value) => sum + value);
String churn(String Function() callback) {
  var last = '';
  for (int i = 0; i < 100000; i++) {
    last = 'allocation-$i-${i * 17}';
  }
  if (!last.startsWith('allocation-99999-')) throw StateError('GC');
  return callback();
}

void main() {
  final view = View({1: 'one', 2: 'two'});
  print('private-sdk-ancestor:${read(view)}');
  try {
    view[1] = 'bad';
  } on UnsupportedError {
    print('immutable:true');
  }
  final mixed = IntMixed([3, 1, 2]);
  print('sdk-alias-mixin:${joined(mixed)}');
  print('sorted:${ordered(mixed)}');
  final applied = Applied<int>([3, 4]);
  print('sdk-on:${applied.joined()}:${applied.readFirst()}');
  print(
    'generic:${applied.mapped<String>((value) => 'v$value').join(',')}:${applied.count()}',
  );
  applied.replace(8);
  print('write:${applied.joined()}');
  print('abstract-unused:${MockList().length}');
  print('abstract-tearoff:${ComparedRank().comparer()(2)}');
  final map = makeMap();
  final values = map.values;
  print('gc:${churn(() => '${total(values)}:${applied.readFirst()}')}');
}

class AddedMap extends Object with MapMixin<int, int> {
  final Map<int, int> data = {1: 10, 2: 20};
  Iterable<int> get keys => data.keys;
  int? operator [](Object? key) => data[key];
  void operator []=(int key, int value) {
    data[key] = value;
  }

  void clear() {
    data.clear();
  }

  int? remove(Object? key) => data.remove(key);
}
