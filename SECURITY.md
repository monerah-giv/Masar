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
