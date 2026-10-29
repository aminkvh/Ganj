import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/ui/keyboard_nav.dart';
import 'package:go_router/go_router.dart';

void main() {
  late GoRouter router;

  Future<void> open(WidgetTester tester) async {
    router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('home')),
        ),
        GoRoute(
          path: '/deep',
          builder: (_, _) => Scaffold(
            body: Column(
              children: const [
                Text('deep'),
                TextField(key: ValueKey('field')),
              ],
            ),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        builder: (_, child) => KeyboardNav(router: router, child: child!),
      ),
    );
    router.push('/deep');
    await tester.pumpAndSettle();
  }

  testWidgets('Escape and Backspace go back', (tester) async {
    await open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);

    router.push('/deep');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('Backspace in a text field only edits the text', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('field')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(find.text('deep'), findsOneWidget);
  });
}
