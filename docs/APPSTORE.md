# رفع مسار إلى App Store

البناء والتوقيع والرفع وتصوير الشاشات ونصوص المتجر تتم آلياً من GitHub عبر سير العمل **App Store**.
المطلوب منكِ أربع خطوات في حساباتك لا يمكن تنفيذها نيابة عنك: إنشاء الحساب، وتسجيل المعرّف، وإنشاء سجل التطبيق، ومفتاح API. بعدها يكون الرفع ضغطة زر.

| | القيمة |
| --- | --- |
| معرّف التطبيق (Bundle ID) | `app.masarmetro.ios` |
| حاوية iCloud | `iCloud.app.masarmetro.ios` |
| الإصدار | `1.0.0`، ورقم البناء يزيد تلقائياً مع كل تشغيل |
| الأجهزة | iPhone. يعمل على iPad بوضع iPhone، فلا يحتاج المتجر صور iPad |
| اللغة الأساسية في المتجر | العربية |

## 1. حساب Apple Developer

- الأسرع: تطبيق **Apple Developer** على iPhone ← Account ← **Enroll Now**. التطبيق يتحقق من الهوية بالكاميرا.
- اختاري **Individual** (فرد). الرسوم 99 دولاراً سنوياً، ويظهر السعر بالريال عند الدفع.
- الموافقة تأخذ عادة حتى 48 ساعة.
- بعد التفعيل افتحي https://developer.apple.com/account ← Membership details، وانسخي **Team ID**. يتكون من 10 خانات.
- عند تأسيس الشركة لاحقاً يُنقل التطبيق إلى حسابها من App Store Connect ← App Information ← **Transfer App**، دون فقد التقييمات أو المستخدمين.

## 2. تسجيل المعرّف والحاوية

من https://developer.apple.com/account/resources:

1. **Identifiers ← + ← iCloud Containers**. الوصف `Masar`، والمعرّف `iCloud.app.masarmetro.ios`.
2. **Identifiers ← + ← App IDs ← App**:
   - الوصف `Masar`، و**Explicit** بالقيمة `app.masarmetro.ios`.
   - فعّلي **iCloud** (ثم اختاري CloudKit، ثم Configure ← الحاوية السابقة)، و**Push Notifications**، و**Sign in with Apple**.

## 3. سجل التطبيق في App Store Connect

https://appstoreconnect.apple.com ← Apps ← **+** ← New App:

| الحقل | القيمة |
| --- | --- |
| Platforms | iOS |
| Name | `مسار – رحلات مترو الرياض`. إن ظهر أنه محجوز فاستخدمي `Masar Metro – مسار` |
| Primary Language | Arabic |
| Bundle ID | `app.masarmetro.ios` |
| SKU | `masar-ios-001` |
| User Access | Full Access |

## 4. مفتاح API وأسرار GitHub

1. App Store Connect ← **Users and Access ← Integrations ← App Store Connect API ← Team Keys ← +**.
   الاسم `GitHub`، والصلاحية **Admin**. هذه الصلاحية لازمة كي تُنشئ Apple شهادة التوزيع وملفات التوقيع تلقائياً.
2. نزّلي ملف `.p8`. يُنزَّل **مرة واحدة فقط**، فاحفظيه في مكان آمن. وانسخي **Issuer ID** و**Key ID** من الصفحة نفسها.
3. في المستودع: Settings ← Secrets and variables ← Actions ← **New repository secret**، وأضيفي أربعة أسرار:

| الاسم | القيمة |
| --- | --- |
| `APPLE_TEAM_ID` | Team ID من الخطوة 1 |
| `ASC_KEY_ID` | Key ID |
| `ASC_ISSUER_ID` | Issuer ID |
| `ASC_KEY_P8` | محتوى ملف `.p8` كاملاً، من `-----BEGIN PRIVATE KEY-----` إلى آخره |

هذه الأسرار لا تُرسل لأحد، ولا تُلصق في محادثة أو بلاغ. GitHub يخفيها حتى عن سجلات التشغيل.

## 5. الرفع

Actions ← **App Store** ← Run workflow، مع تفعيل **upload** و**metadata**. التشغيل يستغرق نحو 20 دقيقة، وفيه:

- **screenshots:** صور شاشة iPhone بمقاس 6.9 بوصة، بالعربية والإنجليزية، من التطبيق نفسه. تجدينها في أسفل صفحة التشغيل باسم `app-store-screenshots`.
- **upload:** يبني التطبيق ويوقّعه ويرفعه. يظهر البناء في App Store Connect ← **TestFlight** بعد معالجة Apple، عادةً خلال 10 إلى 30 دقيقة.
- **نصوص المتجر:** الاسم والعنوان الفرعي والوصف والكلمات المفتاحية بكل لغة يقبلها المتجر، من `ios/AppStore/metadata.json`، والفئتان «التنقل» و«السفر». اللغة التي لا يقبلها المتجر تُتخطّى مع تنبيه في السجل.

جرّبي البناء على جوالك من تطبيق **TestFlight** قبل الإرسال للمراجعة.

## 6. صفحة المتجر والإرسال للمراجعة

في App Store Connect ← التطبيق:

1. **الصور:** في صفحة الإصدار 1.0.0، ارفعي صور `ar` للغة العربية وصور `en` للإنجليزية. بقية اللغات تأخذ صور العربية تلقائياً.
2. **App Privacy:** اختاري **Data Not Collected**. التطبيق لا يرسل أي بيانات إلينا، والمزامنة تتم في حساب iCloud الخاص بالمستخدم، والإعلانات تُختار حسب المحطة لا حسب الشخص.
3. **Age Rating:** أجيبي «لا» عن كل الأسئلة، فيظهر التصنيف **4+**.
4. **App Information ← Content Rights:** بيانات المحطات من البيانات المفتوحة للهيئة الملكية لمدينة الرياض. **Advertising:** نعم، التطبيق يعرض إعلانات.
5. **Pricing and Availability:**
   - السعر مجاني.
   - التوفر: السعودية ودول الخليج في البداية.
   - لا تضيفي دول الاتحاد الأوروبي الآن. التوزيع فيها يشترط إعلان صفة «تاجر»، ونشر عنوان ورقم هاتف للتواصل في صفحة المتجر.
6. **App Review Information:**
   - لا حاجة لحساب تجريبي، لأن التطبيق لا يشترط الدخول.
   - ألصقي في الملاحظات نص `reviewNotes` من `ios/AppStore/metadata.json`.
   - بيانات التواصل: بريد `info@masarmetro.app` ورقم جوالك.
7. اختاري البناء من قسم **Build**، ثم **Add for Review** ← **Submit**. المراجعة تأخذ عادة 24 إلى 48 ساعة.

## 7. مزامنة iCloud في النسخة المنشورة

النسخة المنشورة تستخدم بيئة **Production** في CloudKit. هذه البيئة لا تُنشأ جداولها إلا من نسخة تطوير تعمل مرة على جهاز، وحتى ذلك الحين يعمل التطبيق كاملاً ويحفظ على الجهاز، لكن لا تنتقل الأماكن المحفوظة بين أجهزة المستخدم. لتفعيلها مرة واحدة:

1. على الـMac ثبّتي Xcode، ثم شغّلي `python3 tools/build.py` ثم `cd ios && xcodegen generate && open Masar.xcodeproj`.
2. شغّلي التطبيق على جوالك من Xcode، بحسابك في Signing، ثم احفظي مكاناً واحداً.
3. من https://icloud.developer.apple.com ← الحاوية `iCloud.app.masarmetro.ios` ← **Deploy Schema Changes** إلى Production.

## تحديثات لاحقة

1. غيّري `MARKETING_VERSION` في `ios/project.yml`، مثلاً إلى `1.0.1`.
2. شغّلي سير العمل نفسه.
3. أضيفي نص «ما الجديد» في App Store Connect، ثم أرسلي النسخة للمراجعة.
