// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class L10nEn extends L10n {
  L10nEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Ganj';

  @override
  String get tributeLine => 'In tribute to Ganjoor';

  @override
  String get offline => 'Couldn\'t reach Ganjoor';

  @override
  String get retry => 'Try again';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get save => 'Save';

  @override
  String get close => 'Close';

  @override
  String get more => 'More';

  @override
  String get less => 'Less';

  @override
  String get moreResults => 'More results';

  @override
  String get moreResultsFailed => 'Couldn\'t load more — try again';

  @override
  String get play => 'Play';

  @override
  String get pause => 'Pause';

  @override
  String get stop => 'Stop';

  @override
  String get download => 'Download';

  @override
  String get copied => 'Copied';

  @override
  String get notFoundPage => 'Page not found';

  @override
  String get backHome => 'Back to home';

  @override
  String get poemNotFound => 'Poem not found';

  @override
  String get nothingHere => 'Nothing here';

  @override
  String get notLoaded => 'Couldn\'t load';

  @override
  String get aiBadge => 'AI';

  @override
  String get invalidLink => 'Invalid link';

  @override
  String get linkFailed => 'Couldn\'t open the link';

  @override
  String get openOnGanjoor => 'Open on ganjoor.net';

  @override
  String beytN(String n) {
    return 'Couplet $n';
  }

  @override
  String nOfM(String n, String m) {
    return '$n of $m';
  }

  @override
  String diedYear(String year) {
    return 'd. $year AH';
  }

  @override
  String get langArabic => 'Arabic';

  @override
  String get langTurkish => 'Turkish';

  @override
  String get langKurdish => 'Kurdish';

  @override
  String get langMazandarani => 'Mazandarani';

  @override
  String get langGilaki => 'Gilaki';

  @override
  String get langIsfahani => 'Isfahani';

  @override
  String get faalTitle => 'Divination of Hafez';

  @override
  String get faalInvocation =>
      'O Hafez of Shiraz, keeper of every secret,\nI ask you by God and by your Shakh-e Nabat\nto reveal to me whatever is right and good for me.';

  @override
  String get faalIntention =>
      'Hold your wish in your heart, then open your fortune.';

  @override
  String get faalOpen => 'Open the fortune';

  @override
  String get searchPoems => 'Search poems';

  @override
  String get offlineLibrary => 'Offline library';

  @override
  String get menu => 'Menu';

  @override
  String get randomPoem => 'Random poem';

  @override
  String get metres => 'Metres';

  @override
  String get bookmarksAndNotes => 'Bookmarks & notes';

  @override
  String get settingsAndAbout => 'Settings & about';

  @override
  String get seedRefresh => 'Couldn\'t get the latest poet list — try again';

  @override
  String get searchPoet => 'Find a poet';

  @override
  String get birthplaceMap => 'Map of poets\' birthplaces';

  @override
  String get bookShelf => 'Bookshelf';

  @override
  String get openPoet => 'Works';

  @override
  String get translate => 'Translate';

  @override
  String get translateBeyt => 'Translate couplet';

  @override
  String get machineTranslation => 'Machine translation';

  @override
  String get modelTitle => 'Download translation model';

  @override
  String modelBody(String size) {
    return 'To translate on this device, a translation model (about $size per language) is downloaded once; after that it works offline too.';
  }

  @override
  String get modelDownloading => 'Downloading the translation model…';

  @override
  String get modelFailed => 'Downloading the translation model failed';

  @override
  String get translateFailed => 'Couldn\'t translate';

  @override
  String get openInGoogleTranslate => 'Open in Google Translate';

  @override
  String get translateTo => 'Translation language';

  @override
  String get removeModel => 'Remove translation model from this device';

  @override
  String get modelRemoved => 'Translation model removed';

  @override
  String get translateInBrowser =>
      'On computers, translations open in Google Translate';

  @override
  String packReady(String name) {
    return '$name is ready to read offline';
  }

  @override
  String packFailed(String name) {
    return 'Downloading $name failed';
  }

  @override
  String packRemoveTitle(String name) {
    return 'Remove $name from this device?';
  }

  @override
  String get packRemoveBody =>
      'You\'ll need to download it again to read offline. Bookmarks and notes are kept.';

  @override
  String packRemoveFailed(String name) {
    return 'Couldn\'t remove $name';
  }

  @override
  String listingRecitations(String name) {
    return 'Listing recitations of $name…';
  }

  @override
  String recitationsOf(String name) {
    return 'Recitations of $name';
  }

  @override
  String recitationPlan(String count, String size) {
    return '$count recitations, about $size. They download one at a time.';
  }

  @override
  String jobProgress(String name, String done, String total) {
    return '$name: $done of $total';
  }

  @override
  String get downloadStopped => 'Download stopped';

  @override
  String recitationsDownloaded(String name) {
    return 'Recitations of $name downloaded';
  }

  @override
  String get recitationsFailed => 'Downloading recitations failed';

  @override
  String get poetsTab => 'Poets';

  @override
  String get recitationsTab => 'Recitations';

  @override
  String installedSummary(String count, String size) {
    return '$count poets on this device ($size compressed)';
  }

  @override
  String get onDevice => 'On device';

  @override
  String get updateAvailable => 'Update available';

  @override
  String get update => 'Update';

  @override
  String get downloadAllRecitations => 'Download all recitations';

  @override
  String get removeFromDevice => 'Remove from device';

  @override
  String get downloadForReading => 'Download to read offline';

  @override
  String get noRecitationsYet => 'No recitations downloaded yet';

  @override
  String recitationsSummary(String count, String size) {
    return '$count recitations, $size';
  }

  @override
  String get searchMetre => 'Find a metre (e.g. مفاعیلن)';

  @override
  String hemistichCount(String count) {
    return '$count hemistichs';
  }

  @override
  String get sameMetre => 'Same metre';

  @override
  String get sameMetreRhyme => 'Same metre and rhyme';

  @override
  String rhymeIs(String rhyme) {
    return 'Rhyme: $rhyme';
  }

  @override
  String poemCount(String count) {
    return '$count poems';
  }

  @override
  String get downloadFailed => 'Download failed';

  @override
  String get downloadForListening => 'Download to listen offline';

  @override
  String get playFailed => 'Couldn\'t play';

  @override
  String get speed => 'Speed';

  @override
  String get notInSync => 'not synced to the text';

  @override
  String recitationsCount(String count) {
    return 'Recitations ($count)';
  }

  @override
  String get autoScrollOff => 'Auto-scroll off';

  @override
  String get autoScrollOn => 'Auto-scroll on';

  @override
  String get note => 'Note';

  @override
  String get noteHint => 'Your note on this couplet';

  @override
  String get lineNotRead => 'This line isn\'t read in this recitation';

  @override
  String get bookmark => 'Bookmark';

  @override
  String get findInPoem => 'Find in poem';

  @override
  String get meanings => 'Meanings';

  @override
  String get zoomIn => 'Zoom in';

  @override
  String get zoomOut => 'Zoom out';

  @override
  String get switchTheme => 'Switch theme';

  @override
  String get copyPoem => 'Copy poem';

  @override
  String get share => 'Share';

  @override
  String get findInThisPoem => 'Find in this poem';

  @override
  String get metre => 'Metre';

  @override
  String get rhyme => 'Rhyme';

  @override
  String get summary => 'Summary';

  @override
  String get playFromBeyt => 'Play from this couplet';

  @override
  String get unbookmarkBeyt => 'Remove couplet bookmark';

  @override
  String get bookmarkBeyt => 'Bookmark couplet';

  @override
  String get copyBeyt => 'Copy couplet';

  @override
  String get shareBeyt => 'Share couplet';

  @override
  String meaningPrefix(String text) {
    return 'Meaning: $text';
  }

  @override
  String get bookmarked => 'Bookmarked';

  @override
  String get hasNote => 'Has a note';

  @override
  String get beytOptions => 'Couplet options';

  @override
  String get relatedPanel => 'Poems in the same metre and rhyme';

  @override
  String get quotedPanel => 'Quotations and replies';

  @override
  String get imagesPanel => 'Manuscript images';

  @override
  String get songsPanel => 'Songs';

  @override
  String get commentsPanel => 'Comments';

  @override
  String get search => 'Search';

  @override
  String get poetLabel => 'Poet: ';

  @override
  String get allPoets => 'All poets';

  @override
  String get offlineResults =>
      'Offline results — only from downloaded collections';

  @override
  String get nothingFound => 'Nothing found';

  @override
  String resultCount(String count) {
    return '$count results';
  }

  @override
  String get clearFailed => 'Couldn\'t clear';

  @override
  String get cacheCleared => 'Cache cleared';

  @override
  String get display => 'Display';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get language => 'App language';

  @override
  String get verseTextSize => 'Poem text size';

  @override
  String get showMeaningsDefault => 'Show couplet meanings by default';

  @override
  String get useIranNastaliq => 'Use the IranNastaliq font (if installed)';

  @override
  String get iranNastaliqNote => 'Otherwise Noto Nastaliq is used';

  @override
  String get storage => 'Storage';

  @override
  String get cacheSize => 'Cache of pages you\'ve read';

  @override
  String get clearCache => 'Clear cache';

  @override
  String get clearCacheNote =>
      'Downloaded collections, recitations and bookmarks are kept';

  @override
  String get about => 'About';

  @override
  String get aboutText =>
      'Ganj is a free, open-source app for reading and listening to Persian poetry, made in tribute to Ganjoor. The poems, recitations, couplet meanings and images come from Ganjoor (ganjoor.net), the work of its founder Hamidreza Mohammadi and hundreds of volunteers; each recitation belongs to its reciter. Ganj is not affiliated with Ganjoor.';

  @override
  String get madeBy => 'Designed and built by Amin Akbari';

  @override
  String get ganjoor => 'Ganjoor';

  @override
  String get sourceCode => 'Source code (GPL-3.0)';

  @override
  String get licenses => 'Licenses';

  @override
  String versionN(String version) {
    return 'Version $version';
  }

  @override
  String get backupCopied => 'Backup copied to the clipboard';

  @override
  String get backupSubject => 'Ganj backup';

  @override
  String get importBackup => 'Restore from backup';

  @override
  String get pasteBackup => 'Paste the backup text here';

  @override
  String get importAction => 'Restore';

  @override
  String itemsImported(String count) {
    return '$count items restored';
  }

  @override
  String get backupInvalid => 'That backup text isn\'t valid';

  @override
  String get exportBackup => 'Back up';

  @override
  String get bookmarksTab => 'Bookmarks';

  @override
  String get historyTab => 'History';

  @override
  String get notesTab => 'Notes';

  @override
  String get userDataFailed => 'Couldn\'t read your data';

  @override
  String get noBookmarks => 'No bookmarks yet';

  @override
  String get noHistory => 'You haven\'t read any poems yet';

  @override
  String get noNotes => 'No notes yet';
}
