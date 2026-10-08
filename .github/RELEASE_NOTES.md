<div dir="rtl">

**گنج** — خواننده‌ای آزاد، رایگان و غیررسمی برای شعر پارسی، به پاس **[گنجور](https://ganjoor.net)**: خواندن و شنیدن شعر روی گوشی و رایانه، حتی بی‌اینترنت.

</div>

**Ganj** — a free, open-source, *unofficial* reader for Persian poetry, made in tribute to **[Ganjoor](https://ganjoor.net)**: read and listen on your phone or computer, even offline.

### New in 1.1.4

- Windows: Ganj draws on the integrated graphics chip by default and registers itself as "Power saving" in Windows' graphics settings — fixes the empty white window on dual-GPU (Optimus) laptops with older drivers; `--gpu=high` overrides

### New in 1.1.3

- Translation now uses Ganjoor's plain-Persian meaning of each beyt when there is one (much better results than translating the verse itself)
- Windows: start-up diagnostics — `Ganj-diagnose.cmd` collects a report for computers that show an empty window; `--gpu=low|high` picks the graphics chip on dual-GPU laptops

### New in 1.1.2

- Android: translation works again in release builds (the code shrinker had been stripping ML Kit); if on-device translation ever fails, it continues online, then offers Google Translate
- Text selection menu keeps only Copy and Select all

### New in 1.1.1

- Windows: no more white window on older or budget computers; Windows N and Linux without libmpv explain how to enable audio
- Android: translation fixed (offers Google Translate when the model can't be downloaded); neater poem menu and toolbar
- Smaller: unused libraries removed

### New in 1.1

- Search by meaning · جستجو با معنا — one search box for poets, books and poems · جستجوی یکپارچه
- Tajik (Cyrillic) script under the verses · خط تاجیکی (سیریلیک)
- Download a poet from their own page; home button everywhere; pictures kept for offline use

### Download

| Platform | File | Notes |
|---|---|---|
| Android | `Ganj-*-android.apk` | Works on every phone. Smaller per-device builds: `-arm64` (most phones), `-arm32`, `-x86_64`. Allow "install unknown apps" when asked. |
| Windows 10/11 (64-bit) | `Ganj-*-windows-x64.zip` | Unzip and run `Ganj\ganj.exe` (keep the whole folder). |
| macOS | `Ganj-*-macos.zip` | Not signed by Apple: right-click `ganj.app` → **Open** the first time. |
| Linux (x64) | `Ganj-*-linux-x64.tar.gz` | Extract and run `Ganj/ganj`. Needs `libmpv` for audio (`sudo apt install libmpv2` or `libmpv1`). |
| iOS / iPadOS 15.5+ | `Ganj-*-ios-unsigned.ipa` | Unsigned: install with a sideloading tool (AltStore, Sideloadly) that signs it with your Apple ID. |

`SHA256SUMS.txt` lists checksums for every file.

Ganj is **not affiliated with Ganjoor**. Poems, recitations, meanings and images come from Ganjoor and its contributors; the app is GPL-3.0-or-later. See the README for details and credits.
