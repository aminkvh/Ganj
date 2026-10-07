import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

export 'app_localizations.dart';

extension L10nContext on BuildContext {
  L10n get l10n => L10n.of(this);
}

/// Badge for a verse in another language (Ganjoor language ids); Persian (1) gets none.
String? verseLanguageLabel(L10n l, int? id) => switch (id) {
  2 => l.langArabic,
  3 => l.langTurkish,
  4 => l.langKurdish,
  5 => l.langMazandarani,
  6 => l.langGilaki,
  7 => l.langIsfahani,
  _ => null,
};
