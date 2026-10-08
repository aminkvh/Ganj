import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fa.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of L10n
/// returned by `L10n.of(context)`.
///
/// Applications need to include `L10n.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: L10n.localizationsDelegates,
///   supportedLocales: L10n.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the L10n.supportedLocales
/// property.
abstract class L10n {
  L10n(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static L10n of(BuildContext context) {
    return Localizations.of<L10n>(context, L10n)!;
  }

  static const LocalizationsDelegate<L10n> delegate = _L10nDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en'), Locale('fa')];

  /// No description provided for @appName.
  ///
  /// In fa, this message translates to:
  /// **'گنج'**
  String get appName;

  /// No description provided for @tributeLine.
  ///
  /// In fa, this message translates to:
  /// **'به پاس گنجور'**
  String get tributeLine;

  /// No description provided for @offline.
  ///
  /// In fa, this message translates to:
  /// **'اتصال به گنجور برقرار نشد'**
  String get offline;

  /// No description provided for @retry.
  ///
  /// In fa, this message translates to:
  /// **'تلاش دوباره'**
  String get retry;

  /// No description provided for @cancel.
  ///
  /// In fa, this message translates to:
  /// **'انصراف'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In fa, this message translates to:
  /// **'حذف'**
  String get delete;

  /// No description provided for @save.
  ///
  /// In fa, this message translates to:
  /// **'ذخیره'**
  String get save;

  /// No description provided for @close.
  ///
  /// In fa, this message translates to:
  /// **'بستن'**
  String get close;

  /// No description provided for @more.
  ///
  /// In fa, this message translates to:
  /// **'بیشتر'**
  String get more;

  /// No description provided for @less.
  ///
  /// In fa, this message translates to:
  /// **'کمتر'**
  String get less;

  /// No description provided for @moreResults.
  ///
  /// In fa, this message translates to:
  /// **'نتایج بیشتر'**
  String get moreResults;

  /// No description provided for @moreResultsFailed.
  ///
  /// In fa, this message translates to:
  /// **'نتایج بیشتر دریافت نشد — تلاش دوباره'**
  String get moreResultsFailed;

  /// No description provided for @play.
  ///
  /// In fa, this message translates to:
  /// **'پخش'**
  String get play;

  /// No description provided for @pause.
  ///
  /// In fa, this message translates to:
  /// **'توقف'**
  String get pause;

  /// No description provided for @stop.
  ///
  /// In fa, this message translates to:
  /// **'توقف'**
  String get stop;

  /// No description provided for @download.
  ///
  /// In fa, this message translates to:
  /// **'بارگیری'**
  String get download;

  /// No description provided for @copied.
  ///
  /// In fa, this message translates to:
  /// **'رونوشت شد'**
  String get copied;

  /// No description provided for @notFoundPage.
  ///
  /// In fa, this message translates to:
  /// **'این صفحه پیدا نشد'**
  String get notFoundPage;

  /// No description provided for @backHome.
  ///
  /// In fa, this message translates to:
  /// **'بازگشت به خانه'**
  String get backHome;

  /// No description provided for @poemNotFound.
  ///
  /// In fa, this message translates to:
  /// **'این شعر پیدا نشد'**
  String get poemNotFound;

  /// No description provided for @nothingHere.
  ///
  /// In fa, this message translates to:
  /// **'موردی نیست'**
  String get nothingHere;

  /// No description provided for @notLoaded.
  ///
  /// In fa, this message translates to:
  /// **'دریافت نشد'**
  String get notLoaded;

  /// No description provided for @aiBadge.
  ///
  /// In fa, this message translates to:
  /// **'هوش مصنوعی'**
  String get aiBadge;

  /// No description provided for @invalidLink.
  ///
  /// In fa, this message translates to:
  /// **'پیوند نامعتبر است'**
  String get invalidLink;

  /// No description provided for @linkFailed.
  ///
  /// In fa, this message translates to:
  /// **'باز کردن پیوند ممکن نشد'**
  String get linkFailed;

  /// No description provided for @openOnGanjoor.
  ///
  /// In fa, this message translates to:
  /// **'مشاهده در گنجور'**
  String get openOnGanjoor;

  /// No description provided for @beytN.
  ///
  /// In fa, this message translates to:
  /// **'بیت {n}'**
  String beytN(String n);

  /// No description provided for @nOfM.
  ///
  /// In fa, this message translates to:
  /// **'{n} از {m}'**
  String nOfM(String n, String m);

  /// No description provided for @diedYear.
  ///
  /// In fa, this message translates to:
  /// **'د. {year}'**
  String diedYear(String year);

  /// No description provided for @langArabic.
  ///
  /// In fa, this message translates to:
  /// **'عربی'**
  String get langArabic;

  /// No description provided for @langTurkish.
  ///
  /// In fa, this message translates to:
  /// **'ترکی'**
  String get langTurkish;

  /// No description provided for @langKurdish.
  ///
  /// In fa, this message translates to:
  /// **'کردی'**
  String get langKurdish;

  /// No description provided for @langMazandarani.
  ///
  /// In fa, this message translates to:
  /// **'مازندرانی'**
  String get langMazandarani;

  /// No description provided for @langGilaki.
  ///
  /// In fa, this message translates to:
  /// **'گیلکی'**
  String get langGilaki;

  /// No description provided for @langIsfahani.
  ///
  /// In fa, this message translates to:
  /// **'اصفهانی'**
  String get langIsfahani;

  /// No description provided for @faalTitle.
  ///
  /// In fa, this message translates to:
  /// **'فال حافظ'**
  String get faalTitle;

  /// No description provided for @faalInvocation.
  ///
  /// In fa, this message translates to:
  /// **'ای حافظ شیرازی، تو محرم هر رازی؛\nتو را به خدا و به شاخ نباتت قسم می‌دهم\nکه هر چه صلاح و مصلحت می‌بینی برایم آشکار سازی.'**
  String get faalInvocation;

  /// No description provided for @faalIntention.
  ///
  /// In fa, this message translates to:
  /// **'با نیت قلبی، فال خود را بگشایید.'**
  String get faalIntention;

  /// No description provided for @faalOpen.
  ///
  /// In fa, this message translates to:
  /// **'گشودن فال'**
  String get faalOpen;

  /// No description provided for @searchPoems.
  ///
  /// In fa, this message translates to:
  /// **'جستجو در اشعار'**
  String get searchPoems;

  /// No description provided for @offlineLibrary.
  ///
  /// In fa, this message translates to:
  /// **'کتابخانهٔ آفلاین'**
  String get offlineLibrary;

  /// No description provided for @menu.
  ///
  /// In fa, this message translates to:
  /// **'منو'**
  String get menu;

  /// No description provided for @randomPoem.
  ///
  /// In fa, this message translates to:
  /// **'شعر تصادفی'**
  String get randomPoem;

  /// No description provided for @metres.
  ///
  /// In fa, this message translates to:
  /// **'وزن‌ها'**
  String get metres;

  /// No description provided for @bookmarksAndNotes.
  ///
  /// In fa, this message translates to:
  /// **'نشان‌ها و یادداشت‌ها'**
  String get bookmarksAndNotes;

  /// No description provided for @settingsAndAbout.
  ///
  /// In fa, this message translates to:
  /// **'تنظیمات و درباره'**
  String get settingsAndAbout;

  /// No description provided for @seedRefresh.
  ///
  /// In fa, this message translates to:
  /// **'فهرست به‌روز شاعران دریافت نشد — تلاش دوباره'**
  String get seedRefresh;

  /// No description provided for @searchPoet.
  ///
  /// In fa, this message translates to:
  /// **'جستجوی شاعر'**
  String get searchPoet;

  /// No description provided for @homeSearchHint.
  ///
  /// In fa, this message translates to:
  /// **'جستجوی سخنور، کتاب یا شعر'**
  String get homeSearchHint;

  /// No description provided for @birthplaceMap.
  ///
  /// In fa, this message translates to:
  /// **'نقشهٔ خاستگاه سخنوران'**
  String get birthplaceMap;

  /// No description provided for @bookShelf.
  ///
  /// In fa, this message translates to:
  /// **'قفسهٔ کتاب‌ها'**
  String get bookShelf;

  /// No description provided for @openPoet.
  ///
  /// In fa, this message translates to:
  /// **'آثار'**
  String get openPoet;

  /// No description provided for @translate.
  ///
  /// In fa, this message translates to:
  /// **'ترجمه'**
  String get translate;

  /// No description provided for @translateBeyt.
  ///
  /// In fa, this message translates to:
  /// **'ترجمهٔ بیت'**
  String get translateBeyt;

  /// No description provided for @machineTranslation.
  ///
  /// In fa, this message translates to:
  /// **'ترجمهٔ ماشینی'**
  String get machineTranslation;

  /// No description provided for @machineTranslationOfMeaning.
  ///
  /// In fa, this message translates to:
  /// **'ترجمهٔ ماشینیِ معنی بیت'**
  String get machineTranslationOfMeaning;

  /// No description provided for @modelTitle.
  ///
  /// In fa, this message translates to:
  /// **'بارگیری مدل ترجمه'**
  String get modelTitle;

  /// No description provided for @modelBody.
  ///
  /// In fa, this message translates to:
  /// **'برای ترجمه روی همین دستگاه، مدل ترجمه (حدود {size} برای هر زبان) یک بار بارگیری می‌شود؛ پس از آن بی‌اینترنت هم کار می‌کند.'**
  String modelBody(String size);

  /// No description provided for @modelDownloading.
  ///
  /// In fa, this message translates to:
  /// **'در حال بارگیری مدل ترجمه…'**
  String get modelDownloading;

  /// No description provided for @modelFailed.
  ///
  /// In fa, this message translates to:
  /// **'بارگیری مدل ترجمه ناموفق بود'**
  String get modelFailed;

  /// No description provided for @translateFailed.
  ///
  /// In fa, this message translates to:
  /// **'ترجمه ممکن نشد'**
  String get translateFailed;

  /// No description provided for @openInGoogleTranslate.
  ///
  /// In fa, this message translates to:
  /// **'باز کردن در Google Translate'**
  String get openInGoogleTranslate;

  /// No description provided for @translateTo.
  ///
  /// In fa, this message translates to:
  /// **'زبان ترجمه'**
  String get translateTo;

  /// No description provided for @removeModel.
  ///
  /// In fa, this message translates to:
  /// **'حذف مدل ترجمه از دستگاه'**
  String get removeModel;

  /// No description provided for @modelRemoved.
  ///
  /// In fa, this message translates to:
  /// **'مدل ترجمه حذف شد'**
  String get modelRemoved;

  /// No description provided for @translateInBrowser.
  ///
  /// In fa, this message translates to:
  /// **'روی رایانه، ترجمه در Google Translate باز می‌شود'**
  String get translateInBrowser;

  /// No description provided for @packReady.
  ///
  /// In fa, this message translates to:
  /// **'{name} برای خواندن آفلاین آماده است'**
  String packReady(String name);

  /// No description provided for @packFailed.
  ///
  /// In fa, this message translates to:
  /// **'بارگیری {name} ناموفق بود'**
  String packFailed(String name);

  /// No description provided for @packRemoveTitle.
  ///
  /// In fa, this message translates to:
  /// **'حذف {name} از دستگاه؟'**
  String packRemoveTitle(String name);

  /// No description provided for @packRemoveBody.
  ///
  /// In fa, this message translates to:
  /// **'برای خواندن آفلاین دوباره باید بارگیری شود. نشان‌ها و یادداشت‌ها می‌مانند.'**
  String get packRemoveBody;

  /// No description provided for @packRemoveFailed.
  ///
  /// In fa, this message translates to:
  /// **'حذف {name} ممکن نشد'**
  String packRemoveFailed(String name);

  /// No description provided for @listingRecitations.
  ///
  /// In fa, this message translates to:
  /// **'در حال فهرست‌کردن خوانش‌های {name}…'**
  String listingRecitations(String name);

  /// No description provided for @recitationsOf.
  ///
  /// In fa, this message translates to:
  /// **'خوانش‌های {name}'**
  String recitationsOf(String name);

  /// No description provided for @recitationPlan.
  ///
  /// In fa, this message translates to:
  /// **'{count} خوانش، حدود {size}. بارگیری یکی‌یکی انجام می‌شود.'**
  String recitationPlan(String count, String size);

  /// No description provided for @jobProgress.
  ///
  /// In fa, this message translates to:
  /// **'{name}: {done} از {total}'**
  String jobProgress(String name, String done, String total);

  /// No description provided for @downloadStopped.
  ///
  /// In fa, this message translates to:
  /// **'بارگیری متوقف شد'**
  String get downloadStopped;

  /// No description provided for @recitationsDownloaded.
  ///
  /// In fa, this message translates to:
  /// **'خوانش‌های {name} بارگیری شد'**
  String recitationsDownloaded(String name);

  /// No description provided for @recitationsFailed.
  ///
  /// In fa, this message translates to:
  /// **'بارگیری خوانش‌ها ناموفق بود'**
  String get recitationsFailed;

  /// No description provided for @poetsTab.
  ///
  /// In fa, this message translates to:
  /// **'شاعران'**
  String get poetsTab;

  /// No description provided for @recitationsTab.
  ///
  /// In fa, this message translates to:
  /// **'خوانش‌ها'**
  String get recitationsTab;

  /// No description provided for @installedSummary.
  ///
  /// In fa, this message translates to:
  /// **'{count} شاعر روی دستگاه ({size} فشرده)'**
  String installedSummary(String count, String size);

  /// No description provided for @onDevice.
  ///
  /// In fa, this message translates to:
  /// **'روی دستگاه'**
  String get onDevice;

  /// No description provided for @updateAvailable.
  ///
  /// In fa, this message translates to:
  /// **'نسخهٔ تازه موجود است'**
  String get updateAvailable;

  /// No description provided for @update.
  ///
  /// In fa, this message translates to:
  /// **'به‌روزرسانی'**
  String get update;

  /// No description provided for @downloadAllRecitations.
  ///
  /// In fa, this message translates to:
  /// **'بارگیری همهٔ خوانش‌ها'**
  String get downloadAllRecitations;

  /// No description provided for @removeFromDevice.
  ///
  /// In fa, this message translates to:
  /// **'حذف از دستگاه'**
  String get removeFromDevice;

  /// No description provided for @downloadForReading.
  ///
  /// In fa, this message translates to:
  /// **'بارگیری برای خواندن آفلاین'**
  String get downloadForReading;

  /// No description provided for @noRecitationsYet.
  ///
  /// In fa, this message translates to:
  /// **'هنوز خوانشی بارگیری نشده است'**
  String get noRecitationsYet;

  /// No description provided for @recitationsSummary.
  ///
  /// In fa, this message translates to:
  /// **'{count} خوانش، {size}'**
  String recitationsSummary(String count, String size);

  /// No description provided for @searchMetre.
  ///
  /// In fa, this message translates to:
  /// **'جستجوی وزن (مثلاً مفاعیلن)'**
  String get searchMetre;

  /// No description provided for @hemistichCount.
  ///
  /// In fa, this message translates to:
  /// **'{count} مصرع'**
  String hemistichCount(String count);

  /// No description provided for @sameMetre.
  ///
  /// In fa, this message translates to:
  /// **'هم‌وزن‌ها'**
  String get sameMetre;

  /// No description provided for @sameMetreRhyme.
  ///
  /// In fa, this message translates to:
  /// **'هم‌وزن و هم‌قافیه'**
  String get sameMetreRhyme;

  /// No description provided for @rhymeIs.
  ///
  /// In fa, this message translates to:
  /// **'قافیه: {rhyme}'**
  String rhymeIs(String rhyme);

  /// No description provided for @poemCount.
  ///
  /// In fa, this message translates to:
  /// **'{count} شعر'**
  String poemCount(String count);

  /// No description provided for @downloadFailed.
  ///
  /// In fa, this message translates to:
  /// **'بارگیری ناموفق بود'**
  String get downloadFailed;

  /// No description provided for @downloadForListening.
  ///
  /// In fa, this message translates to:
  /// **'بارگیری برای شنیدن آفلاین'**
  String get downloadForListening;

  /// No description provided for @playFailed.
  ///
  /// In fa, this message translates to:
  /// **'پخش ممکن نشد'**
  String get playFailed;

  /// No description provided for @audioNeedsMediaPack.
  ///
  /// In fa, this message translates to:
  /// **'پخش خوانش روی این نسخهٔ ویندوز (N) به «Media Feature Pack» رایگان مایکروسافت نیاز دارد.'**
  String get audioNeedsMediaPack;

  /// No description provided for @howToInstall.
  ///
  /// In fa, this message translates to:
  /// **'راهنمای نصب'**
  String get howToInstall;

  /// No description provided for @audioNeedsMpv.
  ///
  /// In fa, this message translates to:
  /// **'پخش خوانش روی لینوکس به libmpv نیاز دارد؛ برای نمونه: sudo apt install libmpv2'**
  String get audioNeedsMpv;

  /// No description provided for @speed.
  ///
  /// In fa, this message translates to:
  /// **'سرعت'**
  String get speed;

  /// No description provided for @notInSync.
  ///
  /// In fa, this message translates to:
  /// **'بدون همگامی با متن'**
  String get notInSync;

  /// No description provided for @recitationsCount.
  ///
  /// In fa, this message translates to:
  /// **'خوانش‌ها ({count})'**
  String recitationsCount(String count);

  /// No description provided for @autoScrollOff.
  ///
  /// In fa, this message translates to:
  /// **'پیمایش خودکار خاموش'**
  String get autoScrollOff;

  /// No description provided for @autoScrollOn.
  ///
  /// In fa, this message translates to:
  /// **'پیمایش خودکار روشن'**
  String get autoScrollOn;

  /// No description provided for @note.
  ///
  /// In fa, this message translates to:
  /// **'یادداشت'**
  String get note;

  /// No description provided for @noteHint.
  ///
  /// In fa, this message translates to:
  /// **'یادداشت شما برای این بیت'**
  String get noteHint;

  /// No description provided for @lineNotRead.
  ///
  /// In fa, this message translates to:
  /// **'در این خوانش این خط خوانده نشده است'**
  String get lineNotRead;

  /// No description provided for @bookmark.
  ///
  /// In fa, this message translates to:
  /// **'نشان‌گذاری'**
  String get bookmark;

  /// No description provided for @findInPoem.
  ///
  /// In fa, this message translates to:
  /// **'جستجو در شعر'**
  String get findInPoem;

  /// No description provided for @meanings.
  ///
  /// In fa, this message translates to:
  /// **'معنی ابیات'**
  String get meanings;

  /// No description provided for @zoomIn.
  ///
  /// In fa, this message translates to:
  /// **'بزرگ‌نمایی'**
  String get zoomIn;

  /// No description provided for @zoomOut.
  ///
  /// In fa, this message translates to:
  /// **'کوچک‌نمایی'**
  String get zoomOut;

  /// No description provided for @switchTheme.
  ///
  /// In fa, this message translates to:
  /// **'تغییر پوسته'**
  String get switchTheme;

  /// No description provided for @copyPoem.
  ///
  /// In fa, this message translates to:
  /// **'رونوشت شعر'**
  String get copyPoem;

  /// No description provided for @share.
  ///
  /// In fa, this message translates to:
  /// **'هم‌رسانی'**
  String get share;

  /// No description provided for @findInThisPoem.
  ///
  /// In fa, this message translates to:
  /// **'جستجو در این شعر'**
  String get findInThisPoem;

  /// No description provided for @metre.
  ///
  /// In fa, this message translates to:
  /// **'وزن'**
  String get metre;

  /// No description provided for @rhyme.
  ///
  /// In fa, this message translates to:
  /// **'قافیه'**
  String get rhyme;

  /// No description provided for @summary.
  ///
  /// In fa, this message translates to:
  /// **'چکیده'**
  String get summary;

  /// No description provided for @playFromBeyt.
  ///
  /// In fa, this message translates to:
  /// **'پخش از این بیت'**
  String get playFromBeyt;

  /// No description provided for @unbookmarkBeyt.
  ///
  /// In fa, this message translates to:
  /// **'حذف نشان بیت'**
  String get unbookmarkBeyt;

  /// No description provided for @bookmarkBeyt.
  ///
  /// In fa, this message translates to:
  /// **'نشان‌گذاری بیت'**
  String get bookmarkBeyt;

  /// No description provided for @copyBeyt.
  ///
  /// In fa, this message translates to:
  /// **'رونوشت بیت'**
  String get copyBeyt;

  /// No description provided for @shareBeyt.
  ///
  /// In fa, this message translates to:
  /// **'هم‌رسانی بیت'**
  String get shareBeyt;

  /// No description provided for @meaningPrefix.
  ///
  /// In fa, this message translates to:
  /// **'معنی: {text}'**
  String meaningPrefix(String text);

  /// No description provided for @bookmarked.
  ///
  /// In fa, this message translates to:
  /// **'نشان‌دار'**
  String get bookmarked;

  /// No description provided for @hasNote.
  ///
  /// In fa, this message translates to:
  /// **'یادداشت دارد'**
  String get hasNote;

  /// No description provided for @beytOptions.
  ///
  /// In fa, this message translates to:
  /// **'گزینه‌های بیت'**
  String get beytOptions;

  /// No description provided for @relatedPanel.
  ///
  /// In fa, this message translates to:
  /// **'اشعار هم‌وزن و هم‌قافیه'**
  String get relatedPanel;

  /// No description provided for @quotedPanel.
  ///
  /// In fa, this message translates to:
  /// **'نقل‌قول‌ها و استقبال‌ها'**
  String get quotedPanel;

  /// No description provided for @imagesPanel.
  ///
  /// In fa, this message translates to:
  /// **'تصاویر نسخه‌های خطی'**
  String get imagesPanel;

  /// No description provided for @songsPanel.
  ///
  /// In fa, this message translates to:
  /// **'آهنگ‌ها'**
  String get songsPanel;

  /// No description provided for @commentsPanel.
  ///
  /// In fa, this message translates to:
  /// **'حاشیه‌ها'**
  String get commentsPanel;

  /// No description provided for @search.
  ///
  /// In fa, this message translates to:
  /// **'جستجو'**
  String get search;

  /// No description provided for @searchWords.
  ///
  /// In fa, this message translates to:
  /// **'واژه'**
  String get searchWords;

  /// No description provided for @searchMeaning.
  ///
  /// In fa, this message translates to:
  /// **'معنا'**
  String get searchMeaning;

  /// No description provided for @meaningHint.
  ///
  /// In fa, this message translates to:
  /// **'به زبان خودتان بپرسید؛ مثلاً: شعری دربارهٔ بی‌وفایی دنیا'**
  String get meaningHint;

  /// No description provided for @semanticScope.
  ///
  /// In fa, this message translates to:
  /// **'نتایج محدود به: {scope}'**
  String semanticScope(String scope);

  /// No description provided for @semanticGlobal.
  ///
  /// In fa, this message translates to:
  /// **'جستجوی سراسری'**
  String get semanticGlobal;

  /// No description provided for @semanticResting.
  ///
  /// In fa, this message translates to:
  /// **'جستجوی معنایی اکنون در دسترس نیست؛ کمی بعد دوباره امتحان کنید'**
  String get semanticResting;

  /// No description provided for @semanticOffline.
  ///
  /// In fa, this message translates to:
  /// **'جستجوی معنایی به اینترنت نیاز دارد'**
  String get semanticOffline;

  /// No description provided for @semanticCredit.
  ///
  /// In fa, this message translates to:
  /// **'با جستجوی معنایی گنجور'**
  String get semanticCredit;

  /// No description provided for @clear.
  ///
  /// In fa, this message translates to:
  /// **'پاک کردن'**
  String get clear;

  /// No description provided for @tajikScript.
  ///
  /// In fa, this message translates to:
  /// **'خط تاجیکی (سیریلیک)'**
  String get tajikScript;

  /// No description provided for @tajikScriptNote.
  ///
  /// In fa, this message translates to:
  /// **'متن تاجیکی ابیات از گنجور تاجیکی (tj.ganjoor.net)، برای شعرهایی که دارند'**
  String get tajikScriptNote;

  /// No description provided for @home.
  ///
  /// In fa, this message translates to:
  /// **'خانه'**
  String get home;

  /// No description provided for @poetLabel.
  ///
  /// In fa, this message translates to:
  /// **'شاعر: '**
  String get poetLabel;

  /// No description provided for @allPoets.
  ///
  /// In fa, this message translates to:
  /// **'همهٔ شاعران'**
  String get allPoets;

  /// No description provided for @offlineResults.
  ///
  /// In fa, this message translates to:
  /// **'نتایج آفلاین — فقط از مجموعه‌های بارگیری‌شده'**
  String get offlineResults;

  /// No description provided for @nothingFound.
  ///
  /// In fa, this message translates to:
  /// **'چیزی یافت نشد'**
  String get nothingFound;

  /// No description provided for @resultCount.
  ///
  /// In fa, this message translates to:
  /// **'{count} نتیجه'**
  String resultCount(String count);

  /// No description provided for @clearFailed.
  ///
  /// In fa, this message translates to:
  /// **'پاک‌کردن ممکن نشد'**
  String get clearFailed;

  /// No description provided for @cacheCleared.
  ///
  /// In fa, this message translates to:
  /// **'حافظهٔ موقت پاک شد'**
  String get cacheCleared;

  /// No description provided for @display.
  ///
  /// In fa, this message translates to:
  /// **'نمایش'**
  String get display;

  /// No description provided for @themeSystem.
  ///
  /// In fa, this message translates to:
  /// **'خودکار'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In fa, this message translates to:
  /// **'روشن'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In fa, this message translates to:
  /// **'تیره'**
  String get themeDark;

  /// No description provided for @language.
  ///
  /// In fa, this message translates to:
  /// **'زبان برنامه'**
  String get language;

  /// No description provided for @verseTextSize.
  ///
  /// In fa, this message translates to:
  /// **'اندازهٔ متن شعر'**
  String get verseTextSize;

  /// No description provided for @showMeaningsDefault.
  ///
  /// In fa, this message translates to:
  /// **'نمایش معنی ابیات به‌طور پیش‌فرض'**
  String get showMeaningsDefault;

  /// No description provided for @useIranNastaliq.
  ///
  /// In fa, this message translates to:
  /// **'استفاده از قلم ایران‌نستعلیق (اگر نصب است)'**
  String get useIranNastaliq;

  /// No description provided for @iranNastaliqNote.
  ///
  /// In fa, this message translates to:
  /// **'در غیر این صورت نستعلیق نوتو به کار می‌رود'**
  String get iranNastaliqNote;

  /// No description provided for @storage.
  ///
  /// In fa, this message translates to:
  /// **'حافظه'**
  String get storage;

  /// No description provided for @cacheSize.
  ///
  /// In fa, this message translates to:
  /// **'حافظهٔ موقت صفحه‌های خوانده‌شده'**
  String get cacheSize;

  /// No description provided for @clearCache.
  ///
  /// In fa, this message translates to:
  /// **'پاک‌کردن حافظهٔ موقت'**
  String get clearCache;

  /// No description provided for @clearCacheNote.
  ///
  /// In fa, this message translates to:
  /// **'مجموعه‌های بارگیری‌شده، خوانش‌ها و نشان‌ها دست نمی‌خورند'**
  String get clearCacheNote;

  /// No description provided for @about.
  ///
  /// In fa, this message translates to:
  /// **'درباره'**
  String get about;

  /// No description provided for @aboutText.
  ///
  /// In fa, this message translates to:
  /// **'گنج نرم‌افزاری آزاد و رایگان برای خواندن و شنیدن شعر پارسی است و به پاس «گنجور» ساخته شده است. شعرها، خوانش‌ها، معنی ابیات و تصاویر از گنجور (ganjoor.net) و به همت بنیان‌گذار آن، حمیدرضا محمدی، و صدها داوطلب فراهم آمده است؛ خوانش‌ها از آنِ خوانندگانشان است. گنج وابسته به گنجور نیست.'**
  String get aboutText;

  /// No description provided for @madeBy.
  ///
  /// In fa, this message translates to:
  /// **'طراحی و ساخت: امین اکبری'**
  String get madeBy;

  /// No description provided for @ganjoor.
  ///
  /// In fa, this message translates to:
  /// **'گنجور'**
  String get ganjoor;

  /// No description provided for @sourceCode.
  ///
  /// In fa, this message translates to:
  /// **'کد منبع (GPL-3.0)'**
  String get sourceCode;

  /// No description provided for @licenses.
  ///
  /// In fa, this message translates to:
  /// **'پروانه‌ها'**
  String get licenses;

  /// No description provided for @versionN.
  ///
  /// In fa, this message translates to:
  /// **'نسخهٔ {version}'**
  String versionN(String version);

  /// No description provided for @backupCopied.
  ///
  /// In fa, this message translates to:
  /// **'پشتیبان در حافظهٔ موقت رونوشت شد'**
  String get backupCopied;

  /// No description provided for @backupSubject.
  ///
  /// In fa, this message translates to:
  /// **'پشتیبان گنج'**
  String get backupSubject;

  /// No description provided for @importBackup.
  ///
  /// In fa, this message translates to:
  /// **'ورود از پشتیبان'**
  String get importBackup;

  /// No description provided for @pasteBackup.
  ///
  /// In fa, this message translates to:
  /// **'متن پشتیبان را اینجا بچسبانید'**
  String get pasteBackup;

  /// No description provided for @importAction.
  ///
  /// In fa, this message translates to:
  /// **'ورود'**
  String get importAction;

  /// No description provided for @itemsImported.
  ///
  /// In fa, this message translates to:
  /// **'{count} مورد وارد شد'**
  String itemsImported(String count);

  /// No description provided for @backupInvalid.
  ///
  /// In fa, this message translates to:
  /// **'متن پشتیبان معتبر نیست'**
  String get backupInvalid;

  /// No description provided for @exportBackup.
  ///
  /// In fa, this message translates to:
  /// **'پشتیبان‌گیری'**
  String get exportBackup;

  /// No description provided for @bookmarksTab.
  ///
  /// In fa, this message translates to:
  /// **'نشان‌ها'**
  String get bookmarksTab;

  /// No description provided for @historyTab.
  ///
  /// In fa, this message translates to:
  /// **'تاریخچه'**
  String get historyTab;

  /// No description provided for @notesTab.
  ///
  /// In fa, this message translates to:
  /// **'یادداشت‌ها'**
  String get notesTab;

  /// No description provided for @userDataFailed.
  ///
  /// In fa, this message translates to:
  /// **'خواندن داده‌ها ممکن نشد'**
  String get userDataFailed;

  /// No description provided for @noBookmarks.
  ///
  /// In fa, this message translates to:
  /// **'هنوز نشانی نگذاشته‌اید'**
  String get noBookmarks;

  /// No description provided for @noHistory.
  ///
  /// In fa, this message translates to:
  /// **'هنوز شعری نخوانده‌اید'**
  String get noHistory;

  /// No description provided for @noNotes.
  ///
  /// In fa, this message translates to:
  /// **'هنوز یادداشتی ننوشته‌اید'**
  String get noNotes;
}

class _L10nDelegate extends LocalizationsDelegate<L10n> {
  const _L10nDelegate();

  @override
  Future<L10n> load(Locale locale) {
    return SynchronousFuture<L10n>(lookupL10n(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en', 'fa'].contains(locale.languageCode);

  @override
  bool shouldReload(_L10nDelegate old) => false;
}

L10n lookupL10n(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return L10nEn();
    case 'fa':
      return L10nFa();
  }

  throw FlutterError(
    'L10n.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
