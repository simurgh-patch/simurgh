int storage = 2;

num get value => storage + 0.5;

set value(num next) {
  storage = next.floor();
}

num retained() => value;

void main() {
  print('first:${retained()}');
  value += 1;
  print('after:${retained()}');
}
