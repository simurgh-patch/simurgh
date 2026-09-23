class Base {
  int _secret = 4;
  int _method({int value = 3}) => value;
}

String consume(Base object) {
  try {
    return '${object._secret}:${object._method()}';
  } catch (e) {
    return e.toString();
  }
}
