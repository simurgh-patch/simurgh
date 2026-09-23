class Box<T> {
  T value;
  Box(this.value);
  T pick(T next) => value;
  T get current => value;
  void set current(T next) { value = next; }
  String typeName() => '$T';
  String shadow<T>(T next) => '$T:$next';
  U map<U>(U Function(T) callback) => callback(value);
  Future<T> later(T next) async { await Future<void>.value(); return value; }
}
class Child<U> extends Box<U> {
  Child(U value) : super(value);
  U pick(U next) => super.pick(next);
  U get current => super.current;
  void set current(U next) { super.current = next; }
}
class IntBox extends Child<int> {
  IntBox(int value) : super(value);
  int pick(int next) => super.pick(next);
}
class Numeric<T extends num> extends Box<T> {
  Numeric(T value) : super(value);
}
Box<int> make(int value) => Box<int>(value);
int read(Box<int> value) => value.pick(9);
String covariance() {
  Box<num> value = Box<int>(1);
  try { value.current = 1.5; return 'missing'; }
  catch (error) { return '${error is TypeError}'; }
}
int churn(Box<int> value) {
  int index = 0;
  var last = '';
  while (index < 100000) { last = 'allocation-$index-${index * 17}'; index++; }
  if (!last.startsWith('allocation-99999-')) throw StateError('Bad allocation');
  return value.pick(9);
}
Future<void> main() async {
  final value = IntBox(4);
  print('virtual=${read(value)}');
  print('type=${value.typeName()}');
  print('shadow=${value.shadow<String>('s')}');
  print('map=${value.map<String>((int n) => 'mapped:$n')}');
  print('getter=${value.current}');
  value.current = 6;
  print('setter=${value.current}');
  final pending = Box<num>(1).later(2);
  print('futureType=${pending is Future<int>}');
  print('async=${await pending}');
  print('covariance=${covariance()}');
  print('gc=${churn(value)}');
  print('factory=${read(make(3))}');
  print('factoryType=${make(3).typeName()}');
  print('newGc=${churn(make(3))}');
  print('bounded=${Numeric<double>(1.5).pick(2.5)}');
}
