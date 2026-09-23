late final int shared;
late final int newlyWritten;
int starts = 0;
late final int lazy = initialize();
int initialize() {
  starts++;
  return 10;
}

int readShared() => shared;
int writeFromAot(int value) {
  shared = value;
  return shared;
}

int writeFromPatch() {
  shared = 3;
  return readShared();
}

int initializeUnused() {
  return -1;
}

bool beforeInitialization() {
  try {
    readShared();
    return false;
  } catch (error) {
    return error.toString().startsWith('LateInitializationError');
  }
}

bool rejectSecondWrite() {
  try {
    writeFromAot(99);
    return false;
  } catch (error) {
    return error.toString().startsWith('LateInitializationError');
  }
}

void main() {
  print('uninitialized=${beforeInitialization()}');
  print('shared=${writeFromPatch()}:${readShared()}');
  print('singleAssignment=${rejectSecondWrite()}:${readShared()}');
  print('unused=${initializeUnused()}');
  print('lazy=$lazy:$lazy:$starts');
}
