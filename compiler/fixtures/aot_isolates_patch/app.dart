import 'dart:isolate' as iso;

int counter = 7;
int worker(int value) => value + 10;
Future<int> compute(int value) => iso.Isolate.run(() => worker(value));
Future<int> changedCompute(int value) =>
    iso.Isolate.run(() => worker(value) + 100);
Future<int> nested() => iso.Isolate.run(() => iso.Isolate.run(() => worker(3)));
void spawned(iso.SendPort port) {
  port.send('${worker(4)}:$counter');
}

Future<String> spawnOnce() async {
  final port = iso.ReceivePort();
  try {
    final start = iso.Isolate.spawn<iso.SendPort>;
    final child = await start(
      spawned,
      port.sendPort,
      paused: true,
      debugName: 'simurgh-child',
    );
    child.resume(child.pauseCapability!);
    return await port.first as String;
  } finally {
    port.close();
  }
}

Future<int> failing() => iso.Isolate.run<int>(() {
  throw StateError('worker-${worker(0)}');
});
Future<void> main() async {
  counter = 99;
  print('local:${worker(2)}:$counter');
  print('run:${await compute(2)}');
  print('changed:${await changedCompute(2)}');
  print('nested:${await nested()}');
  print('spawn:${await spawnOnce()}');
  final execute = iso.Isolate.run<int>;
  print('tearoff:${await execute(() => worker(5))}');
  try {
    await failing();
  } catch (error) {
    print('error:$error');
  }
}
