part 'counter_part.dart';

int storage = 1;
int get value => storage;
int get _secret => storage + 10;
int readPrivate() => _secret;
int Function(int) get callback => (int amount) => storage + amount;
