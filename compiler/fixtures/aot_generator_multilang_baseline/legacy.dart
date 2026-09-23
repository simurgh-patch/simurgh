// @dart=3.0
part 'details.dart';

class Holder<T> {
  final T value;
  Holder(this.value);
  Iterable<T> values() sync* {
    yield value;
  }
}

Iterable<int> values(int count) sync* {
  for (int i = 0; i < count; i++) {
    yield i + 1;
  }
}
