import 'dart:ffi';

@Native<Pointer<Void> Function(IntPtr, IntPtr)>(symbol: 'calloc')
external Pointer<Void> allocate(int count, int size);
@Native<Void Function(Pointer<Void>)>(symbol: 'free')
external void release(Pointer<Void> value);

final class Pair extends Struct {
  @Int32()
  external int x;
  @Int32()
  external int y;
  int score() => x * 10 + y;
}

int work(Pointer<Pair> value) {
  value.ref.x = 5;
  value.ref.y = 4;
  return value.ref.score();
}

void main() {
  final pointer = allocate(1, sizeOf<Pair>()).cast<Pair>();
  try {
    print('struct:${work(pointer)}:${pointer.ref.x}:${pointer.ref.y}');
  } finally {
    release(pointer.cast<Void>());
  }
}
