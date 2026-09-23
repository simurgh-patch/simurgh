int unchanged(int value) => value * 2;
int calculate(int value) {
  final retained = unchanged;
  return retained(value) + addition(3) + 7;
}

int viaReference(int value) {
  final callback = calculate;
  return callback(value) + 1;
}

void main() {
  print('calculate=${calculate(100)}');
  print('reference=${viaReference(100)}');
  print('identity=${calculate == calculate}');
  print('binding=${identical(1, 1)}');
}

int addition(int value) => value == 0 ? 200 : recurse(value - 1);
int recurse(int value) => addition(value);
bool identical(int first, int second) => false;
