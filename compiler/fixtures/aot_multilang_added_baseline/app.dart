// @dart=3.0
class Box {
  final int value;
  Box(this.value);
  int read() => value + 1;
}
int stable(Box value) => value.read();
Box make(int value) => Box(value);
void main() { print('virtual=${stable(make(3))}'); }
