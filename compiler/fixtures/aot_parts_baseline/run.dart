part of parts_demo;

void main() {
  final box = Child(3);
  print('private:${invoke(box)}:${stableRead(box)}');
  bump();
  print('state:$_count');
  print('closure:${churn(callback(box))}');
  print('new:${stableRead(make())}');
  print('identity:${identical(token(), stored)}');
  print('isolation:${_Hidden(1).runtimeType == other.hidden().runtimeType}');
  print('other:${other.read()}');
}
