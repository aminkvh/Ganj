/// A manifest value used as a path segment must not escape the install folder.
String _safeSegment(String s) {
  if (s.isEmpty || s == '.' || s.contains('..') || s.contains('/') || s.contains(r'\')) {
    throw FormatException('Unsafe name in voice manifest: "$s"');
  }
  return s;
}

/// What the voice download consists of: a version and its files with sizes and checksums.
class VoiceFile {
  const VoiceFile({required this.name, required this.size, required this.sha256});

  factory VoiceFile.fromJson(Map<String, dynamic> j) => VoiceFile(
    name: _safeSegment(j['name'] as String),
    size: (j['size'] as num).toInt(),
    sha256: (j['sha256'] as String).toLowerCase(),
  );

  final String name;
  final int size;
  final String sha256;

  Map<String, dynamic> toJson() => {'name': name, 'size': size, 'sha256': sha256};
}

List<VoiceFile> _filesOf(Object? l) => [
  for (final f in (l as List)) VoiceFile.fromJson((f as Map).cast<String, dynamic>()),
];

/// The variant a manifest without `variants` (version 1) is read as.
const kQualityVariant = 'quality';

/// The other variant: smaller and quicker, a little less natural.
const kFastVariant = 'fast';

/// The only variant keys a manifest may carry; others are ignored.
const _kKnownVariants = {kFastVariant, kQualityVariant};

/// A voice version: [files] are shared by every variant, [variants] maps a variant name (`fast`, `quality`) to the
/// files only that variant needs.
class VoiceManifest {
  const VoiceManifest({
    required this.version,
    required this.files,
    this.variants = const {kQualityVariant: <VoiceFile>[]},
  });

  factory VoiceManifest.fromJson(Map<String, dynamic> j) {
    final v = j['variants'];
    final variants = <String, List<VoiceFile>>{
      if (v is Map)
        for (final e in v.entries)
          if (_kKnownVariants.contains(e.key)) e.key as String: _filesOf(e.value),
    };
    return VoiceManifest(
      version: _safeSegment(j['version'] as String),
      files: _filesOf(j['files']),
      // No usable variant (version 1): the shared files are the whole quality voice.
      variants: variants.isEmpty ? const {kQualityVariant: <VoiceFile>[]} : variants,
    );
  }

  final String version;

  /// The files every variant needs.
  final List<VoiceFile> files;

  /// Variant name to the files only it needs.
  final Map<String, List<VoiceFile>> variants;

  /// The size of the shared files only; see [sizeOf] for what a variant downloads.
  int get totalBytes => files.fold(0, (a, f) => a + f.size);

  /// What installing [variant] downloads: the shared files plus its own.
  int sizeOf(String variant) => filesFor(variant).fold(0, (a, f) => a + f.size);

  /// The shared files followed by [variant]'s; throws [ArgumentError] for an unknown variant.
  List<VoiceFile> filesFor(String variant) {
    final own = variants[variant];
    if (own == null) {
      throw ArgumentError.value(variant, 'variant', 'not in the voice manifest');
    }
    return [...files, ...own];
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    'files': [for (final f in files) f.toJson()],
    'variants': {
      for (final e in variants.entries) e.key: [for (final f in e.value) f.toJson()],
    },
  };
}

/// Negative, zero or positive as version [a] is older than, the same as, or newer than [b]: numeric per dot part,
/// so 1.10.0 is newer than 1.9.0. A missing part, or one that is not a number, counts as 0.
int compareVersions(String a, String b) {
  final x = a.split('.'), y = b.split('.');
  for (var i = 0; i < x.length || i < y.length; i++) {
    final p = i < x.length ? int.tryParse(x[i]) ?? 0 : 0;
    final q = i < y.length ? int.tryParse(y[i]) ?? 0 : 0;
    if (p != q) return p.compareTo(q);
  }
  return 0;
}

/// Base URLs (ending in '/'); `voice.json` and every file sit under a base. Named by the voice version; the
/// first published ones (`ganj-zip-distill/`, `phone-v1`, voice 1.1.0) stay as they are for Ganj 1.6.0.
const kVoiceSources = <String, String>{
  'hf': 'https://huggingface.co/aminkvh/Ganj_voice/resolve/main/ganj-zip-distill-1.2.0/',
  'github': 'https://github.com/aminkvh/Ganj_voice/releases/download/phone-1.2.0/',
};

const String _devBase = String.fromEnvironment('GANJ_VOICE_BASE');

/// The sources the app uses: [kVoiceSources], or only `--dart-define=GANJ_VOICE_BASE=...` when set.
Map<String, String> voiceSources() => _devBase.isEmpty ? kVoiceSources : const {'dev': _devBase};
