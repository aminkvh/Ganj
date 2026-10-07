import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/version.dart';

void main() {
  test('the version shown in About is the one in pubspec.yaml', () {
    final line = File('pubspec.yaml').readAsLinesSync().firstWhere((l) => l.startsWith('version:'));
    expect(kAppVersion, line.split(':').last.trim().split('+').first);
  });
}
