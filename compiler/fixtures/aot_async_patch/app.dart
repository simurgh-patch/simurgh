Future<int> stable(int value) async {
  await Future<void>.delayed(Duration.zero);
  return value + 1;
}
Future<int> calculate(int value) async {
  final next = await stable(value);
  return next + 100;
}
Future<int> nested(int value) async => (await calculate(value)) * 2;
class Box {
  int value;
  Box(this.value);
  Future<int> step(int delta) async {
    await stable(0);
    value += delta * 2;
    return value;
  }
}
Future<int> Function(int) make(int seed) {
  var total = seed;
  return (int delta) async {
    await stable(0);
    total += delta * 2;
    return total;
  };
}
Future<void> fail() async {
  await stable(0);
  throw StateError('patched async');
}
Future<String> caught() async {
  try { await fail(); return 'missing'; }
  catch (error) { return error.toString(); }
}
Future<int> churn(Future<int> Function(int) callback) async {
  final pending = callback(1);
  var index = 0;
  var last = '';
  while (index < 100000) {
    last = 'allocation-$index-${index * 17}';
    index++;
  }
  if (!last.startsWith('allocation-99999-')) throw StateError('Bad allocation');
  return await pending;
}
class Trace {
  String value = '';
  void append(String text) { value += text; }
}
Future<int> ordered(Trace trace) async {
  trace.append('start,');
  await Future<void>.value();
  trace.append('resume,');
  return 2;
}
Future<int> arrow(int value) async => (await stable(value)) + 200;
Future<int> passthrough(Future<int> value) { return value; }
Future<num> widened() async { await stable(0); return 2; }
Future<void> main() async {
  final wide = widened();
  print('futureType=${wide is Future<int>}');
  print('wide=${await wide}');
  final trace = Trace();
  final pending = ordered(trace);
  trace.append('caller,');
  print('before=${trace.value}');
  print('identity=${identical(pending, passthrough(pending))}');
  print('ordered=${await pending}');
  print('after=${trace.value}');
  print('arrow=${await arrow(2)}');

  print('calculate=${await calculate(5)}');
  print('nested=${await nested(5)}');
  final box = Box(10);
  print('method=${await box.step(3)}');
  final callback = make(10);
  print('closure=${await callback(2)}');
  print('gc=${await churn(callback)}');
  print('caught=${await caught()}');
}
