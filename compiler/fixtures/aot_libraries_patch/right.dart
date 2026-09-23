import 'left.dart' as left;

int _offset() => 2;
int evaluate(int value) => value + _offset();
int cycle(int value) => value == 0 ? _offset() : left.cycle(value - 1);
int choose() => 200;
