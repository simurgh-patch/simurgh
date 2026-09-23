int unchanged(int value) => value * 2;
int calculate(int value) {
  final retained = 'survivor:${unchanged(value)}';
  var index = 0;
  var total = 0;
  while (index < 100000) {
    final allocated = 'temporary:${unchanged(index)}';
    total += allocated.length;
    index++;
  }
  if (retained != 'survivor:200' || total == 0) {
    throw StateError('Lost interpreted root across mixed calls');
  }
  return unchanged(value) + 207;
}
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
