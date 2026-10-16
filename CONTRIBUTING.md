# المساهمة في مسار / Contributing to Masar

## المصدر الوحيد للحقيقة / One source of truth
كل المحطات والأسعار والنصوص في `data/`. لا تعدّل الملفات المولّدة يدوياً:
All stations, fares and text live in `data/`. Never hand-edit generated files:
`dist/`, `ios/Masar/Resources/{network.json,fares.json,*.xcstrings}`.

```bash
python3 tools/build.py                      # يولّد الويب والموقع وموارد iOS
python3 -m unittest discover -s tests       # فحص البيانات والترجمات
node --test tests/engine.test.mjs tests/ads.test.mjs           # فحص محرك المسارات
```

## قواعد / Rules
- **اللغات**: أي نص جديد يُضاف بالثماني لغات (ar, en, ur, hi, bn, fil, id, zh) وبنفس المتغيرات `{…}`.
- **الاتجاه**: اختبر بالعربية (RTL) والإنجليزية (LTR).
- **الوصول**: أهداف لمس ≥ 44 نقطة، تسميات لقارئ الشاشة، تباين مقروء، احترام «تقليل الحركة».
- **الخصوصية**: لا يُحفظ الموقع ولا يُرسل. راجع `SECURITY.md`.
- **المحرك**: أي تعديل في البحث يجب أن يجتاز اختبار المطابقة مع المرجع (13,612 زوجاً) واختبار الباب إلى الباب.
- **iOS**: يُبنى بـ XcodeGen (`ios/project.yml`)؛ لا يُرفع ملف `.xcodeproj`.

## الفروع والرسائل / Branches & commits
فرع لكل تغيير، وطلب دمج يمر بفحوص CI. رسائل الالتزام بصيغة: `feat:`، `fix:`، `data:`، `i18n:`، `ci:`، `docs:`.
