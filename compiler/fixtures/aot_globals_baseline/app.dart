int shared = 1;
int starts = 0;
const int seed = 3;
const int derived = seed + 2;
int initialized = seed * 2;
late int delayed;
int once = 0;
int lazy = initialize();
int initialize() {
  starts++;
  return 10;
}

int readShared() => shared;
int changeShared() {
  shared += 2;
  return readShared();
}

int readValue() => initialized + derived;
int withDefault([int n = seed]) => n;

class Box {
  int value;
  Box(this.value);
  int read() => value;
}

Box held = Box(12);
int readHeld() => held.read();
int unready() {
  try {
    return delayed;
  } catch (error) {
    return -1;
  }
}

void main() {
  print('unready=${unready()}');
  print('held=${readHeld()}');
  print('shared=${changeShared()}:${readShared()}');
  print('value=${readValue()}');
  print('default=${withDefault()}');
  print('lazy=$lazy:$lazy:$starts');
  delayed = 4;
  delayed++;
  once = 8;
  print('late=$delayed:$once');
}
