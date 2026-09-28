// @dart=3.0
extension Text on int {
  int get score => this * 2;
}

int remote() => 3.score;
