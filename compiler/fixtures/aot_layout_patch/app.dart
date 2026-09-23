int stable(int value) => value * 2;
class Base {
  int hook() => 10;
}
class Box extends Base {
  String value;
  int factor;
  Box(int input) : value = '${input + 1}', factor = 3;
  int extra() => value.length;
  int compute() => stable(int.parse(value) * factor) + extra();
  int hook() => compute() + 1;
}
class Child extends Box {
  Child(int value) : super(value);
  int inherited() => super.compute() + 1;
}
class Holder {
  Box value;
  Holder(this.value);
  int read() => value.compute();
}
class Worker {
  Box create(int value) => Box(value);
}
Box factory() => Box(2);
Base defaultFactory({Base Function() create = factory}) => create();
int invokeBase(Base object) => object.hook();
int fromDefault() => invokeBase(defaultFactory());
bool isBox<T>(T object) => object is Box;
bool check<T>(T object, bool Function<T>(T) predicate) => predicate<T>(object);
int churn(Base object) {
  var index = 0;
  var last = '';
  while (index < 100000) { last = 'allocation-$index-${index * 17}'; index++; }
  if (!last.startsWith('allocation-99999-')) throw StateError('Bad allocation');
  return invokeBase(object);
}
final class Locked {
  int read() => 1;
}
final class LockedChild extends Locked {
  int value;
  int offset = 7;
  LockedChild(this.value);
  int read() => value + offset;
}
void main() {
  final object = Box(4);
  print('compute=${object.compute()}');
  print('fieldType=${object.value is String}');
  print('child=${Child(4).inherited()}');
  print('holder=${Holder(object).read()}');
  print('worker=${Worker().create(4).compute()}');
  print('aotBase=${invokeBase(object)}');
  print('default=${fromDefault()}');
  print('type=${check<Box>(object, isBox)}');
  print('gc=${churn(object)}');
  print('closed=${LockedChild(7).read()}');
}
