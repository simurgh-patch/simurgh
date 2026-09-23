class Left {
  final int value;
  Left(this.value);
  String label() => 'left:$value';
}

class Right {
  final int value;
  Right(this.value);
  String label() => 'right:$value';
}

typedef Chosen = Left;
typedef Value = int;
typedef Handler = Value Function(Value value);
typedef Removed = int;
Chosen selected = Chosen(3);

class Holder {
  final Chosen item;
  Holder(this.item);
  String label() => item.label();
  String toString() => label();
}

Value transform(Value value) => value + 2;
Handler callback = transform;
String consume(Chosen value) => value.label();
String typed(Handler fn) => '${fn(5)}';
Object make() => Holder(Chosen(4));
String stable(Object value) => value.toString();
void main() {
  print('${consume(selected)}:${typed(callback)}:${Holder(Chosen(4)).label()}');
  print('types:${Chosen == Left}:${Value == int}:${make().runtimeType}');
  final value = make();
  var last = '';
  for (int i = 0; i < 100000; i++) {
    last = 'allocation-$i-${i * 17}';
  }
  if (!last.startsWith('allocation-99999-')) throw StateError('GC');
  print('gc:${stable(value)}');
}
