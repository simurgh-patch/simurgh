class Box<T> {
  final T seed;
  int calls = 0;
  late T value = initialize();
  late final T once;
  late final T lazyFinal = initialize();
  late final inferred = initialize();
  late int empty;
  late final int patchOnly;
  int nilCalls = 0;
  late final int? nil = initNil();
  int? initNil() {
    nilCalls++;
    return null;
  }

  Box(this.seed);
  T initialize() {
    calls++;
    return seed;
  }

  T read() => value;
  void assign(T next) {
    once = next;
  }
}

int read(Box<int> box) => box.value;
void assign(Box<int> box, int value) {
  box.assign(value);
}

bool uninitialized(Box<int> box) {
  try {
    print(box.empty);
  } catch (error) {
    return error.toString().startsWith('LateInitializationError:');
  }
  return false;
}

bool duplicate(Box<int> box) {
  try {
    box.assign(99);
  } catch (error) {
    return error.toString().startsWith('LateInitializationError:');
  }
  return false;
}

int change(Box<int> box) {
  box.value = 10;
  return box.read();
}

void first(Box<int> box) {
  box.assign(7);
}

int churn(Box<int> box) {
  var last = '';
  for (int i = 0; i < 100000; i++) {
    last = 'allocation-$i-${i * 17}';
  }
  if (!last.startsWith('allocation-99999-')) throw StateError('GC');
  return box.once;
}

class Retry {
  int attempts = 0;
  late final int value = initialize();
  int initialize() {
    attempts++;
    if (attempts == 1) throw StateError('retry');
    return 9;
  }
}

class Shape {
  late int value;
  Shape() {
    value = 6;
  }
  int read() => value;
}

int shape(Shape value) => value.read();
void setOnly(Box<int> box) {}
bool duplicateOnly(Box<int> box) {
  try {
    setOnly(box);
  } catch (error) {
    return error.toString().startsWith('LateInitializationError:');
  }
  return false;
}

int onlyValue(Box<int> box) {
  try {
    return box.patchOnly;
  } catch (error) {
    if (!error.toString().startsWith('LateInitializationError:')) rethrow;
    return -1;
  }
}

void main() {
  final box = Box<int>(3);
  print('cold:${box.calls}');
  print('lazy:${read(box)}:${box.read()}:${box.calls}');
  print('final:${box.lazyFinal}:${box.lazyFinal}:${box.calls}');
  print('missing:${uninitialized(box)}');
  first(box);
  print('once:${box.once}:${duplicate(box)}');
  print('write:${change(box)}:${read(box)}');
  print('gc:${churn(box)}');
  final other = Box<int>(4);
  assign(other, 8);
  print('other:${other.once}:${other.calls}');
  print('nil:${box.nil}:${box.nil}:${box.nilCalls}');
  setOnly(box);
  print('only:${onlyValue(box)}:${duplicateOnly(box)}');
  print('inferred:${box.inferred}:${box.inferred}:${box.calls}');
  final retry = Retry();
  try {
    print(retry.value);
  } on StateError catch (error) {
    print('retry:$error');
  }
  print('retried:${retry.value}:${retry.value}:${retry.attempts}');
  print('shape:${shape(Shape())}');
}
