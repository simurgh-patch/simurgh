int adjust(int value, {int scale = 2, required int bias}) => value * scale + bias + 100;
int optional(int value, [int delta = 3]) => (value + delta) * 2;
int consume(int value, {required int bias, int Function(int, {int scale, required int bias}) callback = adjust}) => callback(value, bias: bias);
int Function(int, {int increment}) make(int start) {
  return (int value, {int increment = 2}) => (start + value + increment) * 3;
}
class Base {
  int offset;
  Base({this.offset = 4});
  int compute(int value, {int scale = 2, int bias = 1}) => offset + adjust(value, scale: scale, bias: bias);
}
class Child extends Base {
  Child({int offset = 4}) : super(offset: offset);
  int compute(int value, {int scale = 2, int bias = 1}) => super.compute(value, scale: scale, bias: bias) + Base(offset: 50).offset;
}
int invoke(Base object) => object.compute(5);
void main() {
  print('named=${adjust(5, bias: 1)}');
  print('explicit=${adjust(5, bias: 4, scale: 3)}');
  print('optional=${optional(5)}');
  print('positional=${optional(5, 7)}');
  final object = Child();
  print('method=${invoke(object)}');
  print('methodExplicit=${object.compute(5, scale: 3, bias: 4)}');
  final closure = make(3);
  print('closure=${closure(4)}');
  print('closureExplicit=${closure(4, increment: 5)}');
  print('callback=${consume(5, bias: 1)}');
  final reference = adjust;
  print('tearoff=${reference(5, bias: 1)}');
}
