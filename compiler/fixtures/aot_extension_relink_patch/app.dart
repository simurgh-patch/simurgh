class Box {
  final int value;
  Box(this.value);
}

extension Read on Box {
  num get result => value + 0.5;
  String label() => 'value:$result';
}

String retained(Box box) => box.label();
void main() {
  print('relink:${retained(Box(2))}');
}
