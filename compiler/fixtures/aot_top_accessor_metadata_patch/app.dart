class Tag<T> {
  final T value;
  const Tag(this.value);
  const Tag.named(this.value);
}

const label = Tag<String>.named('getter');
int storage = 2;

@pragma('vm:never-inline')
@label
int get value => storage + 10;

@Tag<String>.named('setter')
set value(@Tag<int>(3) int next) {
  storage = next * 2;
}

int retained() => value;

void main() {
  print('first:${retained()}');
  value += 3;
  print('after:${retained()}');
}
