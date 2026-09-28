// @dart=3.0
import 'dart:isolate';

int worker(int x) => x + 10;
Future<int> compute() => Isolate.run(() => worker(2));
