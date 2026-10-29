import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/widgets/edge_swipe_back.dart';
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
          path: '/poem',
          builder: (_, _) => Scaffold(
            body: EdgeSwipeBack(child: ListView(children: [for (var i = 0; i < 60; i++) Text('line $i')])),
          ),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    router.push('/poem');
    await tester.pumpAndSettle();
  }

  testWidgets('a sideways drag from either edge goes back, even a slanted one', (tester) async {
    await open(tester);
    await tester.dragFrom(const Offset(6, 300), const Offset(160, 40));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);

    router.push('/poem');
    await tester.pumpAndSettle();
    final w = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    await tester.dragFrom(Offset(w - 6, 300), const Offset(-160, 40));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('a short nudge or a drag in the middle does not go back, and scrolling still works', (tester) async {
    await open(tester);
    await tester.dragFrom(const Offset(6, 300), const Offset(30, 0));
    await tester.pumpAndSettle();
    expect(find.text('line 0'), findsOneWidget);
    await tester.dragFrom(const Offset(300, 400), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('line 0'), findsNothing);
    expect(find.text('home'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
