calculate(value) => value + 1;
int typed(int value) => value + 1;
apply(int Function(int) callback) => callback(3);
nullable(int? value) => value ?? 7;
Object? absent = null;
asyncValue(int value) async => value + 1;
asyncBroad(num value) async => value;

class Base<T> {
  T echo(T value) => value;
}

class Child<U> extends Base<U> {
  @override
  echo(value) => super.echo(value);
}

class IntChild extends Child<int> {
  result() => super.echo(5) + 1;
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
void retentionProbe() { print('retention=baseline'); }
