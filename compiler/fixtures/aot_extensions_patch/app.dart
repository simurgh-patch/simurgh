import 'dart:async';
import 'other.dart' as other;
import 'other.dart' show remote;

extension Text on String {
  static int state = 1;
  static final int initial = state;
  static late int lateValue = state + 1;
  static const int step = 2;
  static int update() {
    state += step;
    return state;
  }

  int get score => length + 10;
  String decorate([String suffix = '!']) => '$this$suffix';
  static int amount() => 20 + state;
  static int retainedStatic() => amount();
  int chained() => score + decorate().length;
}

extension Values<T> on List<T> {
  T firstOr(T fallback) => isEmpty ? fallback : first;
  R convert<R>(R Function(T) f) => f(first);
  set head(T value) {
    this[0] = value;
  }

  T get head => this[0];
}

int retained() => 'abc'.score;

extension Nullable on String? {
  String get label => this ?? 'null';
}

extension on int {
  int anonymous() => this + 4;
}

int receiverCount = 0;
String? receiver() {
  receiverCount++;
  return null;
}

Future<String> deferred() async => 'future';
Future<void> main() async {
  Text.state = 5;
  print(
    'storage:${Text.update()}:${Text.initial}:${Text.lateValue}:${Text.state}',
  );
  print('static:${Text.retainedStatic()}');
  print('null:${receiver()?.score}:${receiverCount}:${receiver().label}');
  print('anonymous:${3.anonymous()}');
  print('remote:${remote()}:${other.Text(2).score}');
  print('async:${(await deferred()).decorate()}');
  print('score:${retained()}:${Text("a").chained()}');
  final f = 'a'.decorate;
  print('tearoff:${f()}');
  final values = [2];
  values.head += 3;
  print(
    'generic:${values.firstOr(0)}:${Values<int>(values).convert((i) => i.toString())}',
  );
}
