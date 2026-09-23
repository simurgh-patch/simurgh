import 'dart:collection';
import 'dart:math';

class Bag<T> extends ListBase<T> {
  final List<T> data;
  Bag(this.data);
  int get length => data.length;
  set length(int value) {
    data.length = value;
  }

  T operator [](int index) => data[index];
  void operator []=(int index, T value) {
    data[index] = value;
  }

  String render() => super.join(',');
  T front() => data.first;
  List<T> copy() => super.map<T>((value) => value).toList();
  List<R> mapped<R>(R Function(T) transform) =>
      super.map<R>(transform).toList();
  String defaults() => super.join();
  void replaceFirst(T value) {
    super.first = value;
  }

  bool empty() => isEmpty;
}

mixin Joined<T> on Bag<T> {
  String marked() => super.join(':');
}

class Mixed<T> extends Bag<T> with Joined<T> {
  Mixed(super.data);
}

class Bounds extends MutableRectangle<int> {
  Bounds(super.left, super.top, super.width, super.height);
  int nudge() {
    super.left += 1;
    return super.left;
  }
}

class IntBag extends Bag<int> {
  IntBag(super.data);
  int operator [](int index) => super[index] + 0;
  void operator []=(int index, int value) {
    super[index] = value - 0;
  }
}

class View extends MapView<int, int> {
  View(super.map);
  int? operator [](Object? key) => super[key];
  int step() {
    super[1] = (super[1] ?? 0) + 1;
    return super[1]!;
  }

  int post() {
    final old = super[1]!;
    super[1] = old + 1;
    return old;
  }

  int firstOnly() => super[2] ??= 7;
  int viaUpdate() => super.update(1, (value) => value + 1, ifAbsent: () => 0);
}

class Failure extends AssertionError {
  Failure([super.message]);
  String detail() => 'detail:${super.message}';
  String toString() => 'old:${super.toString()}';
  bool trace() => super.stackTrace != null;
}

List<int> make() => IntBag([3, 1, 2]);
Map<String, int> makeMap() => {'a': 1};
Error makeError() => Failure('first');
String sorted(List<int> values) {
  values.sort();
  return values.join(',');
}

int mapTotal(Map<String, int> value) =>
    value.values.fold<int>(0, (sum, next) => sum + next);
bool caught(Error error) {
  try {
    throw error;
  } catch (value) {
    return identical(error, value) && error.stackTrace != null;
  }
}

String churn(List<int> value, String Function() callback) {
  var last = '';
  for (int i = 0; i < 100000; i++) {
    last = 'allocation-$i-${i * 17}';
  }
  if (!last.startsWith('allocation-99999-')) throw StateError('GC');
  return '${value.first}:${callback()}';
}

int chain() => 3;

class DynamicView extends MapView<int, dynamic> {
  DynamicView(super.map);
  int post() => super[1]++;
  int compound() => super[1] += 3;
}

void main() {
  print('fields:${Bounds(1, 2, 3, 4).nudge()}');
  print('mixed:${Mixed<int>([1, 2]).marked()}');
  final bag = IntBag([3, 1, 2]);
  final words = Bag<String>(['a', 'b']);
  final value = make();
  print('render:${bag.render()}:${words.render()}');
  print('front:${bag.front()}');
  print(
    'copy:${bag.copy().join(',')}:${bag.mapped<String>((value) => 'v$value').join(',')}',
  );
  print('default:${words.defaults()}:${words.empty()}');
  words.replaceFirst('z');
  print('setter:${words.front()}');
  print('sort:${sorted(value)}');
  final view = View({1: 3});
  print(
    'view:${view.step()}:${view.post()}:${view[1]}:${view.firstOnly()}:${view.firstOnly()}:${view.viaUpdate()}',
  );
  final dynamicView = DynamicView({1: 4});
  print(
    'lvalue:${dynamicView.post()}:${dynamicView.compound()}:${dynamicView[1]}',
  );
  print('chain:${chain()}');
  final error = Failure('failure');
  print('error:${error.detail()}:$error:${caught(error)}:${error.trace()}');
  print('new:${mapTotal(makeMap())}:${caught(makeError())}');
  print('gc:${churn(value, bag.render)}');
}
