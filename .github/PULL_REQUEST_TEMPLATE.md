## ما الذي تغيّر؟ / What changed

## لماذا؟ / Why

## التحقق / Checks
- [ ] `python3 tools/build.py` ثم رفع ملفات `ios/Masar/Resources` المولّدة
- [ ] `python3 -m unittest discover -s tests` و `node --test tests/engine.test.mjs tests/ads.test.mjs tests/admin.test.mjs`
- [ ] أي نص جديد مترجم في `data/strings.json` باللغات الثماني
- [ ] جُرّب على الجوال بالوضعين الفاتح والداكن، وبالعربية (RTL) والإنجليزية (LTR)
- [ ] لا يُحفظ موقع المستخدم ولا يُرسل خارج جهازه
