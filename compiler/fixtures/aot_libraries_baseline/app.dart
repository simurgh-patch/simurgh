import 'api.dart' show evaluate;
import 'left.dart' as left;
import 'right.dart' as right;
import 'selected.dart' show choose;

void main() {
  final callback = left.evaluate;
  print('value=${evaluate(10)}');
  print('reference=${callback(10)}');
  print('private=${right.evaluate(10)}');
  print('cycle=${left.cycle(4)}');
  print('selected=${choose()}');
}
