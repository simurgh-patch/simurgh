int unchanged(int value) => value * 2;
int calculate(int value) => unchanged(value) + 7;
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
