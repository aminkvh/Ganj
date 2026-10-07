import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every selectable area uses the trimmed menu (Copy / Select all)', () {
    final missing = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.endsWith('startup_error.dart')) continue;
      final src = f.readAsStringSync();
      for (final m in RegExp(r'SelectionArea\(').allMatches(src)) {
        final call = src.substring(m.start, (m.start + 160).clamp(0, src.length));
        if (!call.contains('contextMenuBuilder: ganjSelectionMenu')) missing.add('${f.path}@${m.start}');
      }
    }
    expect(missing, isEmpty);
  });
}
