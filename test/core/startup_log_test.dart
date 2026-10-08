import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/diag/startup_log.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('ganj_log_'));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('start-up steps are appended, each with a timestamp, to the same log the runner writes', () {
    final log = File('${dir.path}/ganj.log')..writeAsStringSync('2026-10-08 10:00:00  window created\n');
    final startup = StartupLog(log);
    startup.step('dart main');
    startup.step('first frame built');
    final lines = log.readAsLinesSync();
    expect(lines, hasLength(3));
    expect(lines[0], endsWith('window created'), reason: 'the runner line stays');
    expect(lines[1], matches(r'^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d  dart: dart main$'));
    expect(lines[2], endsWith('  dart: first frame built'));
  });

  test('an unwritable log never breaks start-up', () {
    final startup = StartupLog(File('${dir.path}/no/such/dir/ganj.log'));
    expect(() => startup.step('dart main'), returnsNormally);
  });

  test('the default log sits in the temp folder under the name the runner uses', () {
    expect(StartupLog.defaultFile().path, endsWith('ganj.log'));
    expect(StartupLog.defaultFile().parent.path, Directory.systemTemp.path);
  });
}
