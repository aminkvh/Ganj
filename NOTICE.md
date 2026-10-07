# Notices

**گنج (Ganj)** is an independent, unofficial, open-source Persian poetry reader made as a tribute to
[گنجور — Ganjoor](https://ganjoor.net). It is **not affiliated with or endorsed by Ganjoor**.

Copyright © 2026 Amin Akbari. Ganj is free software under the GNU General Public License, version 3 or (at your
option) any later version — see `LICENSE`. It comes with no warranty.

## Content

- Poems, metadata, meanings (couplet summaries), recitations, manuscript images, songs, comments and the book
  catalogue are read from the public Ganjoor API (https://api.ganjoor.net) and Ganjoor's downloadable poet packs
  (https://i.ganjoor.net). They are curated by Ganjoor's founder Hamidreza Mohammadi and its many volunteers; each
  recitation belongs to its reciter, and AI-written meanings are labelled as such, as on the site. Ganj does not
  re-host any of it: everything is fetched from Ganjoor's own servers.
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
