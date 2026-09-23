calculate(value) => value + 10;
int typed(int value) => value + 10;
apply(int Function(int) callback) => callback(3);
nullable(int? value) => value ?? 7;
Object? absent = null;
asyncValue(int value) async => value + 10;
asyncBroad(num value) async => value;

class Base<T> {
  T echo(T value) => value;
}

class Child<U> extends Base<U> {
  @override
  echo(value) => super.echo(value);
}

class IntChild extends Child<int> {
  result() => super.echo(5) + 10;
}

loop() {
  var total = 0;
  for (var calculate in [1, 2, 3]) {
    total += calculate;
  }
  for (var i = 0; i < 2; i++) {
    total += i;
  }
  {
    final (calculate, text) = (4, 'pattern');
    total += calculate;
    print(text);
  }
  local(value) => value * 2;
  return local(total) + calculate(1);
}

main() async {
  retentionProbe();
  print('dynamic=${calculate(2)}');
  print('callback=${apply((value) => typed(value))}');
  print('nullable=${nullable(null)}:${nullable(2)}:${absent == null}');
  print('inherited=${IntChild().result()}:${Child<String>().echo('text')}');
  print('loop=${loop()}');
  print('async=${await asyncValue(2)}');
  final future = asyncBroad(1);
  print('futureType=${future is Future<num>}:${future is Future<int>}');
  print('future=${await future}');
}

class Dormant {
  int value = 2;
  int hidden(int x, {int extra = 3}) => value + x + extra;
  T bounded<T extends num>(T x) => x;
  int get doubled => value * 2;
  set doubled(int x) { value = x ~/ 2; }
  int Function(int) get callback => (int x) => x + value;
}
int churnDynamic(dynamic receiver) {
  var last = '';
  for (int i = 0; i < 100000; i++) {
    last = 'allocation-$i-${i * 17}';
  }
  if (!last.startsWith('allocation-99999-')) throw StateError('GC');
  return receiver.hidden(1);
}
void retentionProbe() {
  dynamic receiver = Dormant();
  print('retained=${receiver.hidden(4, extra: 8)}');
  print('getter=${receiver.doubled}');
  receiver.doubled = 12;
  print('setter=${receiver.value}');
  final dynamic tearoff = receiver.hidden;
  print('tearoff=${tearoff(1, extra: 2)}');
  print('callbackDynamic=${receiver.callback(3)}');
  print('boundedDynamic=${receiver.bounded<num>(2.5)}');
  bool typeError = false;
  try { receiver.hidden('bad'); } on TypeError { typeError = true; }
  print('argumentCheck=$typeError');
  bool setterError = false;
  try { receiver.doubled = 'bad'; } on TypeError { setterError = true; }
  print('setterCheck=$setterError');
  bool boundError = false;
  try { receiver.bounded<String>('bad'); } on TypeError { boundError = true; }
  print('boundCheck=$boundError');
  bool missing = false;
  try { dynamic other = 1; other.hidden(1); } on NoSuchMethodError { missing = true; }
  print('missing=$missing');
  print('dynamicGc=${churnDynamic(receiver)}');
  dynamic added = AddedDynamic();
  print('newDynamic=${added.hidden(1)}:${churnDynamic(added)}');
  dynamic number = 5;
  print('unary=${-number}:${~number}');
}

class AddedDynamic extends Dormant {
  @override
  int hidden(int x, {int extra = 3}) => super.hidden(x, extra: extra) + 100;
}
