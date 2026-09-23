part of 'app.dart';

int _count = 0;
void bump() {
  _count += 10;
}

const _Token stored = _Token(1);

int _bonus() => math.max(5, 1);
