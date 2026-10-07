import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Release APKs are shrunk by R8. ML Kit creates its component registrars by reflection, so
/// without keep rules R8 strips their no-argument constructors, ML Kit fails to initialise,
/// and the translation plugin throws while registering ("MissingPluginException" on every
/// call). Seen on a Pixel 10 Pro with Ganj 1.1.1; debug builds (not shrunk) were fine.
void main() {
  test('ML Kit keep rules exist and the release build uses them', () {
    final rules = File('android/app/proguard-rules.pro');
    expect(rules.existsSync(), isTrue, reason: 'android/app/proguard-rules.pro is missing');
    // Rules only, not the comments explaining them.
    final text = rules.readAsLinesSync().where((l) => !l.trimLeft().startsWith('#')).join(' ');
    // The registrars (NaturalLanguageTranslateRegistrar, CommonComponentRegistrar…) all extend
    // ComponentRegistrar and are created with `new X()` by reflection: keep that constructor.
    expect(text, contains('-keep class * extends com.google.firebase.components.ComponentRegistrar { <init>(); }'));
    expect(text, contains('-keep class com.google_mlkit_translation.** { *; }'));
    expect(text, contains('-keep class com.google_mlkit_commons.** { *; }'));
    // Not the blanket rule: keeping the constructors is enough, and the shrinker should stay
    // free to drop the rest of ML Kit it can prove unused.
    expect(text, isNot(contains('-keep class com.google.mlkit.** { *; }')));

    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('proguard-rules.pro'), reason: 'release buildType must reference proguard-rules.pro');
  });
}
