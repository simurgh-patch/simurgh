import 'dart:ffi';

@Native<Pointer<Void> Function(IntPtr, IntPtr)>(symbol: 'calloc')
external Pointer<Void> allocate(int count, int size);
@Native<Void Function(Pointer<Void>)>(symbol: 'free')
external void release(Pointer<Void> value);
int work(Pointer<Int32> pointer) {
  pointer.value = 30;
  pointer[1] = 40;
  return pointer.value + pointer[1];
}

void main() {
  final pointer = allocate(2, sizeOf<Int32>()).cast<Int32>();
  try {
    print('pointer:${work(pointer)}');
  } finally {
    release(pointer.cast<Void>());
  }
}
