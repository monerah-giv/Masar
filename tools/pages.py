"""Static pages for the public site: privacy, terms, advertiser terms, the advertiser media kit,
one page per station (search engines answer "how do I get to X by metro" with these) and a sitemap.

Everything is generated from data/*.json by tools/build.py, so a station rename or a new price
updates every page on the next build. Pages are bilingual (Arabic first, English second)."""
import heapq, html, json, os

E = html.escape
LANDMARKS = ["t12", "kafd", "qasrhokm", "museum", "ksu", "kfstadium"]
EFFECTIVE = "2026-10-17"

CSS = """
:root{--bg:#EEF3F1;--surface:#fff;--soft:#E3ECE8;--ink:#0B1A22;--muted:#51635D;--rule:#D3DED9;--accent:#00795C;--accent-ink:#fff;--accent-soft:#D6EEE5;--gold:#F6B53C;--gold-soft:#FCEFD2;
--f-display:"Readex Pro","IBM Plex Sans Arabic",system-ui,sans-serif;--f-body:"IBM Plex Sans Arabic",system-ui,"Segoe UI",Tahoma,sans-serif;color-scheme:light}
@media (prefers-color-scheme:dark){:root{--bg:#08141A;--surface:#0F2129;--soft:#16303A;--ink:#E6F0EC;--muted:#93AAA3;--rule:#21404A;--accent:#34C495;--accent-ink:#03140E;--accent-soft:#0F3B2F;--gold:#FFC65A;--gold-soft:#3A2D10;color-scheme:dark}}
*{box-sizing:border-box}html{font-size:16px}
body{margin:0;background:var(--bg);color:var(--ink);font-family:var(--f-body);line-height:1.7;padding:0 max(16px,env(safe-area-inset-left,0px)) 48px max(16px,env(safe-area-inset-right,0px))}
.wrap{max-width:760px;margin:0 auto}
header.top{display:flex;align-items:center;gap:12px;padding:18px 0 8px}
header.top a.brand{display:flex;align-items:center;gap:10px;color:var(--ink);text-decoration:none;font-family:var(--f-display);font-weight:700;font-size:1.25rem}
.mark{width:36px;height:36px;border-radius:10px;background:var(--accent);display:grid;place-items:center}.mark i{width:12px;height:12px;border-radius:50%;background:var(--gold);box-shadow:0 0 0 4px #fff}
header.top .grow{flex:1}
header.top nav a{color:var(--muted);text-decoration:none;font-size:.9rem;margin-inline-start:14px}
h1,h2,h3{font-family:var(--f-display);line-height:1.3;text-wrap:balance}
h1{font-size:1.9rem;margin:18px 0 6px}h2{font-size:1.25rem;margin:28px 0 8px}h3{font-size:1.05rem;margin:18px 0 6px}
p,li{max-width:68ch}a{color:var(--accent)}
.lead{color:var(--muted);font-size:1.05rem;margin:0 0 12px}
.card{background:var(--surface);border:1px solid var(--rule);border-radius:16px;padding:16px 18px;margin:14px 0}
.cta{display:flex;flex-wrap:wrap;gap:10px;margin:16px 0}
.btn{display:inline-flex;align-items:center;gap:8px;min-height:46px;padding:10px 18px;border-radius:12px;background:var(--accent);color:var(--accent-ink);font-weight:700;text-decoration:none}
.btn.ghost{background:var(--soft);color:var(--ink)}
.badge{display:inline-flex;align-items:center;justify-content:center;min-width:28px;height:28px;padding:0 8px;border-radius:99px;color:#fff;font-weight:700;font-size:.85rem;margin-inline-end:6px}
.chip{display:inline-block;padding:2px 10px;border-radius:99px;background:var(--gold-soft);font-size:.85rem;font-weight:600}
table{width:100%;border-collapse:collapse;font-size:.95rem}th,td{text-align:start;padding:9px 10px;border-bottom:1px solid var(--soft);vertical-align:top}th{color:var(--muted);font-size:.85rem}
.tw{overflow-x:auto}.num{font-variant-numeric:tabular-nums}
.en{direction:ltr;text-align:left;border-top:1px dashed var(--rule);margin-top:36px;padding-top:8px}
.en h1,.en h2,.en h3{font-family:"Readex Pro",system-ui,sans-serif}
.note{color:var(--muted);font-size:.88rem}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(170px,1fr));gap:8px}.grid a{display:block;padding:10px 12px;border-radius:12px;background:var(--surface);border:1px solid var(--rule);text-decoration:none;color:var(--ink)}
.grid small{display:block;color:var(--muted)}
footer{margin-top:40px;padding-top:14px;border-top:1px solid var(--rule);color:var(--muted);font-size:.85rem;display:flex;flex-wrap:wrap;gap:14px}
footer a{color:var(--muted)}
"""

def shell(title, desc, body, depth, path, site_url):
    up = "../" * depth
    canon = (site_url.rstrip("/") + "/" + path) if site_url else ""
    return f"""<!doctype html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>{E(title)}</title>
<meta name="description" content="{E(desc)}">
{f'<link rel="canonical" href="{E(canon)}">' if canon else ''}
<meta property="og:title" content="{E(title)}"><meta property="og:description" content="{E(desc)}"><meta property="og:type" content="website">
<meta name="theme-color" content="#00795C">
<link rel="icon" type="image/png" sizes="192x192" href="{up}icon-192.png">
<link rel="apple-touch-icon" href="{up}icon-180.png">
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans+Arabic:wght@400;600;700&family=Readex+Pro:wght@600;700&display=swap">
<style>{CSS}</style>
</head>
<body><div class="wrap">
<header class="top"><a class="brand" href="{up}"><span class="mark" aria-hidden="true"><i></i></span>مسار</a><span class="grow"></span>
<nav><a href="{up}station/">المحطات</a><a href="{up}advertise/">أعلن معنا</a></nav></header>
<main>{body}</main>
<footer><span>مسار تطبيق مستقل، غير تابع لقطار الرياض أو الهيئة الملكية لمدينة الرياض.</span>
<a href="{up}privacy/">الخصوصية</a><a href="{up}terms/">شروط الاستخدام</a><a href="{up}ad-terms/">شروط الإعلان</a></footer>
</div></body></html>
"""

def write(out, path, text):
    full = os.path.join(out, path, "index.html") if not path.endswith(".xml") else os.path.join(out, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w", encoding="utf-8") as f:
        f.write(text)

def qr_rows(text):
    """QR modules as strings of 0/1 (error correction M), via the encoder that ships with reportlab."""
    from reportlab.graphics.barcode import qrencoder as q
    for v in range(1, 15):
        try:
            c = q.QRCode(v, q.QRErrorCorrectLevel.M); c.addData(text); c.make()
            n = c.getModuleCount()
            return ["".join("1" if c.isDark(r, k) else "0" for k in range(n)) for r in range(n)]
        except Exception:
            continue
    raise ValueError("text too long for a QR code")

# ---------- routing (same model and costs as the app's engine; checked against it in tests) ----------
def travel_times(net):
    p = net["params"]; wait0, xfer, dwell = p["initialWaitMin"], p["transferMin"], p["dwellMin"]
    lines = {l["id"]: l for l in net["lines"]}
    hop = {l["id"]: l["lengthKm"] / (len(l["stations"]) - 1) / l["speedKmh"] * 60 + dwell for l in net["lines"]}
    at = {}
    for l in net["lines"]:
        for s in l["stations"]:
            at.setdefault(s, []).append(l["id"])
    def from_station(src):
        best, out, h = {}, {}, []
        for l in at[src]:
            best[(src, l)] = 0.0; heapq.heappush(h, (0.0, 0.0, 0, src, l))
        done = set()
        while h:
            s, t, x, sid, lid = heapq.heappop(h)
            if (sid, lid) in done: continue
            done.add((sid, lid))
            if sid not in out: out[sid] = (wait0 + t, x)
            st = lines[lid]["stations"]; i = st.index(sid); nb = []
            if i > 0: nb.append((st[i - 1], lid, hop[lid], 0))
            if i < len(st) - 1: nb.append((st[i + 1], lid, hop[lid], 0))
            nb += [(sid, o, xfer, 1) for o in at[sid] if o != lid]
            for nsid, nl, dt, dx in nb:
                if (nsid, nl) in done: continue
                t1, x1 = t + dt, x + dx; s1 = t1 + x1 * 0.001
                if s1 < best.get((nsid, nl), float("inf")):
                    best[(nsid, nl)] = s1; heapq.heappush(h, (s1, t1, x1, nsid, nl))
        return out
    return {s["id"]: from_station(s["id"]) for s in net["stations"]}, at

def build_pages(out, net, strings, ads, app):
    site = (app.get("siteUrl") or "").rstrip("/")
    S = {s["id"]: s for s in net["stations"]}
    lines = {l["id"]: l for l in net["lines"]}
    tr = strings["strings"]
    lname = lambda i, lang="ar": tr[f"line_{i}"][lang]
    times, at = travel_times(net)
    tier_of = lambda sid: next((k for k, v in ads["tiers"].items() if sid in v), "C")
    contact = app.get("contactEmail") or ""
    contact_ar = f'<a href="mailto:{E(contact)}">{E(contact)}</a>' if contact else f'<a href="{E(app.get("repoUrl", ""))}/issues/new/choose">صفحة البلاغات</a>'
    contact_en = f'<a href="mailto:{E(contact)}">{E(contact)}</a>' if contact else f'<a href="{E(app.get("repoUrl", ""))}/issues/new/choose">our issues page</a>'
    urls = []

    def page(path, title, desc, body):
        depth = path.count("/") + (1 if path else 0)
        write(out, path, shell(title, desc, body, depth, path + "/" if path else "", site))
        urls.append(path + "/" if path else "")

    # ---------- privacy ----------
    page("privacy", "سياسة الخصوصية | مسار", "ما يجمعه مسار وما لا يجمعه: لا تتبّع ولا تحليلات، والموقع يبقى على جهازك.", f"""
<h1>سياسة الخصوصية</h1><p class="lead">سارية من {EFFECTIVE}. باختصار: مسار لا يجمع بياناتك، ولا يتتبّعك، ولا يبيع شيئاً عنك.</p>
<h2>ما لا نجمعه</h2><ul><li>لا تسجيل إجباري، ولا تحليلات، ولا معرّفات إعلانية، ولا تتبّع عبر التطبيقات أو المواقع.</li>
<li><b>موقعك</b> يُستخدم على جهازك فقط لاختيار أقرب محطة، ولا يُحفظ ولا يُرسل إلينا.</li></ul>
<h2>ما يُحفظ وأين</h2><ul><li><b>الأماكن المحفوظة والمسارات وسجل الرحلات</b> تُحفظ على جهازك. في تطبيق iPhone تُزامَن عبر حساب iCloud الخاص بك فقط، ولا تمر بأي خادم لنا. سجل الرحلات يحفظ «محطة ← محطة» ولا يحفظ عناوين.</li>
<li><b>تسجيل الدخول بـ Apple</b> اختياري، ويُستخدم لتسمية الحساب فقط. يمكنك حذف كل بياناتك من «حسابي ← حذف حسابي وبياناتي».</li></ul>
<h2>الإعلانات</h2><ul><li>الإعلانات <b>سياقية</b>: تُختار حسب المحطة التي تتجه إليها، لا حسب هويتك.</li>
<li>يجلب التطبيق قائمة الإعلانات من موقعنا على GitHub Pages دون إرسال أي معلومة عنك. قد يسجّل مزوّد الاستضافة (GitHub) عنوان IP في سجلاته وفق سياسته.</li>
<li>عند فتح رابط معلن تنتقل إلى موقعه وتسري عليه سياسته. يحمل الرابط اسم الحملة والمحطة فقط، ولا شيء عنك.</li></ul>
<h2>خدمات خارجية</h2><p>اتجاهات المشي تفتح في خرائط Google أو Apple وتسري عليها سياستهما.</p>
<h2>بيانات المعلنين</h2><p>بيانات التواصل والمدفوعات الخاصة بالمعلنين تُستخدم للفوترة فقط، وتُحفظ مشفّرة.</p>
<h2>حقوقك والتواصل</h2><p>لك حق الوصول إلى بياناتك وتصحيحها وحذفها وفق نظام حماية البيانات الشخصية. للتواصل: {contact_ar}. أي تغيير في هذه السياسة يُنشر هنا مع تاريخ سريانه.</p>
<section class="en" lang="en"><h1>Privacy policy</h1><p class="lead">Effective {EFFECTIVE}. Masar does not collect, track or sell anything about you.</p>
<ul><li>No required sign-up, no analytics, no advertising identifiers, no cross-app tracking.</li>
<li>Your <b>location</b> is used on your device only to pick the nearest station; it is never stored or sent to us.</li>
<li>Saved places, routes and trip history stay on your device; on iPhone they sync only through your own iCloud. History keeps station pairs, never addresses.</li>
<li>Sign in with Apple is optional. Delete everything from Account → Delete my account and data.</li>
<li>Ads are <b>contextual</b>: chosen by the station you are heading to, not by who you are. The ad list is fetched from GitHub Pages with nothing about you; GitHub may log IP addresses under its own policy. Advertiser links carry the campaign and station only.</li>
<li>Walking directions open in Google or Apple Maps under their policies. Advertiser contact and payment data are used for billing only and kept encrypted.</li>
<li>You may access, correct or delete your data under the Saudi Personal Data Protection Law. Contact: {contact_en}.</li></ul></section>""")

    # ---------- terms ----------
    page("terms", "شروط الاستخدام | مسار", "شروط استخدام مسار لتخطيط رحلات مترو الرياض.", f"""
<h1>شروط الاستخدام</h1><p class="lead">سارية من {EFFECTIVE}.</p>
<ol><li><b>تطبيق مستقل:</b> مسار غير تابع لقطار الرياض أو للهيئة الملكية لمدينة الرياض أو لتطبيق درب. التذاكر تُشترى من القنوات الرسمية.</li>
<li><b>المعلومات تقديرية:</b> أزمنة الرحلات ومواقع بعض المحطات وأوقات التشغيل والأسعار تقديرية وقد تتغير. تحقّق من المصادر الرسمية قبل الرحلات المهمة.</li>
<li><b>المسؤولية:</b> يُقدَّم مسار «كما هو». لا نتحمّل مسؤولية تأخير أو فوات رحلة أو أي ضرر ينتج عن الاعتماد على تقديراته.</li>
<li><b>الإعلانات:</b> تصدر عن معلنين مستقلين يتحمّلون مسؤولية عروضهم. وجود إعلان لا يعني توصية منا.</li>
<li><b>الاستخدام المقبول:</b> لا يجوز إساءة استخدام الخدمة أو محاولة تعطيلها أو نسخ بياناتها لأغراض تجارية دون إذن.</li>
<li><b>الملكية:</b> اسم مسار وشعاره وتصميمه وشيفرته مملوكة لأصحابه.</li>
<li><b>التعديل:</b> قد نعدّل هذه الشروط وننشر التعديل هنا. استمرارك في الاستخدام يعني قبولك بها. تخضع هذه الشروط لأنظمة المملكة العربية السعودية.</li></ol>
<section class="en" lang="en"><h1>Terms of use</h1><ol><li>Masar is independent and not affiliated with Riyadh Metro, the Royal Commission for Riyadh City or the Darb app. Buy tickets through official channels.</li>
<li>Journey times, some station positions, hours and fares are estimates and may change; check official sources for important trips.</li>
<li>Masar is provided as is; we are not liable for delays, missed trips or losses from relying on its estimates.</li>
<li>Ads come from independent advertisers who are responsible for their offers; an ad is not an endorsement.</li>
<li>Do not misuse, disrupt or commercially scrape the service. The name, logo, design and code belong to their owners.</li>
<li>We may update these terms here; continued use means acceptance. Governed by the laws of the Kingdom of Saudi Arabia.</li></ol></section>""")

    # ---------- advertiser terms ----------
    page("ad-terms", "شروط الإعلان | مسار", "شروط الإعلان في مسار: المراجعة، الدفع، الظهور، والفئات الممنوعة.", f"""
<h1>شروط الإعلان</h1><p class="lead">سارية من {EFFECTIVE}، وتنطبق على كل حجز مساحة إعلانية في مسار.</p>
<h2>الحجز والمراجعة</h2><ul><li>يُؤكَّد الحجز بعد مراجعة الإعلان، ولمسار رفض أي إعلان أو إيقافه إذا خالف هذه الشروط.</li>
<li>يلتزم المعلن بأن يكون لديه سجل تجاري ساري المفعول، وبأي ترخيص يتطلبه نشاطه، وبصحة عرضه وأسعاره.</li></ul>
<h2>الدفع والظهور</h2><ul><li>الأسعار من جدول الأسعار المنشور، وتُعرض قبل ضريبة القيمة المضافة. تُضاف الضريبة متى وجبت.</li>
<li><b>الدفع يشتري أياماً:</b> كل دفعة تغطي حصتها من أيام الحجز بدءاً من تاريخ البدء. يظهر الإعلان حتى آخر يوم مدفوع، ويتوقف تلقائياً بعده إلى أن تصل الدفعة التالية.</li>
<li>لكل محطة عدد محدود من المساحات، ويتناوب الإعلانان المتشاركان في المحطة نفسها على الظهور يومياً.</li>
<li>الإلغاء قبل تاريخ البدء يعيد المبلغ المدفوع كاملاً. بعد البدء تُعاد قيمة الأيام المدفوعة التي لم تُعرض، إذا كان الإيقاف من جهة مسار.</li></ul>
<h2>القياس</h2><p>مسار لا يتتبّع الركاب، لذا لا يقدّم أرقام مشاهدة لكل شخص. نوفّر لك رابطاً موسوماً (UTM) يُظهر الزيارات في تحليلات موقعك، وننصح برمز خصم خاص بمسار لقياس المبيعات.</p>
<h2>الفئات الممنوعة</h2><p>التبغ ومنتجات التدخين الإلكتروني، والكحول، والقمار، والمحتوى غير اللائق، والأسلحة، والحملات السياسية أو الدينية، والمنتجات المالية أو الصحية غير المرخّصة، والسلع المقلّدة، وأي إعلان مضلل أو مخالف للأنظمة.</p>
<section class="en" lang="en"><h1>Advertiser terms</h1><ul><li>Bookings are confirmed after review; Masar may refuse or stop any ad that breaks these terms. Advertisers must hold a valid commercial registration and any licence their activity needs.</li>
<li>Prices follow the published rate card, before VAT; VAT is added where due.</li>
<li><b>Payment buys days:</b> each payment covers its share of the booked days from the start date; the ad shows up to the last paid day and stops by itself after it until the next payment arrives.</li>
<li>Stations have a limited number of slots; ads sharing a station rotate daily. Cancelling before the start date refunds in full; after it, paid days not shown are refunded when Masar stopped the ad.</li>
<li>Masar does not track riders, so it gives no per-person view counts; campaign links carry UTM tags for your own analytics.</li>
<li>Not accepted: tobacco and vaping, alcohol, gambling, adult content, weapons, political or religious campaigns, unlicensed financial or health products, counterfeits, misleading or unlawful ads.</li></ul></section>""")

    # ---------- media kit ----------
    rows = []
    for t, label in (("A", "مميزة: محطات التحويل والمطار"), ("B", "رئيسية: جامعات ونهايات خطوط ومراكز"), ("C", "حي: بقية المحطات")):
        n = sum(1 for s in net["stations"] if tier_of(s["id"]) == t)
        r = ads["rates"][t]
        four = round(r * 4 * (1 - next(d["off"] for d in ads["durations"] if d["weeks"] == 4)))
        rows.append(f'<tr><td><span class="chip">{t}</span> {E(label)}</td><td class="num">{n}</td><td class="num">{r:,}</td><td class="num">{four:,}</td></tr>')
    pk = ads["packages"]
    page("advertise", "أعلن قرب محطات مترو الرياض | مسار", "اظهر لمن يتجه إلى محطتك الآن. إعلان سياقي قرب محطات مترو الرياض من 400 ريال للأسبوع.", f"""
<h1>زبونك نازل في المحطة الجاية</h1>
<p class="lead">يظهر إعلانك في مسار لمن يخطط رحلته إلى المحطة القريبة منك، تحت محطة الوصول مباشرة، ومعه اتجاهات المشي إلى محلك.</p>
<div class="cta"><a class="btn" href="../#advertise">احجز مساحتك الآن</a><a class="btn ghost" href="../ad-terms/">شروط الإعلان</a></div>
<div class="card"><h2 style="margin-top:0">لماذا قرب المحطات؟</h2><ul>
<li>نقل مترو الرياض <b>60.7 مليون رحلة</b> في النصف الأول من 2026، أي نحو 335 ألف رحلة يومياً (<a href="https://www.arabnews.pk/saudi-arabia/saudi-rail-passenger-traffic-jumps-16-in-first-half-of-2026-2654162" rel="noopener">Arab News</a>).</li>
<li>أكثر المحطات ازدحاماً: قصر الحكم، وSTC، والمركز المالي، والمتحف الوطني (<a href="https://www.listmag.com/en/travel-stay/riyadh-metro-surpasses-milestone-of-200-million-rides-4279" rel="noopener">List Magazine</a>).</li>
<li>الإعلان يظهر في لحظة القرار: الراكب في طريقه إليك فعلاً.</li></ul></div>
<h2>كيف يظهر إعلانك</h2><ul><li>بطاقة معلَّمة بكلمة «إعلان» تحت محطة الوصول في نتيجة الرحلة، وفي صفحة المحطة.</li>
<li>اسم نشاطك وعرضك بالعربية والإنجليزية، مع أزرار «زيارة» و«اتصال» و«اتجاهات المشي» من المحطة إليك.</li>
<li>لا تتبّع للركاب: بيئة آمنة لعلامتك، وروابط موسومة تقيس بها الزيارات في تحليلاتك.</li></ul>
<h2>الأسعار</h2><div class="tw"><table><thead><tr><th>فئة المحطة</th><th>عدد المحطات</th><th>الأسبوع (ريال)</th><th>4 أسابيع (ريال)</th></tr></thead><tbody>{"".join(rows)}</tbody></table></div>
<p class="note">لكل مساحة في محطة واحدة، قبل ضريبة القيمة المضافة. خصم 20٪ لاثني عشر أسبوعاً، و{round(pk["line"]*100)}٪ لباقة المسار الكامل، و{round(pk["network"]*100)}٪ لباقة كل الشبكة. مساحتان فقط في كل محطة.</p>
<h2>كيف تحجز</h2><ol><li>افتح «أعلن معنا»، واختر المحطة والمدة، وشاهد السعر ومعاينة إعلانك فوراً.</li><li>أرسل الطلب، ونراجع الإعلان خلال يوم عمل.</li><li>ادفع كاملاً أو على أقساط. يظهر إعلانك للأيام المدفوعة.</li></ol>
<div class="cta"><a class="btn" href="../#advertise">ابدأ الحجز</a></div>
<section class="en" lang="en"><h1>Your customer is getting off at the next stop</h1>
<p>Masar shows your ad to riders planning a trip to the station near you, right under their arrival stop, with walking directions to your door. Riyadh Metro carried 60.7 million trips in the first half of 2026, about 335,000 a day. Prices start at SAR {ads["rates"]["C"]:,} a week per station before VAT, with discounts for 12 weeks, whole lines and the whole network. Two slots per station. No rider tracking; UTM-tagged links for your own analytics. <a href="../#advertise">Book a slot</a> · <a href="../ad-terms/">Advertiser terms</a></p></section>""")

    # ---------- stations ----------
    order = []
    for l in net["lines"]:
        for s in l["stations"]:
            if s not in order: order.append(s)
    def badge(i):
        c = lines[i]["colorLight"]; ink = "#1D1600" if i == 4 else "#fff"
        return f'<span class="badge" style="background:{c};color:{ink}" title="{E(lname(i))}">{i}</span>'
    station_times = {}
    for sid in order:
        s = S[sid]; ls = at[sid]
        neigh = []
        for i in ls:
            st = lines[i]["stations"]; k = st.index(sid)
            prev = st[k - 1] if k > 0 else None; nxt = st[k + 1] if k < len(st) - 1 else None
            parts = [f'<a href="../{p}/">{E(S[p]["ar"])}</a>' for p in (prev, nxt) if p]
            neigh.append(f'<li>{badge(i)} {E(lname(i))}: {" · ".join(parts)}</li>')
        trows, tt = [], {}
        for d in LANDMARKS:
            if d == sid: continue
            m, x = times[sid][d]; tt[d] = [round(m, 3), x]
            xs = "بدون تحويل" if x == 0 else ("تحويل واحد" if x == 1 else f"{x} تحويلات")
            trows.append(f'<tr><td><a href="../{d}/">{E(S[d]["ar"])}</a></td><td class="num">{round(m)} دقيقة</td><td>{xs}</td><td><a href="../../?from={sid}&amp;to={d}">افتح الرحلة</a></td></tr>')
        station_times[sid] = tt
        tier = tier_of(sid)
        approx = s.get("geo") not in ("official", "ref")
        maps = f'https://www.google.com/maps/dir/?api=1&destination={s["lat"]:.6f},{s["lng"]:.6f}&travelmode=walking'
        inter = f' <span class="chip">محطة تحويل</span>' if len(ls) > 1 else ""
        page(f"station/{sid}", f"محطة {s['ar']} – مترو الرياض | مسار",
             f"محطة {s['ar']} ({s['en']}) على {('، '.join(lname(i) for i in ls))}. أسرع طريق إليها ومنها، والمحطات المجاورة، والزمن إلى أهم الوجهات.", f"""
<p class="note"><a href="../">كل المحطات</a></p>
<h1>محطة {E(s['ar'])}{inter}</h1><p class="lead" lang="en" dir="ltr" style="text-align:right">{E(s['en'])} station · Riyadh Metro</p>
<p>{"".join(badge(i) for i in ls)} {E("، ".join(lname(i) for i in ls))}</p>
<div class="cta"><a class="btn" href="../../?to={sid}">رحلة إلى هنا من موقعك</a><a class="btn ghost" href="../../?from={sid}">ابدأ رحلة من هنا</a><a class="btn ghost" href="{E(maps)}" rel="noopener">اتجاهات المشي إلى المحطة</a></div>
{('<p class="note">موقع المحطة على الخريطة تقديري.</p>' if approx else '')}
<h2>المحطات المجاورة</h2><ul>{"".join(neigh)}</ul>
<h2>الزمن إلى أهم الوجهات</h2><div class="tw"><table><thead><tr><th>الوجهة</th><th>الزمن التقريبي</th><th>التحويلات</th><th></th></tr></thead><tbody>{"".join(trows)}</tbody></table></div>
<p class="note">يشمل الانتظار الأول ({net["params"]["initialWaitMin"]} دقائق) و{net["params"]["transferMin"]} دقائق لكل تحويل. الأزمنة تقديرية.</p>
<div class="card"><b>نشاطك قرب محطة {E(s['ar'])}؟</b> اعرضه لمن يصل إلى هنا، من {ads["rates"][tier]:,} ريال للأسبوع. <a href="../../#advertise:{sid}">احجز مساحة هنا</a></div>""")
    groups = []
    for l in net["lines"]:
        items = "".join(f'<a href="{sid}/">{E(S[sid]["ar"])}<small lang="en">{E(S[sid]["en"])}</small></a>' for sid in l["stations"])
        groups.append(f'<h2>{badge(l["id"])} {E(lname(l["id"]))} · {len(l["stations"])} محطة</h2><div class="grid">{items}</div>')
    page("station", "محطات مترو الرياض | مسار", "كل محطات مترو الرياض الـ 83 على المسارات الستة، مع أسرع طريق إلى كل محطة.", f"""
<h1>محطات مترو الرياض</h1><p class="lead">{len(order)} محطة على ستة مسارات. اختر محطة لترى المحطات المجاورة والزمن إلى أهم الوجهات، وافتح الرحلة في مسار بضغطة.</p>
{"".join(groups)}""")

    # ---------- printable QR stickers (A6), one per station for partner shops ----------
    if site:
        link = lambda sid: f"{site}/?utm_source=qr&utm_medium=sticker" + (f"&utm_content={sid}" if sid else "")
        codes = {"": qr_rows(link(""))}
        codes.update({sid: qr_rows(link(sid)) for sid in order})
        opts = "".join(f'<option value="{sid}">{E(S[sid]["ar"])}</option>' for sid in order)
        write(out, "sticker", STICKER.replace("/*CODES*/null", json.dumps(codes, separators=(",", ":"))).replace("<!--OPTS-->", opts))
    # ---------- sitemap ----------
    if site:
        locs = "".join(f"<url><loc>{E(site)}/{E(u)}</loc></url>" for u in [""] + urls)
        with open(os.path.join(out, "sitemap.xml"), "w", encoding="utf-8") as f:
            f.write(f'<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">{locs}</urlset>\n')
    with open(os.path.join(out, "station-times.json"), "w", encoding="utf-8") as f:
        json.dump(station_times, f, separators=(",", ":"))
    return len(urls)

STICKER = """<!doctype html>
<html lang="ar" dir="rtl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex"><title>ملصق مسار للطباعة</title>
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans+Arabic:wght@400;600;700&family=Readex+Pro:wght@600;700&display=swap">
<style>
@page{size:105mm 148mm;margin:0}
*{box-sizing:border-box}body{margin:0;background:#E3ECE8;font-family:"IBM Plex Sans Arabic",system-ui,sans-serif;color:#0B1A22}
.tools{max-width:420px;margin:16px auto;padding:0 16px;display:flex;gap:8px;flex-wrap:wrap;align-items:center}
.tools select,.tools button{font:inherit;padding:8px 12px;border-radius:10px;border:1px solid #D3DED9;background:#fff}
.tools button{background:#00795C;color:#fff;border:0;font-weight:700}
.sheet{width:105mm;height:148mm;margin:0 auto 24px;background:#fff;display:flex;flex-direction:column;align-items:center;justify-content:space-between;padding:10mm 9mm 8mm;box-shadow:0 8px 30px rgba(0,0,0,.12);position:relative;overflow:hidden}
.band{position:absolute;inset:0 0 auto;height:8mm;background:#00795C}.band i{position:absolute;top:2.5mm;left:9mm;width:3mm;height:3mm;border-radius:50%;background:#F6B53C}
.brand{margin-top:6mm;font-family:"Readex Pro",sans-serif;font-weight:700;font-size:13mm;line-height:1;color:#00795C}
h1{font-family:"Readex Pro",sans-serif;font-size:7mm;line-height:1.25;margin:2mm 0 0;text-align:center}
.qr{width:52mm;height:52mm}
.sub{font-size:3.6mm;text-align:center;margin:0;color:#51635D}
.st{font-size:4mm;font-weight:700;background:#FCEFD2;border-radius:99px;padding:1mm 4mm}
.langs{font-size:2.8mm;color:#51635D;text-align:center;direction:ltr}
@media print{body{background:#fff}.tools{display:none}.sheet{box-shadow:none;margin:0}}
</style></head><body>
<div class="tools"><label for="st">المحطة القريبة:</label><select id="st"><option value="">بدون محطة</option><!--OPTS--></select><button type="button" onclick="print()">اطبع</button></div>
<div class="sheet"><div class="band"><i></i></div>
<div class="brand">مسار</div>
<h1>خطّط رحلتك بالمترو<br>بضغطة واحدة</h1>
<svg class="qr" id="qr" viewBox="0 0 10 10" role="img" aria-label="رمز QR لفتح مسار"></svg>
<span class="st" id="stname" hidden></span>
<p class="sub">امسح الرمز: أسرع رحلة من مكانك إلى أي محطة في الرياض</p>
<div class="langs">Riyadh Metro trips · العربية · English · اردو · हिन्दी · বাংলা · Filipino · Indonesia · 中文</div></div>
<script>
const CODES = /*CODES*/null, names = {};
document.querySelectorAll("#st option").forEach(o => names[o.value] = o.textContent);
function draw(id){
  const rows = CODES[id] || CODES[""], n = rows.length, q = 4, svg = document.getElementById("qr");
  let d = "";
  rows.forEach((r, y) => { for(let x = 0; x < n; x++) if(r[x] === "1") d += "M" + (x + q) + " " + (y + q) + "h1v1h-1z"; });
  svg.setAttribute("viewBox", "0 0 " + (n + 2 * q) + " " + (n + 2 * q));
  svg.innerHTML = '<rect width="100%" height="100%" fill="#fff"/><path d="' + d + '" fill="#0B1A22" shape-rendering="crispEdges"/>';
  const s = document.getElementById("stname"); s.hidden = !id; s.textContent = id ? "قرب محطة " + names[id] : "";
}
document.getElementById("st").onchange = e => draw(e.target.value);
const pre = new URLSearchParams(location.search).get("station"); if(pre && CODES[pre]){ document.getElementById("st").value = pre; draw(pre); } else draw("");
</script></body></html>
"""
