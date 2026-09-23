import 'dart:async';

final log = <String>[];
int revision() => 1;
Iterable<int> guarded(int count) sync* {
  log.add('sync-start');
  try {
    for (int i = 0; i < count; i++) {
      yield i + 1;
    }
    throw StateError('sync');
  } finally {
    log.add('sync-final');
  }
}

Stream<int> guardedAsync(int count) async* {
  log.add('async-start');
  try {
    for (int i = 0; i < count; i++) {
      await Future<void>.value();
      yield i + 2;
    }
    throw StateError('async');
  } finally {
    log.add('async-final');
  }
}

Iterable<T> replay<T>(T value) sync* {
  Iterable<T> local(T item) sync* {
    yield item;
    yield item;
  }

  yield* local(value);
}

class Box<T> {
  final T item;
  Box(this.item);
  Stream<T> stream() async* {
    yield item;
    await Future<void>.value();
    yield item;
  }
}

int exerciseHeap() {
  var checksum = 0;
  for (int i = 0; i < 250000; i++) {
    final items = List<int>.filled(100, i);
    checksum += items[0];
  }
  return checksum;
}

Future<void> main() async {
  final iterator = guarded(2).iterator;
  print('lazy:${log.length}');
  print('first:${iterator.moveNext()}:${iterator.current}');
  print('heap:${exerciseHeap()}');
  print('second:${iterator.moveNext()}:${iterator.current}');
  try {
    iterator.moveNext();
  } catch (e) {
    print('error:$e');
  }
  print('end:${iterator.moveNext()}:$log');
  log.clear();
  final events = guardedAsync(4);
  print('async-lazy:${log.length}');
  final seen = <int>[];
  await for (final item in events) {
    seen.add(item);
    if (seen.length == 2) break;
  }
  print('cancel:$seen:$log');
  log.clear();
  final failure = <int>[];
  try {
    await for (final item in guardedAsync(1)) {
      failure.add(item);
    }
  } catch (e) {
    print('async-error:$e');
  }
  print('failure:$failure:$log');
  print('generic:${replay<String>('x').toList()}');
  print('method:${await Box<int>(3).stream().toList()}');
  print('rev:${revision()}');
}
