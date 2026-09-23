import 'dart:async';

class Tag {
  final String value;
  const Tag(this.value);
}

int starts = 0;
int closes = 0;
@Tag('sync')
@pragma('vm:never-inline')
Iterable<int> values(int count) sync* {
  starts++;
  try {
    for (int i = 0; i < count; i++) {
      yield i + 1;
    }
    yield* <int>[8, 9];
  } finally {
    closes++;
  }
}

@Tag('async')
Stream<int> events(int count) async* {
  try {
    for (int i = 0; i < count; i++) {
      await Future<void>.value();
      yield i + 2;
    }
    yield* Stream<int>.fromIterable(<int>[10, 11]);
  } finally {
    closes++;
  }
}

class Box<T> {
  final T item;
  Box(this.item);
  @Tag('items')
  @pragma('vm:never-inline')
  Iterable<T> items() sync* {
    yield item;
    yield item;
  }

  @Tag('stream')
  Stream<T> stream() async* {
    yield item;
    await Future<void>.value();
    yield item;
  }
}

Future<void> main() async {
  final iterable = values(2);
  print('lazy:$starts:$closes');
  print(iterable.toList());
  print(iterable.toList());
  print('replay:$starts:$closes');
  print(await events(2).toList());
  final box = Box<String>('x');
  print(box.items().toList());
  print(await box.stream().toList());
  print('done:$starts:$closes');
}
