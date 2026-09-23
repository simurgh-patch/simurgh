// @dart=3.12
import 'package:piece/piece.dart' as p;

int consume(p.View view) => view.read();
int modern(int _) => 7;
void main() {
  print('read:${consume(p.make())}');
  print('legacy:${p.legacy(3)}:${modern(0)}');
  print('type:${p.make().runtimeType}');
  print('private:${p.privateValue()}');
}
