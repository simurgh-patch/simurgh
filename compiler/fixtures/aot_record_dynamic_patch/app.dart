typedef Row = (int, {String label, int Function(int) callback});
typedef Other = ({int absent});

class SetterContract {
  set label(String value) {}
}

Row sample() => (3, label: 'base', callback: (int value) => value + 2);
dynamic make() {
  var seed = 10;
  return (30, true, label: 'patch', callback: (int value) => value + seed);
}

String consume(dynamic value) =>
    '${value.$1}:${value.label}:${value.callback(4)}';
String errors(dynamic value) {
  var type = false, arity = false, write = false, missing = false;
  try {
    value.callback('bad');
  } catch (error) {
    type = error is TypeError;
  }
  try {
    value.callback();
  } catch (error) {
    arity = error is NoSuchMethodError;
  }
  try {
    value.label = 'write';
  } catch (error) {
    write = error is NoSuchMethodError;
  }
  try {
    value.absent;
  } catch (error) {
    missing = error is NoSuchMethodError;
  }
  return '$type:$arity:$write:$missing';
}

dynamic wrap<T>(T callback) => (genericCallback: callback);
String generic(dynamic value) => '${value.genericCallback(3)}';
void main() {
  print(
    'generic:${generic(wrap<int Function(int)>((int value) => value + 1))}',
  );
  final value = make();
  print('read:${consume(value)}');
  print('errors:${errors(value)}');
  var last = '';
  for (int i = 0; i < 100000; i++) {
    last = 'allocation-$i-${i * 17}';
  }
  if (!last.startsWith('allocation-99999-')) throw StateError('GC');
  print('gc:${consume(value)}');
}
