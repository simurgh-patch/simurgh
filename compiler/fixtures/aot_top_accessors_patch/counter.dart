part 'counter_part.dart';

int storage = 1;
int get value => storage + 10;
int get _secret => storage + 20;
int readPrivate() => _secret;
int Function(int) get callback => (int amount) => storage + amount + 30;
