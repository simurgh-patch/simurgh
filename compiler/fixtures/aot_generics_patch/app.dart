T choose<T>(T first, T second) => second;
T relay<T>(T first, T second) => choose<T>(first, second);
T invoke<T>(T Function<T>(T, T) callback, T first, T second) => callback<T>(first, second);
num bounded<T extends num>(T first, T second) => first + second;
String typed<T>(T value) => 'patched:$T:$value';
Future<T> later<T>(T first, T second) async {
  await Future<void>.value();
  return second;
}
T Function<T>(T, T) make() => <T>(T first, T second) => second;
T Function(T) capture<T>(T seed) => (T next) => next;
class Selector {
  T pick<T>(T first, T second) => second;
}
class Child extends Selector {
  T pick<T>(T first, T second) => super.pick<T>(first, second);
}
int throughClass(Selector selector) => selector.pick<int>(4, 9);
int churn(int Function(int) callback) {
  var index = 0;
  var last = '';
  while (index < 100000) { last = 'allocation-$index-${index * 17}'; index++; }
  if (!last.startsWith('allocation-99999-')) throw StateError('Bad allocation');
  return callback(9);
}
String checkBound() {
  final dynamic callback = bounded;
  try { callback<String>('a', 'b'); return 'missing'; }
  catch (error) { return '${error is TypeError}'; }
}
Future<void> main() async {
  print('int=${relay<int>(1, 2)}');
  print('string=${relay<String>('left', 'right')}');
  print('callback=${invoke<int>(choose, 3, 8)}');
  final reference = choose<int>;
  print('tearoff=${reference(4, 7)}');
  print('bound=${bounded<int>(3, 5)}');
  print('boundError=${checkBound()}');
  print('type=${typed<num>(1)}');
  final pending = later<num>(1, 2);
  print('futureType=${pending is Future<int>}');
  print('async=${await pending}');
  final callback = make();
  print('closure=${callback<String>('a', 'b')}');
  print('virtual=${throughClass(Child())}');
  print('gc=${churn(capture<int>(4))}');
}
