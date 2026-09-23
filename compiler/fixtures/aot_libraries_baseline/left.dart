import 'right.dart' as right;

int _offset() => 1;
int evaluate(int value) => value + _offset();
int cycle(int value) => value == 0 ? _offset() : right.cycle(value - 1);
int choose() => 100;
