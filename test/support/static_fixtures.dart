import 'dart:io';

/// Request path prefix of the static copy on jsDelivr.
const staticPrefix = '/gh/ganjoor/ganjoor-data@main';

/// Trimmed real files of Ganjoor's static data copy (test/fixtures/static mirrors the CDN
/// paths), keyed by request path for a FakeAdapter.
Map<String, String> staticRoutes() {
  final root = Directory('test/fixtures/static');
  return {
    for (final f in root.listSync(recursive: true).whereType<File>())
      '$staticPrefix/${f.path.substring(root.path.length + 1).replaceAll(r'\', '/')}': f.readAsStringSync(),
  };
}
