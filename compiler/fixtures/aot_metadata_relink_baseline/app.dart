class Tag<T> {
  final T value;
  const Tag(this.value);
}

const note = Tag<String>('old-note');

@note
class Box {
  final int value;
  const Box(this.value);
}

@note
enum Status {
  @note
  ready,
}

@Tag<String>('old-function')
int tagged(@Tag<String>('old-param') int value) => value + 1;
int caller() => tagged(4);
Box make() => Box(3);
int consume(Box box) => box.value;
Status state() => Status.ready;
String read(Enum item) => '${item.name}:$item';
void main() {
  print('${caller()}:${consume(make())}:${read(state())}');
}
