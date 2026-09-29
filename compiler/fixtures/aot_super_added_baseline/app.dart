class Root {
  String value() => 'root';
}

mixin Paint on Root {
  String render() => 'plain';
}

class App extends Root with Paint {}

String run() => App().render();
void main() {
  print(run());
}
