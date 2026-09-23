// @dart=3.12
import 'legacy.dart' as legacy;
int increment(int value) => value + 10;
int evaluate(int value) {
  final (_, second) = (1, value);
  return second + legacy.Box(1).read();
}

int churn(int Function() callback) {
  var last = '';
  for (int i = 0; i < 100000; i++) { last = 'allocation-$i-${i * 17}'; }
  if (!last.startsWith('allocation-99999-')) throw StateError('GC');
  return callback();
}

int ignored(int _, int value) => value + 10;
