import 'base.dart';

class Child extends Base<int> {
  int value = 1000;
  Child(super.value, super.fixed);
  int update(int delta) {
    super.value += delta;
    return super.value++ + ++super.value;
  }

  int parentValue() => super.value;
  int firstSuper() => value;
  int readFinal() => super.fixed;
  int initialize(int input) {
    super.deferred = input;
    super.once = input + 1;
    return super.deferred + super.once;
  }

  int optionalValue(int Function() create) => super.optional ??= create();
  Future<int> asyncUpdate(Future<int> Function() create) async {
    super.value += await create();
    return super.value;
  }
}

class Middle extends Base<int> {
  Middle() : super(2, 0);
  int get value => super.value + 100;
}

class MixedAccess extends Middle {
  int change() => super.value += 3;
  int stored() => super.value;
}

class FieldParent {
  int value = 1;
  final int fixed = 2;
}

class FieldChild extends FieldParent {}

class Implementation implements FieldChild {
  int value = 4;
  final int fixed = 5;
  late int deferred;
  late final int once;
  int? optional;
}

class Payload {
  final int number;
  Payload(this.number);
}

class Holder extends Base<Payload> {
  Holder(Payload payload) : super(payload, payload);
  void store(Payload payload) {
    super.deferred = payload;
  }

  int read() => super.deferred.number;
}

class Mock implements Child {
  dynamic noSuchMethod(Invocation invocation) => 77;
}

Payload make() => Payload(10);
int observe(Holder holder) => holder.deferred.number;
int invoke(Child child) => child.update(2);
int mockRead(Child child) => child.parentValue();
String churn(Holder holder, int Function() read) {
  var last = '';
  for (int i = 0; i < 100000; i++) {
    last = 'allocation-$i-${i * 17}';
  }
  if (!last.startsWith('allocation-99999-')) throw StateError('GC');
  return '${observe(holder)}:${read()}';
}

Future<void> main() async {
  final child = Child(3, 7);
  print('update:${invoke(child)}:${child.parentValue()}:${child.value}');
  print('first:${child.firstSuper()}');
  print('final:${child.readFinal()}');
  print('late:${child.initialize(10)}');
  try {
    child.initialize(20);
  } catch (_) {
    print('repeat:true:${child.deferred}');
  }
  int calls = 0;
  int create() {
    calls++;
    return 4;
  }

  print(
    'optional:${child.optionalValue(create)}:${child.optionalValue(create)}:$calls',
  );
  Future<int> later() async {
    calls++;
    return 3;
  }

  print('async:${await child.asyncUpdate(later)}:$calls');
  final mixed = MixedAccess();
  print('accessors:${mixed.change()}:${mixed.stored()}');
  print('private:${PrivateChild().update()}');
  print('mock:${mockRead(Mock())}');
  final FieldChild implemented = Implementation();
  implemented.value += 2;
  print('implemented:${implemented.value}:${implemented.fixed}');
  final holder = Holder(Payload(1));
  holder.store(make());
  print('gc:${churn(holder, holder.read)}');
}
