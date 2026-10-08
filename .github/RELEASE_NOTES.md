**Ganj** — a free, open-source, *unofficial* reader for Persian poetry, made in tribute to **[Ganjoor](https://ganjoor.net)**: read and listen on your phone or computer, even offline.

<div dir="rtl">

**گنج** — خواننده‌ای آزاد، رایگان و غیررسمی برای شعر پارسی، به پاس **[گنجور](https://ganjoor.net)**: خواندن و شنیدن شعر روی گوشی و رایانه، حتی بی‌اینترنت.

</div>

## What's new · تازه‌ها

### 1.1.4
- Windows: Ganj draws on the integrated graphics chip by default and registers itself as "Power saving" in Windows' graphics settings — fixes the empty white window on dual-GPU (Optimus) laptops with older drivers; `--gpu=high` overrides.

<div dir="rtl">

- ویندوز: گنج به‌طور پیش‌فرض روی تراشهٔ گرافیکی داخلی رسم می‌کند و خود را در تنظیمات گرافیک ویندوز «کم‌مصرف» ثبت می‌کند؛ پنجرهٔ سفید خالی روی لپ‌تاپ‌های دوتراشه‌ای (Optimus) با درایورهای قدیمی رفع شد. با `--gpu=high` می‌توان تراشهٔ جداگانه را برگزید.

</div>

### 1.1.3
- Translation now uses Ganjoor's plain-Persian meaning of each beyt when there is one — much better results than translating the verse itself.
- Windows: start-up diagnostics; `Ganj-diagnose.cmd` collects a report for computers that show an empty window.

<div dir="rtl">

- ترجمه اکنون، هرجا گنجور معنی سادهٔ بیت را دارد، همان معنی را ترجمه می‌کند — نتیجه‌ای بسیار بهتر از ترجمهٔ خودِ بیت.
- ویندوز: عیب‌یابی آغاز برنامه؛ `Ganj-diagnose.cmd` برای رایانه‌هایی که پنجرهٔ خالی نشان می‌دهند گزارش می‌سازد.

</div>

### 1.1.2
- Android: translation works again in release builds; if on-device translation ever fails, it continues online and then offers Google Translate.
- The text-selection menu keeps only Copy and Select all.

<div dir="rtl">

- اندروید: ترجمه در نسخهٔ انتشاری دوباره کار می‌کند؛ اگر ترجمهٔ روی دستگاه ناموفق باشد، آنلاین ادامه می‌دهد و سپس Google Translate را پیشنهاد می‌کند.
- منوی انتخاب متن فقط «کپی» و «انتخاب همه» را نگه می‌دارد.

</div>

### 1.1.1
- Windows: no more white window on older or budget computers; Windows N and Linux without libmpv explain how to enable audio.
- Android: translation fixed (offers Google Translate when the model can't be downloaded); neater poem menu and toolbar.
- Smaller: unused libraries removed.

<div dir="rtl">

- ویندوز: دیگر پنجرهٔ سفید روی رایانه‌های قدیمی یا ارزان نشان داده نمی‌شود؛ ویندوز N و لینوکس بدون libmpv راه فعال‌کردن صدا را توضیح می‌دهند.
- اندروید: ترجمه درست شد (اگر مدل بارگیری نشود، Google Translate پیشنهاد می‌شود)؛ منو و نوار ابزار شعر مرتب‌تر شد.
- کوچک‌تر: کتابخانه‌های بی‌استفاده حذف شدند.

</div>

### 1.1
- Search by meaning (Ganjoor's semantic search); one home search box for poets, books and poems.
- Tajik (Cyrillic) script under the verses, from Ganjoor's Tajik data.
- Download a poet from their own page; home button everywhere; pictures kept for offline use.

<div dir="rtl">

- جستجو با معنا (جستجوی معنایی گنجور)؛ یک کادر جستجو در خانه برای سخنوران، کتاب‌ها و شعرها.
- خط تاجیکی (سیریلیک) زیر ابیات، از داده‌های تاجیکی گنجور.
- بارگیری دیوان هر شاعر از صفحهٔ خودش؛ دکمهٔ خانه در همه‌جا؛ نگه‌داری تصاویر برای استفادهٔ بی‌اینترنت.

</div>

## Download · دریافت

| Platform · سکو | File · فایل | Notes · توضیح |
|---|---|---|
| Android | `Ganj-*-android.apk` | Works on every phone; smaller per-device builds: `-arm64` (most phones), `-arm32`, `-x86_64`. Allow "install unknown apps" when asked. · روی همهٔ گوشی‌ها کار می‌کند؛ نسخه‌های کوچک‌تر: `-arm64` (بیشتر گوشی‌ها)، `-arm32`، `-x86_64`. اگر پرسید، نصب از منابع ناشناس را اجازه دهید. |
| Windows 10/11 (64-bit) | `Ganj-*-windows-x64.zip` | Unzip and run `Ganj\ganj.exe` (keep the whole folder). · از حالت فشرده خارج کنید و `Ganj\ganj.exe` را اجرا کنید (کل پوشه را نگه دارید). |
| macOS | `Ganj-*-macos.zip` | Not signed by Apple: right-click `ganj.app` → **Open** the first time. · امضای اپل ندارد: بار نخست روی `ganj.app` راست‌کلیک کنید و **Open** را بزنید. |
| Linux (x64) | `Ganj-*-linux-x64.tar.gz` | Extract and run `Ganj/ganj`. Needs `libmpv` for audio (`sudo apt install libmpv2`). · باز کنید و `Ganj/ganj` را اجرا کنید؛ برای صدا `libmpv` لازم است. |
| iOS / iPadOS 15.5+ | `Ganj-*-ios-unsigned.ipa` | Unsigned: install with a sideloading tool (AltStore, Sideloadly) that signs it with your Apple ID. · بدون امضا: با ابزار سایدلود (AltStore، Sideloadly) و اپل‌آیدی خودتان نصب کنید. |

`SHA256SUMS.txt` lists checksums for every file. · چک‌سام همهٔ فایل‌ها در `SHA256SUMS.txt` است.

Ganj is **not affiliated with Ganjoor**. Poems, recitations, meanings and images come from Ganjoor and its contributors; the app is GPL-3.0-or-later. See the README for details and credits.

<div dir="rtl">

گنج **وابسته به گنجور نیست**. شعرها، خوانش‌ها، معنی‌ها و تصاویر از گنجور و همکارانش است؛ برنامه زیر پروانهٔ GPL-3.0-or-later است. جزئیات و سپاس‌ها در README.

</div>
