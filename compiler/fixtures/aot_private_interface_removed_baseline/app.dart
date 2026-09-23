import 'base.dart';

class Original extends Base {}

Base make() => Added();
void main() {
  print(consume(make()));
}

class Added implements Base {}
