// @dart=3.0
import 'modern.dart' as modern;
class Box {
  final int value;
  Box(this.value);
  int read() => value + 1;
}
int stable(Box value) => value.read();
Box make(int value) => modern.Added(value);
void main() { print('virtual=${stable(make(3))}'); }
