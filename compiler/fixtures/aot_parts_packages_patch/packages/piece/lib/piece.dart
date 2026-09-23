library pieces;

part 'src/moved.dart';
part 'src/extra.dart';

abstract class View {
  int read();
}

View make() => Added(5);
int legacy(int value) => _old(value);
int privateValue() => _Box(8)._value;
