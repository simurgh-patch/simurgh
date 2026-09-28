// @dart=3.0
import 'dart:isolate';

int worker(int x) => x + 1;
Future<int> compute() => Isolate.run(() => worker(2));
