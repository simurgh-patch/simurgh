// @dart=3.0
import 'modern.dart' as modern;
int evaluate(int _) {
  int legacyLocal(int _) => _ + 1;
  return legacyLocal(_) + modern.increment(1);
}
class Box {
  final int value;
  Box(this.value);
  int read() => value + 1;
}

int Function() callback(int _) {
  var count = _;
  return () => ++count + 1;
}

int binding() { var _ = 2; return _ + 1; }
