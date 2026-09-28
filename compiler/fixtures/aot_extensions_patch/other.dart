// @dart=3.0
extension Text on int {
  int get score => this * 3;
}

int remote() => 3.score;
