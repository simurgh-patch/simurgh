class Base<T> {
  T value;
  Base(this.value);
  int run(int x) => x + 1;
  int get current => 5;
  set current(int next) {}
}

mixin First<T> on Base<T> {
  int count = 0;
  int run(int x) {
    count++;
    return super.run(x) + 20;
  }

  T choose(T other) => value;
  int get current => super.current + 3;
  set current(int next) {
    count = next;
    super.current = next;
  }

  int Function() callback() =>
      () => run(count + 1);
}
mixin Second<T> on Base<T> {
  int run(int x) => super.run(x) * 2;
}

mixin class Label {
  String label() => 'new';
}

mixin Shape {
  String extra = 'abcd';
  int size() => extra.length;
}

class Shaped with Shape {}

abstract interface class Tagged {
  String tag();
}

mixin Tagger implements Tagged {
  String tag() => 'tag';
}

class TaggedBox with Tagger {}

base mixin LockedMixin {
  int locked() => 2;
}

final class LockedBox with LockedMixin {}

mixin Fresh on Base<int> {
  int run(int x) => super.run(x) + 200;
}

class Freshly extends Base<int> with Fresh {
  Freshly(super.value);
}

Base<int> fresh() => Freshly(1);
int shape(Shape value) => value.size();
int churn(int Function() callback) {
  var last = '';
  for (int i = 0; i < 100000; i++) {
    last = 'allocation-$i-${i * 17}';
  }
  if (!last.startsWith('allocation-99999-')) throw StateError('GC');
  return callback();
}

class Combined extends Base<int> with First<int>, Second<int>, Label {
  Combined(super.value);
  int run(int x) => super.run(x) + 3;
}

class Added extends Base<int> with First<int>, Label {
  Added(super.value);
}

Base<int> make() => Added(8);
int invoke(Base<int> value) => value.run(2);
int choose(First<int> value) => value.choose(7);
void main() {
  final combined = Combined(3);
  final added = make();
  print('combined:${invoke(combined)}');
  print('count:${combined.count}');
  print('choose:${choose(combined)}');
  print('label:${combined.label()}');
  print('new:${invoke(added)}');
  print('type:${added is First<int>}:${added is Label}');
  print('chooseNew:${choose(added as First<int>)}');
  combined.current = 4;
  print('accessors:${combined.current}:${combined.count}');
  print('gc:${churn(combined.callback())}');
  print('shape:${shape(Shaped())}');
  print('fresh:${invoke(fresh())}');
  print('interface:${(TaggedBox() as Tagged).tag()}');
  print('baseMixin:${LockedBox().locked()}');
  print('mixinClass:${Label().label()}');
}
