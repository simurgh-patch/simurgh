class Num {
  final int n;
  Num(this.n);
  Num operator +(Num other) => Num(n + other.n + 10);
  Num operator -(Num other) => Num(n - other.n - 10);
  Num operator -() => Num(-n - 10);
  Num operator ~() => Num(~n);
  int operator *(int other) => n * other;
  bool operator <(Num other) => n < other.n;
  bool operator ==(Object other) => other is Num && n % 10 == other.n % 10;
  int get hashCode => n % 10;
}

class Child extends Num {
  Child(super.n);
  Num operator +(Num other) => super + other;
  Num operator -(Num other) => super - other;
  Num operator -() => -super;
  Num operator ~() => ~super;
  bool operator ==(Object other) => super == other;
  int get hashCode => super.hashCode;
  bool unequal(Object? other) => super != other;
}

class Bucket<T> {
  final List<T> values;
  Bucket(this.values);
  T operator [](int index) => values[index];
  void operator []=(int index, T next) {
    values[index] = next;
  }
}

class Strings extends Bucket<String> {
  Strings(super.values);
  String change() => super[0] = 'changed';
  String append() => super[0] += '!!';
}

class IndexBase {
  final List<int> values = [2];
  String trace = '';
  int operator [](int index) {
    trace += 'g';
    return values[index];
  }

  void operator []=(int index, int next) {
    trace += 's';
    values[index] = next;
  }
}

class IndexChild extends IndexBase {
  int index() {
    trace += 'i';
    return 0;
  }

  int rhs() {
    trace += 'r';
    return 4;
  }

  Future<int> delayed() async {
    trace += 'a';
    await Future<void>.value();
    values[0] = 100;
    trace += 'r';
    return 5;
  }

  int assign() => super[index()] = rhs();
  int add() => (super[index()] += rhs()) + 10;
  int fail() {
    trace += 'r';
    throw StateError('operand');
  }

  int failed() => super[index()] += fail();
  int addedSuper() => super[index()] *= rhs();
  int prefix() => ++super[index()];
  int postfix() => super[index()]++;
  Future<int> asyncAdd() async => super[index()] += await delayed();
}

class NullableBase {
  int? value;
  String trace = '';
  int? operator [](int index) {
    trace += 'g';
    return value;
  }

  void operator []=(int index, int? next) {
    trace += 's';
    value = next;
  }
}

class NullableChild extends NullableBase {
  int index() {
    trace += 'i';
    return 0;
  }

  int rhs() {
    trace += 'r';
    return 7;
  }

  int assign() => super[index()] ??= rhs();
}

class Added extends Num {
  Added(super.n);
  Num operator +(Num other) => Num(n + other.n + 100);
}

Num make() => Added(9);
int invoke(Num value) => (value + Num(3)).n;
int negative(Num value) => (-value).n;
String dynamicOps(dynamic value) =>
    '${(-value).n}:${(value - Num(2)).n}:${(value + Num(2)).n}';
bool equal(Num left, Object? right) => left == right;
int churn(Num value) {
  var last = '';
  for (int i = 0; i < 100000; i++) {
    last = 'allocation-$i-${i * 17}';
  }
  if (!last.startsWith('allocation-99999-')) throw StateError('GC');
  return (value + Num(1)).n;
}

class WriteOnly {
  String stored = '';
  void operator []=(int index, String value) {
    stored = value;
  }
}

class WriteChild extends WriteOnly {
  String put() => super[0] = 'rhs';
}

class Ops {
  final int n;
  Ops(this.n);
  double operator /(int v) => n / v;
  int operator ~/(int v) => (n + 10) ~/ v;
  int operator %(int v) => n % v;
  int operator &(int v) => n & v;
  int operator |(int v) => n | v;
  int operator ^(int v) => n ^ v;
  int operator <<(int v) => n << v;
  int operator >>(int v) => n >> v;
  int operator >>>(int v) => n >>> v;
  bool operator <=(int v) => n <= v;
  bool operator >(int v) => n > v;
  bool operator >=(int v) => n >= v;
}

Future<void> main() async {
  final child = Child(8);
  print(
    'arithmetic:${invoke(child)}:${(child - Num(3)).n}:${negative(child)}:${(~child).n}:${child * 2}:${child < Num(9)}',
  );
  print(
    'equality:${equal(child, Num(18))}:${equal(child, null)}:${child.unequal(null)}:${child.hashCode}',
  );
  print('dynamic:${dynamicOps(child)}');
  final made = make();
  print('new:${invoke(made)}:${churn(made)}');
  final strings = Strings(['a']);
  print('generic:${strings.change()}:${strings.append()}:${strings[0]}');
  final index = IndexChild();
  print('assign:${index.assign()}:${index.values[0]}:${index.trace}');
  index.trace = '';
  print('compound:${index.add()}:${index.values[0]}:${index.trace}');
  index.trace = '';
  print('prefix:${index.prefix()}:${index.values[0]}:${index.trace}');
  index.trace = '';
  print('postfix:${index.postfix()}:${index.values[0]}:${index.trace}');
  index.trace = '';
  print('async:${await index.asyncAdd()}:${index.values[0]}:${index.trace}');
  final nullable = NullableChild();
  print('nullFirst:${nullable.assign()}:${nullable.trace}');
  nullable.trace = '';
  print('nullSecond:${nullable.assign()}:${nullable.trace}');
  index.trace = '';
  print('addedSuper:${index.addedSuper()}:${index.values[0]}:${index.trace}');
  index.trace = '';
  try {
    index.failed();
  } on StateError {
    print('failed:${index.values[0]}:${index.trace}');
  }
  final writer = WriteChild();
  print('writeOnly:${writer.put()}:${writer.stored}');
  final ops = Ops(11);
  print(
    'operators:${ops / 2}:${ops ~/ 2}:${ops % 2}:${ops & 2}:${ops | 2}:${ops ^ 2}:${ops << 2}:${ops >> 2}:${ops >>> 2}:${ops <= 11}:${ops > 11}:${ops >= 11}',
  );
}
