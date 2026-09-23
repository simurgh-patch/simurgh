import 'package:meta/meta.dart';

@immutable
class Model {
  final int value;
  const Model(this.value);
  @protected
  @mustCallSuper
  int read() => value;
}

class Child extends Model {
  const Child(super.value);
  @override
  int read() => super.read() + 1;
}

@visibleForTesting
int make() => Child(3).read();
void main() {
  print(make());
}
