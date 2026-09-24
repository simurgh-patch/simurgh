int storage = 2;

int get value => storage;

set value(int next) {
  storage = next;
}

num retained() => value;

void main() {
  print('first:${retained()}');
  value += 1;
  print('after:${retained()}');
}
