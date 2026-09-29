class Root {
  String value() => 'root';
}

mixin Paint on Root {
  String render() => '${super.value()}:paint';
}

class App extends Root with Paint {}

String run() => App().render();
void main() {
  print(run());
}
