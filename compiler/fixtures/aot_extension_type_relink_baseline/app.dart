extension type const Reading(int value) {
  num measure() => value + 1;
}
extension type const Wrapped(Reading value) implements Reading {}
Reading make() => const Reading(2);
num retained(Reading value) => value.measure();
void main() {
  final value = make();
  print(
    'relink:${retained(value)}:${Wrapped(value).measure()}:${identical(value, 2)}:${value.runtimeType}',
  );
}
