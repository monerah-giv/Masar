# النطاق masarmetro.app والبريد info@masarmetro.app

هذا الدليل ينقل موقع مسار من `monerah-giv.github.io/Masar` إلى `https://masarmetro.app/`، ويفعّل بريد الأعمال `info@masarmetro.app`.
الشيفرة جاهزة في فرع `feat/custom-domain`. **لا تدمجيه قبل الخطوة 5**، وإلا ستشير روابط الخصوصية والشروط وملف الإعلانات في التطبيق إلى نطاق لا يعمل، وسترتد رسائل المعلنين.

## 1. حجز النطاق

- النطاق الأساسي هو `masarmetro.app`، ومعه `masarmetro.com` محجوز منذ 1 نوفمبر 2026 ويُحوَّل إليه (الخطوة 7).
- `.app` و`.com` نطاقان عالميان. لا يطلبان سجلاً تجارياً ولا وثائق سعودية، ويُفعَّلان خلال دقائق من الدفع.
- **`.app` يعمل عبر HTTPS فقط.** هذا إلزامي في كل المتصفحات، فلا يفتح الموقع على النطاق إلا بعد أن يصدر GitHub الشهادة (الخطوة 5).
- **المسجّل: Cloudflare Registrar**، وهو نفس حساب `masarmetro.com`. يبيع بسعر التكلفة، ويخفي بيانات المالك (WHOIS) مجاناً.
- عند الشراء:
  - فعّلي **التجديد التلقائي** و**قفل النقل (Transfer lock)**.
  - احجزي لسنتين أو أكثر.
  - استخدمي بريداً تملكينه، وفعّلي التحقق الثنائي (2FA) في الحساب.
- **إن تغيّر الاسم مرة أخرى** فأمر واحد ينقل كل الروابط والبريد والملفات المولّدة إليه:

  ```
  python3 tools/set_domain.py <النطاق>
  ```
- النطاق `.sa` يمكن إضافته لاحقاً، بعد قيد كيان يحمل الاسم، ويُحوَّل إلى `.app` بالطريقة نفسها.

## 2. توثيق النطاق في GitHub (قبل ربطه)

من Settings في حسابك على GitHub، ثم Pages، ثم Add a domain. أدخلي `masarmetro.app`، وانسخي سجل TXT الذي يعطيك إياه إلى DNS، ثم Verify. هذا يمنع أي أحد من الاستيلاء على النطاق عبر GitHub.

## 3. سجلات DNS للموقع

| النوع | الاسم | القيمة |
| --- | --- | --- |
| A | `@` | `185.199.108.153` |
| A | `@` | `185.199.109.153` |
| A | `@` | `185.199.110.153` |
| A | `@` | `185.199.111.153` |
| AAAA | `@` | `2606:50c0:8000::153` |
| AAAA | `@` | `2606:50c0:8001::153` |
| AAAA | `@` | `2606:50c0:8002::153` |
| AAAA | `@` | `2606:50c0:8003::153` |
| CNAME | `www` | `monerah-giv.github.io` |

- لا تضيفي سجلاً عاماً مثل `*.masarmetro.app`.
- في Cloudflare اجعلي هذه السجلات «DNS only» (السحابة الرمادية)، حتى يستطيع GitHub إصدار شهادة HTTPS.

## 4. البريد info@masarmetro.app

اختاري مزوداً واحداً:

- **Zoho Mail**: فيه خطة مجانية حتى 5 مستخدمين، و5 GB لكل مستخدم، ونطاق واحد. اختاري مركز البيانات الأقرب عند التسجيل.
- **Google Workspace**: مدفوع لكل مستخدم شهرياً، ومألوف للعملاء.

ثم:

1. أضيفي النطاق في لوحة المزود، وأثبتي ملكيته بسجل TXT.
2. أنشئي الصندوق `info`. يمكن لاحقاً إضافة أسماء بديلة مثل `ads@` و`support@` إلى الصندوق نفسه.
3. أضيفي سجلات **MX** كما تظهر في لوحة المزود بقيمها وأولوياتها. تختلف القيم حسب المزود ومركز البيانات، فلا تنسخيها من مكان آخر.
4. **SPF**: سجل TXT واحد فقط على `@`، يُنسخ من لوحة المزود. مثاله لـ Zoho: `v=spf1 include:zoho.com ~all`.
5. **DKIM**: أنشئي المفتاح في لوحة المزود، وأضيفي سجل TXT الذي يعطيك إياه، ثم اضغطي Verify.
6. **DMARC**: سجل TXT على الاسم `_dmarc` بالقيمة `v=DMARC1; p=none; rua=mailto:info@masarmetro.app`. بعد شهر بلا مشاكل غيّري `p=none` إلى `p=quarantine`.
7. اختبري البريد بإرسال رسالة من Gmail إلى `info@masarmetro.app` والرد عليها، وتأكدي أن الرد لم يصل إلى الرسائل غير المرغوب فيها.

## 5. ربط الموقع بالنطاق

1. في المستودع افتحي Settings، ثم Pages، ثم Custom domain. اكتبي `masarmetro.app` واحفظي. النشر يتم عبر GitHub Actions، فلا يلزم ملف CNAME.
2. انتظري حتى يكتمل فحص DNS، ثم فعّلي **Enforce HTTPS**. قد يستغرق ظهور هذا الخيار حتى 24 ساعة.
3. افتحي `https://masarmetro.app/` و`https://www.masarmetro.app/`.

## 6. الدمج والتحقق

بعد نجاح الخطوتين 4 و5:

1. ادمجي طلب الدمج من الفرع `feat/custom-domain`. سيعيد Deploy site نشر الموقع بالروابط الجديدة.
2. تأكدي أن `https://masarmetro.app/ads.json` يعرض `"email": "info@masarmetro.app"`.
3. تأكدي أن `https://masarmetro.app/privacy/` يعرض البريد.
4. أرسلي `https://masarmetro.app/sitemap.xml` إلى Google Search Console.
5. الرابط القديم `monerah-giv.github.io/Masar/` يحوّله GitHub تلقائياً إلى النطاق الجديد، فلا تنكسر الروابط المطبوعة سابقاً.
6. تطبيق iPhone يأخذ الروابط الجديدة من نسخته القادمة. وحتى ذلك الحين تعمل روابطه القديمة عبر التحويل نفسه.

## 7. تحويل masarmetro.com إلى masarmetro.app

GitHub Pages يقبل نطاقاً واحداً، فيُحوَّل `.com` إلى `.app` من Cloudflare مع الحفاظ على المسار. مثلاً `masarmetro.com/privacy/` يذهب إلى `masarmetro.app/privacy/`.

1. في Cloudflare افتحي `masarmetro.com`، ثم **DNS → Records**، وأضيفي:
   - `A` باسم `@` وقيمة `192.0.2.1`، مع **Proxied** (السحابة البرتقالية).
   - `CNAME` باسم `www` وقيمة `masarmetro.com`، مع **Proxied**.

   هذا العنوان لا يُستخدم فعلياً، فـ Cloudflare يجيب بنفسه.
2. افتحي **Rules → Redirect Rules → Create rule** واملئي:
   - **If:** All incoming requests.
   - **Then:** Dynamic، والعبارة `concat("https://masarmetro.app", http.request.uri.path)`.
   - **Status code:** 301، وفعّلي **Preserve query string**.
3. احفظي، ثم جرّبي `https://masarmetro.com/station/` و`https://www.masarmetro.com/`.

## ما تغيّر في الشيفرة

- `data/app.json`: صار `siteUrl` هو `https://masarmetro.app/`، وأُضيف `contactEmail` بقيمة `info@masarmetro.app`. هذا البريد يظهر في صفحتي الخصوصية والشروط.
- `data/ads.json`: صار `contact.email` هو `info@masarmetro.app`، فتصل طلبات المعلنين إلى البريد بدل بلاغات GitHub.
- روابط الخصوصية والشروط في تطبيق iPhone وفي بيانات المتجر، وروابط README وPRESS وADMIN.
- الملفات المولّدة (sitemap وروابط canonical وملف الإعلانات المضمَّن في التطبيق) تُبنى من `siteUrl` تلقائياً.
- `tools/set_domain.py`: ينقل كل ما سبق إلى نطاق آخر بأمر واحد، ثم يعيد البناء.
