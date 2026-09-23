var shared = 0;
var changed = 'word', other = 'same';
const increment = 4;
final callback = add;
final choose = <T>(T first, T second) => first;
int add(int value) => value + 10;
int stableRead() => shared;
int update() {
  shared += 10;
  return stableRead();
}

String describe() => changed.toString();
int viaStored() => callback(2);
int defaultArg([int value = increment]) => value;

class Box<T> {
  final value = 'long';
  final echo = (T value) => value;
  Box();
  int length() => value.toString().length;
  T run(T value) => echo(value);
}

final held = Box<int>();
int readHeld() => held.length();
void main() {
  print('state=${update()}:${stableRead()}');
  print('type=${describe()}:$other');
  print('stored=${viaStored()}');
  print('default=${defaultArg()}');
  print('generic=${choose<int>(3, 4)}:${choose<String>('a', 'b')}');
  print('field=${readHeld()}:${held.run(7)}');
}
