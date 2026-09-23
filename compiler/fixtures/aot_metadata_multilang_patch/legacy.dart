// @dart=3.0
part 'details.dart';

class Tag<T> {
  final T value;
  const Tag._(this.value);
}

typedef Alias<T> = Tag<List<T>>;
const note = Tag<String>._('note');
