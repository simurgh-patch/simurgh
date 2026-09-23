part of 'app.dart';

class Child extends Base<int> {
  Child(int value) : super._(value);
  int run() => super._read() + _bonus();
}

int invoke(Child box) => box.run();
int stableRead(Base<int> box) => box.read;
Base<int> make() => Added(4);
int Function() callback(Base<int> box) =>
    () => box._read() + _count + 10;
int churn(int Function() callback) {
  var last = '';
  for (int i = 0; i < 100000; i++) {
    last = 'allocation-$i-${i * 17}';
  }
  if (!last.startsWith('allocation-99999-')) throw StateError('GC');
  return callback();
}
