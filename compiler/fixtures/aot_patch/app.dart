int unchanged(int value) => value * 2;
int calculate(int value) => unchanged(value) + 207;
int caller(int value) => calculate(value) + 1;
String caught() {
  try {
    fail();
    return 'missing exception';
  } catch (error) {
    return error.toString();
  }
}

void fail() => throw StateError('patched');
void main() {
  print('calculate=${calculate(100)}');
  print('caller=${caller(100)}');
  print('caught=${caught()}');
}
