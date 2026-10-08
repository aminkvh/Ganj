import 'dart:io';

/// Start-up steps, appended to the same `%TEMP%\ganj.log` the Windows runner writes, so one
/// file shows how far the app got on a computer where it shows nothing ("white window").
/// Never throws: a log that can't be written must not break start-up.
class StartupLog {
  const StartupLog(this.file);

  final File file;

  static File defaultFile() => File('${Directory.systemTemp.path}${Platform.pathSeparator}ganj.log');

  void step(String what) {
    try {
      final t = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      final stamp = '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
      file.writeAsStringSync('$stamp  dart: $what\n', mode: FileMode.append, flush: true);
    } catch (_) {
      // Nothing to do: diagnostics must never get in the way.
    }
  }
}
