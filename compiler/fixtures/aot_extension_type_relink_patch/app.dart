extension type const Reading(double value) {
  num measure() => value + 1;
}
extension type const Wrapped(Reading value) implements Reading {}
Reading make() => const Reading(2.5);
num retained(Reading value) => value.measure();
void main() {
  final value = make();
  print(
    'relink:${retained(value)}:${Wrapped(value).measure()}:${identical(value, 2.5)}:${value.runtimeType}',
  );
}
