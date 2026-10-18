/// Ganjoor's literary devices («آرایه‌های ادبی»): the catalogue of devices with their named
/// roles («جایگاه‌ها»), and the devices tagged on a poem's couplets.
class LiteraryDevice {
  const LiteraryDevice({required this.id, required this.name, this.key, this.definition, this.slots = const {}});

  factory LiteraryDevice.fromJson(Map<String, dynamic> j) => LiteraryDevice(
    id: j['id'] as int,
    name: (j['name'] as String?) ?? '',
    key: j['key'] as String?,
    definition: j['definition'] as String?,
    slots: {for (final s in (j['slots'] as List? ?? const [])) (s as Map)['id'] as int: (s['name'] as String?) ?? ''},
  );

  final int id;
  final String name;

  /// Latin key of a core device (tashbih, esteare…); null for devices users defined later.
  final String? key;
  final String? definition;

  /// Role names by slot id.
  final Map<int, String> slots;
}

/// One role filled in a tag: words of the beyt (1-based [misra] and inclusive 1-based word
/// range), a concept, or free text — often a span together with the concept it stands for.
class LiteraryPart {
  const LiteraryPart({required this.slotId, this.misra = 0, this.wordStart, this.wordEnd, this.concept, this.text});

  factory LiteraryPart.fromJson(Map<String, dynamic> j) => LiteraryPart(
    slotId: j['slotId'] as int,
    misra: (j['misra'] as int?) ?? 0,
    wordStart: j['wordStart'] as int?,
    wordEnd: j['wordEnd'] as int?,
    concept: (j['concept'] as Map<String, dynamic>?)?['name'] as String?,
    text: j['text'] as String?,
  );

  final int slotId;

  /// 0 when the part points at no words.
  final int misra;
  final int? wordStart, wordEnd;
  final String? concept;
  final String? text;
}

class LiteraryTag {
  const LiteraryTag({
    required this.coupletIndex,
    required this.deviceId,
    this.parts = const [],
    this.uncertain = false,
    this.fromCorpus = false,
  });

  factory LiteraryTag.fromJson(Map<String, dynamic> j) => LiteraryTag(
    coupletIndex: (j['coupletIndex'] as int?) ?? 0,
    deviceId: j['deviceId'] as int,
    uncertain: (j['uncertain'] as bool?) ?? false,
    fromCorpus: ((j['originRef'] as String?) ?? '').startsWith('persian-literary-corpus'),
    parts: [
      for (final p in [
        ...(j['parts'] as List? ?? const []),
      ]..sort((a, b) => (((a as Map)['order'] as int?) ?? 0).compareTo(((b as Map)['order'] as int?) ?? 0)))
        LiteraryPart.fromJson(p as Map<String, dynamic>),
    ],
  );

  /// Zero-based, like the verses' coupletIndex.
  final int coupletIndex;
  final int deviceId;
  final List<LiteraryPart> parts;
  final bool uncertain;

  /// Imported from «A Corpus of Persian Literary Text» (MIT), not tagged on Ganjoor.
  final bool fromCorpus;
}
