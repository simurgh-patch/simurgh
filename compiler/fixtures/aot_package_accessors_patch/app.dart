import 'package:piece/piece.dart' as piece;

int retained() => piece.value;

void main() {
  print('first:${retained()}:${piece.read()}');
  piece.value += 2;
  print('after:${retained()}:${piece.read()}');
}
