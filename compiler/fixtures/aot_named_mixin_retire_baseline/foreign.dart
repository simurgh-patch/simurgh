class Foreign<T> {
  T? _secret;
}

Object? access(Foreign<int> value) {
  try {
    return value._secret;
  } catch (e) {
    return e.toString();
  }
}
