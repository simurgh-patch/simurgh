import 'right.dart' as right;
import 'added.dart' show extra;

int _offset() => 101;
int evaluate(int value) => value + _offset() + extra();
int cycle(int value) => value == 0 ? _offset() : right.cycle(value - 1);
int choose() => 100;
