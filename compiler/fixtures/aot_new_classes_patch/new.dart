import 'base.dart';

class Payload {
  int bias;
  Payload(this.bias);
  int amount() => bias;
}

class New extends Base {
  int value;
  Payload payload;
  New(int value) : value = value + 10, payload = Payload(100), super(value);

  @override
  int compute(int delta) => super.compute(delta) + payload.amount();

  @override
  String label() => 'new';
}

class Leaf extends New {
  Leaf(int value) : super(value);

  @override
  int compute(int delta) => super.compute(delta) + 1;
}
