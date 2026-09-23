import 'base.dart';
import 'other.dart';

class Child extends Base<int> {
  Child() : super(2);
}

class Plain implements Child {}

class Both implements Child, Other {}

class Mock implements Child {
  dynamic noSuchMethod(Invocation invocation) {
    print('unexpected-business-noSuchMethod');
    return 42;
  }
}

class Live extends Base<int> {
  Live() : super(5);
}

mixin Real on Base<int> {}

class Mixed extends Base<int> with Real {
  Mixed() : super(6);
}
