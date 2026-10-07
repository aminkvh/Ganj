// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Persian (`fa`).
class L10nFa extends L10n {
  L10nFa([String locale = 'fa']) : super(locale);

  @override
  String get appName => 'گنج';

  @override
  String get tributeLine => 'به پاس گنجور';

  @override
  String get offline => 'اتصال به گنجور برقرار نشد';

  @override
  String get retry => 'تلاش دوباره';

  @override
  String get cancel => 'انصراف';

  @override
  String get delete => 'حذف';

  @override
  String get save => 'ذخیره';

  @override
  String get close => 'بستن';

  @override
  String get more => 'بیشتر';

  @override
  String get less => 'کمتر';

  @override
  String get moreResults => 'نتایج بیشتر';

  @override
  String get moreResultsFailed => 'نتایج بیشتر دریافت نشد — تلاش دوباره';

  @override
  String get play => 'پخش';

  @override
  String get pause => 'توقف';

  @override
  String get stop => 'توقف';

  @override
  String get download => 'بارگیری';

  @override
  String get copied => 'رونوشت شد';

  @override
  String get notFoundPage => 'این صفحه پیدا نشد';

  @override
  String get backHome => 'بازگشت به خانه';

  @override
  String get poemNotFound => 'این شعر پیدا نشد';

  @override
  String get nothingHere => 'موردی نیست';

  @override
  String get notLoaded => 'دریافت نشد';

  @override
  String get aiBadge => 'هوش مصنوعی';

  @override
  String get invalidLink => 'پیوند نامعتبر است';

  @override
  String get linkFailed => 'باز کردن پیوند ممکن نشد';

  @override
  String get openOnGanjoor => 'مشاهده در گنجور';

  @override
  String beytN(String n) {
    return 'بیت $n';
  }

  @override
  String nOfM(String n, String m) {
    return '$n از $m';
  }

  @override
  String diedYear(String year) {
    return 'د. $year';
  }

  @override
  String get langArabic => 'عربی';

  @override
  String get langTurkish => 'ترکی';

  @override
  String get langKurdish => 'کردی';

  @override
  String get langMazandarani => 'مازندرانی';

  @override
  String get langGilaki => 'گیلکی';

  @override
  String get langIsfahani => 'اصفهانی';

  @override
  String get faalTitle => 'فال حافظ';

  @override
  String get faalInvocation =>
      'ای حافظ شیرازی، تو محرم هر رازی؛\nتو را به خدا و به شاخ نباتت قسم می‌دهم\nکه هر چه صلاح و مصلحت می‌بینی برایم آشکار سازی.';

  @override
  String get faalIntention => 'با نیت قلبی، فال خود را بگشایید.';

  @override
  String get faalOpen => 'گشودن فال';

  @override
  String get searchPoems => 'جستجو در اشعار';

  @override
  String get offlineLibrary => 'کتابخانهٔ آفلاین';

  @override
  String get menu => 'منو';

  @override
  String get randomPoem => 'شعر تصادفی';

  @override
  String get metres => 'وزن‌ها';

  @override
  String get bookmarksAndNotes => 'نشان‌ها و یادداشت‌ها';

  @override
  String get settingsAndAbout => 'تنظیمات و درباره';

  @override
  String get seedRefresh => 'فهرست به‌روز شاعران دریافت نشد — تلاش دوباره';

  @override
  String get searchPoet => 'جستجوی شاعر';

  @override
  String get birthplaceMap => 'نقشهٔ خاستگاه سخنوران';

  @override
  String get bookShelf => 'قفسهٔ کتاب‌ها';

  @override
  String get openPoet => 'آثار';

  @override
  String get translate => 'ترجمه';

  @override
  String get translateBeyt => 'ترجمهٔ بیت';

  @override
  String get machineTranslation => 'ترجمهٔ ماشینی';

  @override
  String get modelTitle => 'بارگیری مدل ترجمه';

  @override
  String modelBody(String size) {
    return 'برای ترجمه روی همین دستگاه، مدل ترجمه (حدود $size برای هر زبان) یک بار بارگیری می‌شود؛ پس از آن بی‌اینترنت هم کار می‌کند.';
  }

  @override
  String get modelDownloading => 'در حال بارگیری مدل ترجمه…';

  @override
  String get modelFailed => 'بارگیری مدل ترجمه ناموفق بود';

  @override
  String get translateFailed => 'ترجمه ممکن نشد';

  @override
  String get openInGoogleTranslate => 'باز کردن در Google Translate';

  @override
  String get translateTo => 'زبان ترجمه';

  @override
  String get removeModel => 'حذف مدل ترجمه از دستگاه';

  @override
  String get modelRemoved => 'مدل ترجمه حذف شد';

  @override
  String get translateInBrowser =>
      'روی رایانه، ترجمه در Google Translate باز می‌شود';

  @override
  String packReady(String name) {
    return '$name برای خواندن آفلاین آماده است';
  }

  @override
  String packFailed(String name) {
    return 'بارگیری $name ناموفق بود';
  }

  @override
  String packRemoveTitle(String name) {
    return 'حذف $name از دستگاه؟';
  }

  @override
  String get packRemoveBody =>
      'برای خواندن آفلاین دوباره باید بارگیری شود. نشان‌ها و یادداشت‌ها می‌مانند.';

  @override
  String packRemoveFailed(String name) {
    return 'حذف $name ممکن نشد';
  }

  @override
  String listingRecitations(String name) {
    return 'در حال فهرست‌کردن خوانش‌های $name…';
  }

  @override
  String recitationsOf(String name) {
    return 'خوانش‌های $name';
  }

  @override
  String recitationPlan(String count, String size) {
    return '$count خوانش، حدود $size. بارگیری یکی‌یکی انجام می‌شود.';
  }

  @override
  String jobProgress(String name, String done, String total) {
    return '$name: $done از $total';
  }

  @override
  String get downloadStopped => 'بارگیری متوقف شد';

  @override
  String recitationsDownloaded(String name) {
    return 'خوانش‌های $name بارگیری شد';
  }

  @override
  String get recitationsFailed => 'بارگیری خوانش‌ها ناموفق بود';

  @override
  String get poetsTab => 'شاعران';

  @override
  String get recitationsTab => 'خوانش‌ها';

  @override
  String installedSummary(String count, String size) {
    return '$count شاعر روی دستگاه ($size فشرده)';
  }

  @override
  String get onDevice => 'روی دستگاه';

  @override
  String get updateAvailable => 'نسخهٔ تازه موجود است';

  @override
  String get update => 'به‌روزرسانی';

  @override
  String get downloadAllRecitations => 'بارگیری همهٔ خوانش‌ها';

  @override
  String get removeFromDevice => 'حذف از دستگاه';

  @override
  String get downloadForReading => 'بارگیری برای خواندن آفلاین';

  @override
  String get noRecitationsYet => 'هنوز خوانشی بارگیری نشده است';

  @override
  String recitationsSummary(String count, String size) {
    return '$count خوانش، $size';
  }

  @override
  String get searchMetre => 'جستجوی وزن (مثلاً مفاعیلن)';

  @override
  String hemistichCount(String count) {
    return '$count مصرع';
  }

  @override
  String get sameMetre => 'هم‌وزن‌ها';

  @override
  String get sameMetreRhyme => 'هم‌وزن و هم‌قافیه';

  @override
  String rhymeIs(String rhyme) {
    return 'قافیه: $rhyme';
  }

  @override
  String poemCount(String count) {
    return '$count شعر';
  }

  @override
  String get downloadFailed => 'بارگیری ناموفق بود';

  @override
  String get downloadForListening => 'بارگیری برای شنیدن آفلاین';

  @override
  String get playFailed => 'پخش ممکن نشد';

  @override
  String get speed => 'سرعت';

  @override
  String get notInSync => 'بدون همگامی با متن';

  @override
  String recitationsCount(String count) {
    return 'خوانش‌ها ($count)';
  }

  @override
  String get autoScrollOff => 'پیمایش خودکار خاموش';

  @override
  String get autoScrollOn => 'پیمایش خودکار روشن';

  @override
  String get note => 'یادداشت';

  @override
  String get noteHint => 'یادداشت شما برای این بیت';

  @override
  String get lineNotRead => 'در این خوانش این خط خوانده نشده است';

  @override
  String get bookmark => 'نشان‌گذاری';

  @override
  String get findInPoem => 'جستجو در شعر';

  @override
  String get meanings => 'معنی ابیات';

  @override
  String get zoomIn => 'بزرگ‌نمایی';

  @override
  String get zoomOut => 'کوچک‌نمایی';

  @override
  String get switchTheme => 'تغییر پوسته';

  @override
  String get copyPoem => 'رونوشت شعر';

  @override
  String get share => 'هم‌رسانی';

  @override
  String get findInThisPoem => 'جستجو در این شعر';

  @override
  String get metre => 'وزن';

  @override
  String get rhyme => 'قافیه';

  @override
  String get summary => 'چکیده';

  @override
  String get playFromBeyt => 'پخش از این بیت';

  @override
  String get unbookmarkBeyt => 'حذف نشان بیت';

  @override
  String get bookmarkBeyt => 'نشان‌گذاری بیت';

  @override
  String get copyBeyt => 'رونوشت بیت';

  @override
  String get shareBeyt => 'هم‌رسانی بیت';

  @override
  String meaningPrefix(String text) {
    return 'معنی: $text';
  }

  @override
  String get bookmarked => 'نشان‌دار';

  @override
  String get hasNote => 'یادداشت دارد';

  @override
  String get beytOptions => 'گزینه‌های بیت';

  @override
  String get relatedPanel => 'اشعار هم‌وزن و هم‌قافیه';

  @override
  String get quotedPanel => 'نقل‌قول‌ها و استقبال‌ها';

  @override
  String get imagesPanel => 'تصاویر نسخه‌های خطی';

  @override
  String get songsPanel => 'آهنگ‌ها';

  @override
  String get commentsPanel => 'حاشیه‌ها';

  @override
  String get search => 'جستجو';

  @override
  String get poetLabel => 'شاعر: ';

  @override
  String get allPoets => 'همهٔ شاعران';

  @override
  String get offlineResults => 'نتایج آفلاین — فقط از مجموعه‌های بارگیری‌شده';

  @override
  String get nothingFound => 'چیزی یافت نشد';

  @override
  String resultCount(String count) {
    return '$count نتیجه';
  }

  @override
  String get clearFailed => 'پاک‌کردن ممکن نشد';

  @override
  String get cacheCleared => 'حافظهٔ موقت پاک شد';

  @override
  String get display => 'نمایش';

  @override
  String get themeSystem => 'خودکار';

  @override
  String get themeLight => 'روشن';

  @override
  String get themeDark => 'تیره';

  @override
  String get language => 'زبان برنامه';

  @override
  String get verseTextSize => 'اندازهٔ متن شعر';

  @override
  String get showMeaningsDefault => 'نمایش معنی ابیات به‌طور پیش‌فرض';

  @override
  String get useIranNastaliq => 'استفاده از قلم ایران‌نستعلیق (اگر نصب است)';

  @override
  String get iranNastaliqNote => 'در غیر این صورت نستعلیق نوتو به کار می‌رود';

  @override
  String get storage => 'حافظه';

  @override
  String get cacheSize => 'حافظهٔ موقت صفحه‌های خوانده‌شده';

  @override
  String get clearCache => 'پاک‌کردن حافظهٔ موقت';

  @override
  String get clearCacheNote =>
      'مجموعه‌های بارگیری‌شده، خوانش‌ها و نشان‌ها دست نمی‌خورند';

  @override
  String get about => 'درباره';

  @override
  String get aboutText =>
      'گنج نرم‌افزاری آزاد و رایگان برای خواندن و شنیدن شعر پارسی است و به پاس «گنجور» ساخته شده است. شعرها، خوانش‌ها، معنی ابیات و تصاویر از گنجور (ganjoor.net) و به همت بنیان‌گذار آن، حمیدرضا محمدی، و صدها داوطلب فراهم آمده است؛ خوانش‌ها از آنِ خوانندگانشان است. گنج وابسته به گنجور نیست.';

  @override
  String get madeBy => 'طراحی و ساخت: امین اکبری';

  @override
  String get ganjoor => 'گنجور';

  @override
  String get sourceCode => 'کد منبع (GPL-3.0)';

  @override
  String get licenses => 'پروانه‌ها';

  @override
  String versionN(String version) {
    return 'نسخهٔ $version';
  }

  @override
  String get backupCopied => 'پشتیبان در حافظهٔ موقت رونوشت شد';

  @override
  String get backupSubject => 'پشتیبان گنج';

  @override
  String get importBackup => 'ورود از پشتیبان';

  @override
  String get pasteBackup => 'متن پشتیبان را اینجا بچسبانید';

  @override
  String get importAction => 'ورود';

  @override
  String itemsImported(String count) {
    return '$count مورد وارد شد';
  }

  @override
  String get backupInvalid => 'متن پشتیبان معتبر نیست';

  @override
  String get exportBackup => 'پشتیبان‌گیری';

  @override
  String get bookmarksTab => 'نشان‌ها';

  @override
  String get historyTab => 'تاریخچه';

  @override
  String get notesTab => 'یادداشت‌ها';

  @override
  String get userDataFailed => 'خواندن داده‌ها ممکن نشد';

  @override
  String get noBookmarks => 'هنوز نشانی نگذاشته‌اید';

  @override
  String get noHistory => 'هنوز شعری نخوانده‌اید';

  @override
  String get noNotes => 'هنوز یادداشتی ننوشته‌اید';
}
