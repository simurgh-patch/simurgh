// @dart=3.12
import 'legacy.dart' as legacy;
import 'modern.dart' as modern;

void main() {
  print('first:${legacy.value}:${modern.doubled}');
  legacy.value += 1;
  print('after:${legacy.value}:${modern.doubled}');
}
