part of 'app.dart';

int read(dynamic box) => box._read();
int field(dynamic box) => box._value;
bool isolated(dynamic box) {
  try {
    box._read();
  } on NoSuchMethodError {
    return true;
  }
  return false;
}

bool fieldIsolated(dynamic box) {
  try {
    print(box._value);
  } on NoSuchMethodError {
    return true;
  }
  return false;
}

void main() {
  final box = _Box(3);
  print('read:${read(box)}');
  print('field:${field(box)}');
  print('private:${isolated(other.make())}:${fieldIsolated(other.make())}');
}
