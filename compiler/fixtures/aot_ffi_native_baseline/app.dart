import 'dart:ffi';

@Native<Int32 Function(Int32)>()
external int abs(int value);

class NativeApi {
  @Native<Int32 Function(Int32)>(symbol: 'abs')
  external static int magnitude(int value);
}

int compute(int value) => abs(value) + NativeApi.magnitude(value);
void main() {
  print('native:${compute(-7)}');
}
