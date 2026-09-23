import 'contracts.dart';

class Box<T> implements Combined<T> {
  T value;
  Box(this.value);
  String get label => 'box';
  T choose(T other) => other;
  int measure(int delta) => delta + 10;
}

class Added<T> implements Combined<T> {
  T value;
  Added(this.value);
  String get label => 'added';
  T choose(T other) => other;
  int measure(int delta) => delta + 100;
}

sealed class Closed {
  int read();
}

class Variant extends Closed {
  int read() => 1;
}

class Other implements Closed {
  int read() => 2;
}

class GrowingImpl implements Growing {
  int read() => 3;
  int get extra => 5;
}

Closed closed() => Other();
int readClosed(Closed value) => value.read();
String closedTag(Closed value) => switch (value) {
  Variant() => 'variant',
  Other() => 'other',
};
Growing growing() => GrowingImpl();
int readGrowing(Growing value) => value.read();

base class BaseFamily {
  int read() => 0;
}

base class BaseImpl implements BaseFamily {
  int read() => 4;
}

final class FinalFamily {
  int read() => 0;
}

final class FinalImpl implements FinalFamily {
  int read() => 6;
}

base class BaseOther implements BaseFamily {
  int read() => 5;
}

final class FinalOther implements FinalFamily {
  int read() => 7;
}

BaseFamily baseFamily() => BaseOther();
FinalFamily finalFamily() => FinalOther();
int readBase(BaseFamily value) => value.read();
int readFinal(FinalFamily value) => value.read();
Value<int> make() => Added<int>(8);
int read(Value<int> receiver) => receiver.measure(receiver.value);
int choose(Value<int> receiver) => receiver.choose(7);
int update(Value<int> receiver) {
  receiver.value += 2;
  return receiver.value;
}

String label(Label receiver) => receiver.label;
bool conforms(Object receiver) =>
    receiver is Combined<int> && receiver is Value<int> && receiver is Label;
bool rejects(Value<num> receiver) {
  try {
    receiver.value = 1.5;
    return false;
  } catch (error) {
    return error is TypeError;
  }
}

int churn(Value<int> receiver) {
  var last = '';
  for (int i = 0; i < 100000; i++) {
    last = 'allocation-$i-${i * 17}';
  }
  if (!last.startsWith('allocation-99999-')) throw StateError('GC');
  return read(receiver);
}

void main() {
  final existing = Box<int>(2);
  final added = make();
  print('existing:${read(existing)}:${choose(existing)}');
  print('new:${read(added)}:${choose(added)}');
  print('update:${update(added)}');
  print('label:${label(added as Label)}');
  print('interfaces:${conforms(added)}');
  print('covariance:${rejects(added)}');
  print('tearoff:${added.measure(1)}:${(added.measure == added.measure)}');
  print('gc:${churn(added)}');
  print('closed:${readClosed(closed())}:${closedTag(closed())}');
  print('growing:${readGrowing(growing())}');
  print('base:${readBase(baseFamily())}');
  print('final:${readFinal(finalFamily())}');
}
