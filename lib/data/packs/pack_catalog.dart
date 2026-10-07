import 'package:xml/xml.dart';

const kPackCatalogUrl = 'https://i.ganjoor.net/android/androidgdbs.xml';

/// One downloadable per-poet SQLite pack from Ganjoor's official list.
class PackInfo {
  const PackInfo({
    required this.poetId,
    required this.catId,
    required this.name,
    required this.url,
    required this.imageUrl,
    required this.size,
    required this.pubDate,
  });

  final int poetId;
  final int catId;
  final String name;
  final String url;
  final String imageUrl;
  final int size;
  final String pubDate;
}

List<PackInfo> parsePackCatalog(String xml) {
  String t(XmlElement e, String name) => e.getElement(name)?.innerText.trim() ?? '';
  return [
    for (final g in XmlDocument.parse(xml).findAllElements('gdb'))
      PackInfo(
        poetId: int.tryParse(t(g, 'PoetID')) ?? 0,
        catId: int.tryParse(t(g, 'CatID')) ?? 0,
        name: t(g, 'CatName'),
        url: t(g, 'DownloadUrl'),
        imageUrl: t(g, 'ImageUrl'),
        size: int.tryParse(t(g, 'FileSizeInByte')) ?? 0,
        pubDate: t(g, 'PubDate'),
      ),
  ]..removeWhere((p) => p.poetId == 0 || p.url.isEmpty);
}
