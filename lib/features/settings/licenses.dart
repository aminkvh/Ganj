import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

bool _registered = false;

/// Adds the app's own GPL-3.0 notice and the bundled fonts' OFL texts to Flutter's license page.
void registerLicenses() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(['گنج (Ganj)'], await rootBundle.loadString('NOTICE.md'));
    yield LicenseEntryWithLineBreaks(['گنج (Ganj)'], await rootBundle.loadString('LICENSE'));
    yield LicenseEntryWithLineBreaks(['Vazirmatn'], await rootBundle.loadString('assets/fonts/OFL-Vazirmatn.txt'));
    yield LicenseEntryWithLineBreaks([
      'Noto Nastaliq Urdu',
    ], await rootBundle.loadString('assets/fonts/OFL-NotoNastaliqUrdu.txt'));
  });
}
