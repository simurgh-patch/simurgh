// @dart=3.12
import 'legacy.dart' as legacy;
import 'modern.dart' as modern;

int stable(int value) => value * 2;
void main() {
  print('wildcard=${modern.ignored(99, 3)}');
  print('binding=${legacy.binding()}');
  print('legacy=${legacy.evaluate(3)}');
  print('bound=${stable(legacy.Box(2).read())}');
  print('modern=${modern.evaluate(3)}');
  print('gc=${modern.churn(legacy.callback(2))}');
  print('identity=${legacy.Box(1) is legacy.Box}');
  print('className=${legacy.Box(1).runtimeType}');
}
