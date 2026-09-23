library pieces;

part 'src/impl.dart';

abstract class View {
  int read();
}

View make() => _Box(4);
int legacy(int value) => _old(value);
int privateValue() => _Box(8)._value;
