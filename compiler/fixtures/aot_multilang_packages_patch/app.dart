import 'package:engine_logic/engine_logic.dart' as engine;
import 'package:labels/labels.dart' as labels;
int stableRead(engine.Box box) => box.read();
void main() {
  print('compute=${engine.compute(2)}');
  print('box=${stableRead(engine.Box(3))}');
  print('label=${labels.label()}');
  print('message=${engine.message()}');
}
