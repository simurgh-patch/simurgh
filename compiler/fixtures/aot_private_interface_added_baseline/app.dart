import 'base.dart';

class Original extends Base {}

Base make() => Original();
void main() {
  print(consume(make()));
}
