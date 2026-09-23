import 'dart:async';

final events = <String>[];
sequence() sync* {
  yield 11;
  yield 12;
}

flow() async* {
  yield 13;
  yield 14;
}

Stream<int> nested() async* {
  try {
    yield 15;
    yield 16;
  } finally {
    events.add('nested-final');
  }
}

Stream<int> outer() async* {
  try {
    yield* nested();
    events.add('after-delegate');
  } finally {
    events.add('outer-final');
  }
}

Iterable<int> closureValues() {
  final make = () sync* {
    yield 17;
    yield 18;
  };
  return make();
}

Stream<int> closureEvents() {
  final make = () async* {
    yield 19;
    yield 20;
  };
  return make();
}

class Payload {
  final String value;
  Payload(this.value);
}

Stream<String> held(Completer<void> gate, Completer<void> ready) async* {
  final payload = Payload('patched-held');
  yield 'start';
  ready.complete();
  await gate.future;
  yield payload.value;
}

int exerciseHeap() {
  var checksum = 0;
  for (int i = 0; i < 250000; i++) {
    final items = List<int>.filled(100, i);
    checksum += items[0];
  }
  return checksum;
}

class VoidBox<T> {
  const VoidBox();
}

typedef VoidAlias<T> = VoidBox<T>;
Iterable<VoidAlias<void>> tokens() sync* {
  yield const VoidAlias<void>();
}

Stream<void> ticks() async* {
  yield null;
  yield null;
}

Future<void> main() async {
  print('void:${tokens().length}:${await ticks().length}');
  final gate = Completer<void>();
  final ready = Completer<void>();
  final collected = held(gate, ready).toList();
  await ready.future;
  print('heap:${exerciseHeap()}');
  gate.complete();
  print('held:${await collected}');
  print('inferred:${sequence().toList()}:${await flow().toList()}');
  print(
    'closures:${closureValues().toList()}:${await closureEvents().toList()}',
  );
  final received = <int>[];
  final done = Completer<void>();
  final paused = Completer<void>();
  final resume = Completer<void>();
  late StreamSubscription<int> subscription;
  subscription = outer().listen(
    (int value) {
      received.add(value);
      if (received.length == 1) {
        subscription.pause(resume.future);
        paused.complete();
      }
    },
    onDone: () {
      done.complete();
    },
  );
  await paused.future;
  await Future<void>.value();
  print('paused:$received:$events');
  resume.complete();
  await done.future;
  print('resumed:$received:$events');
  events.clear();
  await for (final item in outer()) {
    print('cancel:$item');
    break;
  }
  print('cancelled:$events');
}
