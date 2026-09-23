import 'base.dart';
import 'foreign.dart';
import 'other.dart';

Base<int> make() => Added();
String capture(Object? Function() action) {
  try {
    return '${action()}';
  } catch (error) {
    return error.toString();
  }
}

String inspect(Base<int> value) {
  final results = <String>[];
  for (final action in [
    () => read(value),
    () {
      write(value, 3);
      return 'written';
    },
    () => call(value),
    () => property(value),
    () {
      setProperty(value);
      return 'set';
    },
    () => generic(value),
    () => collision(value),
  ]) {
    results.add(capture(action));
  }
  return results.join('\n');
}

String churn(Base<int> value, String Function() callback) {
  var last = '';
  for (int i = 0; i < 100000; i++) {
    last = 'allocation-$i-${i * 17}';
  }
  if (!last.startsWith('allocation-99999-')) throw StateError('GC');
  return callback();
}

void main() {
  final value = make();
  print(inspect(value));
  print(inspect(Mock()));
  print('live:${read(Live())}:${read(Mixed())}');
  print('home:${read(HomeMock())}:${read(ConcreteBack())}');
  print('back:${capture(() => read(Back()))}');
  final both = Both();
  print('left:${capture(() => read(both))}');
  print('right:${capture(() => otherRead(both))}');
  print('gc:${churn(value, () => capture(() => read(value)))}');
}

class Added extends Plain {}
