// @dart=3.0
part 'aliases.dart';

class _Hidden<T extends num> {
  final T value;
  const _Hidden(this.value);
  const _Hidden.named(this.value);
  const _Hidden._private(this.value);
  String label() => 'old:$value';
}

String privateIdentity() {
  final constructor = Public<int>._private;
  return '${constructor(6).label()}:${identical(const Public<int>(2), const _Hidden<int>(2))}';
}

int legacyCall() {
  Legacy callback = (int _) => _ + 1;
  return callback(4);
}
