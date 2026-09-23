calculate(value) => typed(value);
forward(value) => typed(value) + 10;
identity(value) => value ?? 'fallback';
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
  local(int value) => value * 3;
  return local(total) + calculate(1);
}

main() async {
  print(
    'dynamic=${calculate(2)}:${forward(2)}:${identity(null)}:${identity(4)}',
  );
  print('callback=${apply((value) => typed(value))}');
  print('nullable=${nullable(null)}:${nullable(2)}:${absent == null}');
  print('inherited=${IntChild().result()}:${Child<String>().echo('text')}');
  print('loop=${loop()}');
  print('async=${await asyncValue(2)}');
  final future = asyncBroad(1);
  print('futureType=${future is Future<num>}:${future is Future<int>}');
  print('future=${await future}');
}
