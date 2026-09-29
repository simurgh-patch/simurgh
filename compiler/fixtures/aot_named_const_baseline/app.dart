class Box {
  final int value;
  const Box.named(this.value);
  @override
  String toString() => 'box:$value';
}

Object make() => const Box.named(1);
void main() {
  print(make());
}
