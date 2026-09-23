abstract interface class Port<T> {
  T get value;
}

class Box<T> implements Port<T> {
  final T value;
  const Box._(this.value);
  factory Box(T value) {
    if (value == null) throw ArgumentError('null');
    return Box._(value);
  }
  const factory Box.redirect(T value) = Box<T>._;
  const Box.named(T value) : this._(value);
}

class Cached {
  static final Cached _instance = Cached._();
  final int value = 7;
  Cached._();
  factory Cached() => _instance;
}

abstract class Choice implements Port<int> {
  factory Choice(int value) = Added;
}

class Original implements Choice {
  final int value;
  Original(this.value);
}

class Added implements Choice {
  final int value;
  Added(int value) : value = value + 10;
}

Port<int> make() => Choice(4);
int read(Port<int> value) => value.value;
Box<int> build(Box<int> Function(int) constructor) => constructor(5);
bool caught() {
  try {
    Box<int?>(null);
  } on ArgumentError {
    return true;
  }
  return false;
}

int churn(Port<int> Function(int) constructor) {
  var last = '';
  for (int i = 0; i < 100000; i++) {
    last = 'allocation-$i-${i * 17}';
  }
  if (!last.startsWith('allocation-99999-')) throw StateError('GC');
  return read(constructor(6));
}

void main() {
  print('factory:${read(Box<int>(2))}');
  print('redirect:${read(const Box<int>.redirect(3))}');
  print('generative:${read(const Box<int>.named(4))}');
  print(
    'const:${identical(const Box<int>.redirect(3), const Box<int>.named(3))}',
  );
  print('cache:${Cached().value}:${identical(Cached(), Cached())}');
  print('choice:${read(make())}');
  print('tearoff:${build(Box<int>.new).value}');
  print('redirectTearoff:${build(Box<int>.redirect).value}');
  print('caught:${caught()}');
  print('gc:${churn(Choice.new)}');
}
