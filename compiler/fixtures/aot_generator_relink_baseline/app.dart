class Tag {
  final String value;
  const Tag(this.value);
}

@Tag('shape')
class Box {
  final int value;
  const Box(this.value);
}

Iterable<Box> make(int value) sync* {
  yield Box(value);
}

Stream<Box> flow(int value) async* {
  yield Box(value);
}

int read(Box box) => box.value;
Iterable<int> transition() => <int>[2, 3];
Iterable<int> reverse() sync* {
  yield 4;
  yield 5;
}

int consume() => transition().first + reverse().last;
@Tag('old')
Iterable<int> tagged() sync* {
  yield 7;
}

int taggedConsumer() => tagged().first;
Iterable<Object> payload() sync* {
  yield 'old';
}

String describe(Object value) => value.toString();
Future<void> main() async {
  print('${read(make(3).first)}:${read((await flow(4).toList()).first)}');
  print('${consume()}:${taggedConsumer()}:${describe(payload().first)}');
}
