import 'dart:async';

class Base {
  int get value => 1;
}

mixin Secret on Base {
  String _label() => 'secret';
}
mixin SecretReader on Base, Secret {
  String reveal() => super._label();
}

class SecretApp extends Base with Secret, SecretReader {}

abstract class AbstractBase implements Base {}

mixin Describe on Base {
  String describe() => 'value:$value';
}

class Actual extends AbstractBase with Describe {
  @override
  int get value => 20;
}

int shadow(int input) {
  final input = 70;
  return input;
}

class Cache {
  final int value;
  const Cache(this.value);
  int read() => value;
}

Future<int> promoted({Cache? cache, int fallback = 3}) async {
  cache ??= Cache(fallback);
  await Future<void>.value();
  return cache.read() + 10;
}

Future<T> generic<T extends num>(T? value, {required T fallback}) async {
  value ??= fallback;
  await Future<void>.value();
  return value;
}

Future<int> captured(int value, {int step = 1}) async {
  void increment() {
    value += step;
  }

  increment();
  increment();
  await Future<void>.value();
  increment();
  return value;
}

Future<int> asyncShadow(int value) async {
  final value = 90;
  await Future<void>.value();
  return value;
}

int starts = 0;
Iterable<int> lazy(int? value, [int fallback = 4]) sync* {
  starts++;
  value ??= fallback;
  yield value;
  yield value + 10;
}

Stream<int> stream(int? value, {int fallback = 5}) async* {
  value ??= fallback;
  await Future<void>.value();
  yield value;
  yield value + 10;
}

Future<int> retained(Future<int> value) => value;
Future<void> main() async {
  print('super:${Actual().describe()}');
  print('private:${SecretApp().reveal()}');
  print('shadow:${shadow(1)}');
  print(
    'promoted:${await promoted()}:${await promoted(cache: const Cache(8))}',
  );
  print('generic:${await generic<int>(null, fallback: 6)}');
  print('captured:${await captured(10, step: 2)}:${await asyncShadow(1)}');
  final values = lazy(null);
  print('lazy-before:$starts');
  print('lazy:${values.toList()}:$starts');
  print('stream:${await stream(null).toList()}');
  final future = Future<int>.value(12);
  print('identity:${identical(future, retained(future))}');
}
