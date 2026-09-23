class Tag {
  final String value;
  const Tag(this.value);
}

@Tag('shape')
class Box {
  final int value;
  final int extra;
  const Box(this.value, [this.extra = 10]);
}

Iterable<Box> make(int value) sync* {
  yield Box(value);
}

Stream<Box> flow(int value) async* {
  yield Box(value);
}

int read(Box box) => box.value + box.extra;
Iterable<int> transition() sync* {
  yield 12;
  yield 13;
}

Iterable<int> reverse() => <int>[14, 15];
int consume() => transition().first + reverse().last;
@Tag('new')
Iterable<int> tagged() sync* {
  yield 7;
}

int taggedConsumer() => tagged().first;

class Added {
  final String value;
  Added(this.value);
  String toString() => 'new:$value';
}

Iterable<Object> payload() sync* {
  yield Added('payload');
}

String describe(Object value) => value.toString();
Future<void> main() async {
  print('${read(make(3).first)}:${read((await flow(4).toList()).first)}');
  print('${consume()}:${taggedConsumer()}:${describe(payload().first)}');
}
