part of 'base.dart';

class HomeMock implements Plain {
  dynamic noSuchMethod(Invocation invocation) => 8;
}

class Back extends Plain {
  dynamic noSuchMethod(Invocation invocation) => 9;
}

class ConcreteBack extends Plain {
  int get _field => 77;
  set _field(int value) {}
  dynamic noSuchMethod(Invocation invocation) => 42;
}
