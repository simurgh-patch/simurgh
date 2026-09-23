// @dart=3.0
typedef Data = (int, {Box value});

class Box {
  final int value;
  Box(this.value);
  int read() => value;
}

int legacy(Data data) {
  final (number, value: item) = data;
  return number + item.read();
}
