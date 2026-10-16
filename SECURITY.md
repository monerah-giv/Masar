# الأمان والخصوصية / Security & privacy

## الإبلاغ عن ثغرة / Reporting a vulnerability
بلّغ عبر **Security → Report a vulnerability** في هذا المستودع (بلاغ خاص)، ولا تفتح بلاغاً عاماً.
Please use **Security → Report a vulnerability** (private advisory). Do not open a public issue.

## مبادئ الخصوصية / Privacy principles
- الموقع يُستخدم على الجهاز فقط لاختيار أقرب محطة، ولا يُخزَّن ولا يُرسل إلى أي خادم لمسار.
  Location is used on the device only to pick stations; it is never stored or sent to a Masar server.
- سجل الرحلات يحفظ محطة ← محطة فقط، ولا يحفظ عناوين أو مواقع.
  Trip history keeps station-to-station pairs only — never addresses or coordinates.
- في iOS تُزامَن الأماكن المحفوظة عبر iCloud الخاص بالمستخدم؛ لا يوجد خادم وسيط.
  On iOS saved places sync through the user's own iCloud; there is no intermediate server.
- الإعلانات سياقية فقط: تُختار حسب المحطة التي يتجه إليها الراكب، لا حسب هويته. لا تحليلات ولا تتبّع ولا معرّفات إعلانية، ولا يُرسل شيء عن الراكب عند جلب الإعلانات.
  Ads are contextual only — chosen by the destination station, never by who the rider is. No analytics, tracking or ad identifiers; fetching the ad feed sends nothing about the rider.

## لوحة التحكم / Admin page
- الدخول بمفتاح GitHub دقيق الصلاحية (Contents على هذا المستودع فقط) لحساب مُدرج في `admins`، ولا يُحفظ المفتاح إلا في متصفح المدير.
  Sign-in uses the admin's own fine-grained GitHub token (Contents on this repo only) and an allow-list; the token stays in the admin's browser.
- بيانات المعلنين والمدفوعات مشفّرة (AES-256-GCM، PBKDF2-SHA256 ×310,000) في `data/billing.enc`؛ المستودع لا يحوي نصاً مقروءاً منها.
  Advertiser and payment data are encrypted (AES-256-GCM, PBKDF2-SHA256 ×310k) in `data/billing.enc`; the repo never holds them in clear.
- الصفحة لا تحمل أسراراً ولا بيانات؛ معرفة رابطها لا تمنح أي وصول.
  The page itself carries no secrets or data; knowing its address grants nothing.
