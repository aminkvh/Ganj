import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/features/shahnameh/data/shahnameh_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the world loads from the app bundle', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final w = await c.read(shahnamehWorldProvider.future);
    expect(w.sections, hasLength(60));
    expect(w.people[60]!.en, 'Rostam');
    expect(w.ages, hasLength(4));
  });
}
