import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/startup_error.dart';

void main() {
  testWidgets('if start-up fails, the reader sees what went wrong instead of a blank window', (tester) async {
    await tester.pumpWidget(
      StartupErrorApp(error: StateError('database could not be opened'), logPath: r'C:\Users\x\ganj-startup.log'),
    );
    expect(find.textContaining('گنج نتوانست باز شود'), findsOneWidget);
    expect(find.textContaining('Ganj could not start'), findsOneWidget);
    expect(find.textContaining('database could not be opened'), findsOneWidget);
    expect(find.textContaining('ganj-startup.log'), findsOneWidget);
  });
}
