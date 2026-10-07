import 'dart:convert';

import 'package:xml/xml.dart';

class Recitation {
  const Recitation({
    required this.id,
    required this.poemId,
    required this.title,
    required this.artist,
    required this.artistUrl,
    required this.mp3Url,
    required this.mp3Size,
    required this.audioOrder,
    required this.inSync,
  });

  final int id;
  final int poemId;
  final String title;
  final String artist;
  final String artistUrl;
  final String mp3Url;
  final int mp3Size;
  final int audioOrder;
  final bool inSync;

  Recitation copyWith({bool? inSync}) => Recitation(
    id: id,
    poemId: poemId,
    title: title,
    artist: artist,
    artistUrl: artistUrl,
    mp3Url: mp3Url,
    mp3Size: mp3Size,
    audioOrder: audioOrder,
    inSync: inSync ?? this.inSync,
  );

  Map<String, Object> toJson() => {
    'id': id,
    'poemId': poemId,
    'audioTitle': title,
    'audioArtist': artist,
    'audioArtistUrl': artistUrl,
    'mp3Url': mp3Url,
    'mp3SizeInBytes': mp3Size,
    'audioOrder': audioOrder,
    'inSyncWithText': inSync,
  };

  factory Recitation.fromJson(Map<String, dynamic> j) => Recitation(
    id: j['id'] as int,
    poemId: (j['poemId'] as int?) ?? 0,
    title: (j['audioTitle'] as String?) ?? '',
    artist: (j['audioArtist'] as String?) ?? '',
    artistUrl: (j['audioArtistUrl'] as String?) ?? '',
    mp3Url: (j['mp3Url'] as String?) ?? '',
    mp3Size: (j['mp3SizeInBytes'] as int?) ?? 0,
    audioOrder: (j['audioOrder'] as int?) ?? 0,
    inSync: (j['inSyncWithText'] as bool?) ?? true,
  );
}

/// A verse start inside a recitation. vOrder 0 = title, -2 = end of audio.
class SyncPoint {
  const SyncPoint(this.vOrder, this.ms);

  final int vOrder;
  final int ms;

  Map<String, int> toJson() => {'verseOrder': vOrder, 'audioStartMilliseconds': ms};
}

/// `/api/audio/verses/{id}`: already normalised (verseOrder == vOrder, real milliseconds).
List<SyncPoint> parseSyncJson(String body) => [
  for (final e in jsonDecode(body) as List)
    SyncPoint((e as Map<String, dynamic>)['verseOrder'] as int, e['audioStartMilliseconds'] as int),
];

/// Desktop-Ganjoor sync XML: 0-based VerseOrder (-1 title, -2 end) and the
/// OneSecondBugFix divisor (default 2000, per GanjoorService's player).
List<SyncPoint> parseSyncXml(String body) {
  final doc = XmlDocument.parse(body);
  final fixText = doc.findAllElements('OneSecondBugFix').firstOrNull?.innerText.trim();
  final fix = int.tryParse(fixText ?? '') ?? 2000;
  return [
    for (final info in doc.findAllElements('SyncInfo'))
      () {
        final order = int.parse(info.getElement('VerseOrder')!.innerText.trim());
        final raw = int.parse(info.getElement('AudioMiliseconds')!.innerText.trim());
        final vOrder = order >= 0 ? order + 1 : (order == -1 ? 0 : order);
        return SyncPoint(vOrder, (raw * 1000 / fix).round());
      }(),
  ];
}
