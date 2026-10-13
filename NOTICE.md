# Notices

**گنج (Ganj)** is an independent, unofficial, open-source Persian poetry reader made as a tribute to
[گنجور — Ganjoor](https://ganjoor.net). It is **not affiliated with or endorsed by Ganjoor**.

Copyright © 2026 Amin Akbari. Ganj is free software under the GNU General Public License, version 3 or (at your
option) any later version — see `LICENSE`. It comes with no warranty.

## Content

- Poems, metadata, meanings (couplet summaries), recitations, manuscript images, songs, comments and the book
  catalogue are read from the public Ganjoor API (https://api.ganjoor.net) and Ganjoor's downloadable poet packs
  (https://i.ganjoor.net). They are curated by Ganjoor's founder Hamidreza Mohammadi and its many volunteers; each
  recitation belongs to its reciter, and AI-written meanings are labelled as such, as on the site. Poems and
  recitations are always fetched from Ganjoor's own servers.
- «جهان شاهنامه» (World of the Shahnameh): the people of the Shahnameh, their family ties and other ties, and the
  people and place tags of its couplets come from Ganjoor's «نامبردگان» data (much of it AI-suggested and reviewed
  by Ganjoor's volunteers). A compact snapshot of it — names, short descriptions, ties, story sections, poem titles
  and the first sentence of each poem summary — ships with the app (`assets/seed/shahnameh/generated.json`, built
  by `tool/shahnameh_snapshot.dart`) so the section works offline; evidence couplets and tagged poems are fetched
  live. The ages, reigns and stories of the timeline, the places of the map with their coordinates and notes, the
  journeys, and the English names (`ages.json`, `places.json`, `names_en.json`) were written by AI for Ganj;
  until reviewed they carry the label «هوش مصنوعی · گنج» in the app, and Ganjoor's own AI-suggested data carries
  the app's usual AI label. Place locations are traditional or approximate where the epic's geography is
  legendary. Readers can report a mistake from any person, story or place («گزارش خطا»).
- The look of the app follows ganjoor.net, whose code ([GanjoorService](https://github.com/ganjoor/GanjoorService))
  is GPL-3.0. The map icon (`assets/images/map.gif`) and the bookshelf design come from ganjoor.net.
- English poet names (`assets/seed/poet_names_en.json`) were compiled for Ganj.
- The app icon was made for this project.

## Third-party software and services

- Fonts: Vazirmatn and Noto Nastaliq Urdu, SIL Open Font License 1.1 (texts in `assets/fonts/`).
- Map: tiles and data © [OpenStreetMap](https://www.openstreetmap.org/copyright) contributors (ODbL), drawn with
  `flutter_map`.
- Machine translation: on Android and iOS, Google ML Kit on-device translation (Google's ML Kit terms apply); on
  Windows, macOS and Linux, Google Translate's free web service, used unofficially and best-effort. Translations
  are machine-made and labelled as such.
- Open-source Flutter packages, each under its own license; the full list is in the app under
  Settings → Licenses.
