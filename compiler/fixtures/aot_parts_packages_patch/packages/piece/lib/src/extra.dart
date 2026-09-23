part of '../piece.dart';

class Added extends _Box {
  Added(int value) : super(value);
  int read() => super.read() + 100;
}
