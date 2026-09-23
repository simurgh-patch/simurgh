// Ordinary Dart code: no patch annotation or manually written bridge.
int calculateTotal(int count) => count * 100 + 7;

abstract class Pricing {
  int quote(int count);
}

class StandardPricing implements Pricing {
  @override
  int quote(int count) => calculateTotal(count);
}

class DiscountPricing implements Pricing {
  @override
  int quote(int count) => calculateTotal(count) - 10;
}

int virtualCall(Pricing pricing, int count) => pricing.quote(count);

class Box<T> {
  Box(this.value);
  final T value;
}

int Function(int) makeAdder(int base) =>
    (value) => base + value;

String exceptionBoundary() {
  try {
    throw StateError('probe');
  } on StateError catch (error) {
    return error.message;
  }
}

Map<String, Object> semanticProbe() => {
  'direct': calculateTotal(2),
  'virtual': virtualCall(DiscountPricing(), 2),
  'generic': Box<int>(42).value,
  'closure': makeAdder(10)(5),
  'exception': exceptionBoundary(),
};

Future<List<int>> deterministicItems() async {
  // Fixed local latency avoids network variance in the initial benchmark.
  // Real network benchmarks are a separate scenario, not measured by this.
  await Future<void>.delayed(const Duration(milliseconds: 40));
  return List.generate(200, calculateTotal);
}
