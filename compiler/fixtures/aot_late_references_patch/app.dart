class Payload {
  final int value;
  Payload(this.value);
}

class Holder<T> {
  late T field;
  late final T once;
  late T lazy = field;
}

int churn(Holder<Payload> holder) {
  var last = '';
  for (int i = 0; i < 100000; i++) {
    last = 'allocation-$i-${i * 17}';
  }
  if (!last.startsWith('allocation-99999-')) throw StateError('GC');
  return holder.once.value;
}

void fill(Holder<Payload> holder) {
  holder.field = Payload(13);
  holder.once = Payload(14);
}

int read(Holder<Payload> holder) =>
    holder.field.value + holder.once.value + holder.lazy.value;
void replace(Holder<Payload> holder) {
  holder.field = Payload(15);
}

void main() {
  final holder = Holder<Payload>();
  fill(holder);
  print('first:${read(holder)}');
  print('gc:${churn(holder)}');
  replace(holder);
  print('next:${read(holder)}');
  print('gc2:${churn(holder)}');
  print('identity:${identical(holder.lazy, holder.field)}');
}
