#!/usr/bin/env python3
"""Masar build: one source of truth (data/*.json) -> web prototype + iOS resources.

Usage:  python3 tools/build.py
Outputs:
  dist/index.html                          web prototype with data inlined
  ios/Masar/Resources/network.json         network graph for the iOS app
  ios/Masar/Resources/fares.json           fares and service hours
  ios/Masar/Resources/Localizable.xcstrings  String Catalog (8 languages, plurals)
  ios/Masar/Resources/ads.json             bundled copy of the ad feed (the app refreshes it from the site)
  dist/site/ads.json                       live ad feed served by GitHub Pages
"""
import json, math, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
D = lambda *p: os.path.join(ROOT, *p)
IOS_LANG = {"zh": "zh-Hans"}          # web code -> Apple localization id

def load(name):
    with open(D("data", name), encoding="utf-8") as f:
        return json.load(f)

def check(net, strings):
    ids = {s["id"] for s in net["stations"]}
    for line in net["lines"]:
        missing = [s for s in line["stations"] if s not in ids]
        if missing:
            sys.exit(f"line {line['id']} references unknown stations: {missing}")
    codes = [l["code"] for l in strings["languages"]]
    gaps = [(k, c) for k, v in strings["strings"].items() for c in codes if c not in v and k != "model_body"]
    if gaps:
        print("warning: untranslated (falls back to English):", gaps[:10], "…" if len(gaps) > 10 else "")

CATEGORIES = {"food", "cafe", "shop", "health", "services", "hotel", "fun"}
DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")

def _metres(a, b):
    r = math.pi / 180
    h = math.sin((b[0]-a[0])*r/2)**2 + math.cos(a[0]*r)*math.cos(b[0]*r)*math.sin((b[1]-a[1])*r/2)**2
    return 2 * 6371000 * math.asin(math.sqrt(h))

def ads_feed(net, ads, strings, app):
    """Validate data/ads.json and expand it into the feed the apps read.
    Campaigns may target stations, whole lines or the network; the feed always lists stations."""
    ids = {s["id"] for s in net["stations"]}
    by_id = {s["id"]: s for s in net["stations"]}
    line_st = {l["id"]: l["stations"] for l in net["lines"]}
    codes = {l["code"] for l in strings["languages"]}
    err = lambda m: sys.exit("ads.json: " + m)
    tier_of = {}
    for tier, lst in ads["tiers"].items():
        if tier not in ads["rates"]:
            err(f"tier {tier} has no rate")
        for sid in lst:
            if sid not in ids: err(f"tier {tier}: unknown station {sid}")
            if sid in tier_of: err(f"station {sid} is in two tiers")
            tier_of[sid] = tier
    if "C" not in ads["rates"]:
        err("rates need a default tier C")
    seen, out = set(), []
    for c in ads.get("campaigns", []):
        cid = c.get("id") or err("campaign without id")
        if cid in seen: err(f"duplicate campaign id {cid}")
        seen.add(cid)
        if c.get("network"):
            sts = sorted(ids)
        else:
            sts = list(c.get("stations", []))
            for lid in c.get("lines", []):
                if lid not in line_st: err(f"{cid}: unknown line {lid}")
                sts += line_st[lid]
            sts = list(dict.fromkeys(sts))
        if not sts: err(f"{cid}: target stations, lines or the network")
        bad = [x for x in sts if x not in ids]
        if bad: err(f"{cid}: unknown stations {bad}")
        if c.get("category") not in CATEGORIES: err(f"{cid}: category must be one of {sorted(CATEGORIES)}")
        for k in ("start", "end"):
            if not DATE.match(str(c.get(k, ""))): err(f"{cid}: {k} must be YYYY-MM-DD")
        if c["start"] > c["end"]: err(f"{cid}: start is after end")
        for k in ("name", "title", "body"):
            v = c.get(k)
            if v is None and k == "body": continue
            if isinstance(v, str): c[k] = v = {"ar": v}
            if not isinstance(v, dict) or not v or not set(v) <= codes: err(f"{cid}: {k} must be text or {{lang: text}}")
        if c.get("url") and not str(c["url"]).startswith("https://"): err(f"{cid}: url must start with https://")
        if c.get("phone") and not re.fullmatch(r"\+?[0-9 ]{7,16}", str(c["phone"])): err(f"{cid}: phone looks wrong")
        if "lat" in c or "lng" in c:
            lat, lng = c.get("lat"), c.get("lng")
            if not (isinstance(lat, (int, float)) and isinstance(lng, (int, float)) and 24.3 < lat < 25.3 and 46.2 < lng < 47.3):
                err(f"{cid}: lat/lng must be inside Riyadh")
            far = [x for x in sts if _metres((lat, lng), (by_id[x]["lat"], by_id[x]["lng"])) > 2500]
            if far and len(sts) < 4:
                print(f"warning: {cid} is more than 2.5 km from {far}")
        w = c.get("weight", 1)
        if not isinstance(w, (int, float)) or w <= 0: err(f"{cid}: weight must be > 0")
        item = {k: c[k] for k in ("id", "name", "category", "title", "body", "url", "phone", "lat", "lng", "start", "end") if c.get(k) is not None}
        item["stations"] = sts; item["weight"] = w
        out.append(item)
    # no station may be sold more often than it has slots on any day
    cap = ads["slotsPerStation"]
    for sid in ids:
        mine = [c for c in out if sid in c["stations"]]
        for c in mine:
            day = c["start"]
            n = sum(1 for o in mine if o["start"] <= day <= o["end"])
            if n > cap: err(f"station {sid} is overbooked on {day} ({n} campaigns, {cap} slots)")
    feed = {k: ads[k] for k in ("contact", "currency", "vat", "slotsPerStation", "rates", "durations", "packages")}
    feed.update({"version": 1, "tierOf": tier_of,
                 "issueUrl": app.get("repoUrl", "").rstrip("/") + "/issues/new" if app.get("repoUrl") else "",
                 "feedUrl": (app.get("siteUrl") or "").rstrip("/") + "/ads.json" if app.get("siteUrl") else "",
                 "campaigns": out})
    return feed

def web(net, fares, strings):
    src = open(D("web", "app.html"), encoding="utf-8").read()
    dump = lambda o: json.dumps(o, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/")
    app = load("app.json") if os.path.exists(D("data", "app.json")) else {"siteUrl": ""}
    for tag, obj in (("NET", net), ("FARES", fares), ("I18N", strings), ("APP", app), ("ADS", ADS)):
        token = f"/*{tag}*/null"
        if token not in src:
            sys.exit(f"placeholder {token} missing in web/app.html")
        src = src.replace(token, dump(obj))
    os.makedirs(D("dist"), exist_ok=True)
    with open(D("dist", "index.html"), "w", encoding="utf-8") as f:
        f.write(src)
    site(src)

def xcstrings(strings):
    unit = lambda v: {"stringUnit": {"state": "translated", "value": v}}
    out = {"sourceLanguage": "en", "version": "1.0", "strings": {}}
    for key, tr in strings["strings"].items():
        locs = {}
        for code, val in tr.items():
            # named {placeholders} stay literal; L10n.swift substitutes them at runtime
            locs[IOS_LANG.get(code, code)] = unit(val)
        out["strings"][key] = {"extractionState": "manual", "localizations": locs}
    for key, tr in strings["plurals"].items():
        locs = {}
        for code, forms in tr.items():
            variations = {cat: unit(txt.replace("{n}", "%lld")) for cat, txt in forms.items()}
            if "other" not in variations:
                sys.exit(f"plural {key}/{code} needs an 'other' form")
            locs[IOS_LANG.get(code, code)] = {"variations": {"plural": variations}}
        out["strings"][key] = {"extractionState": "manual", "localizations": locs}
    return out

def ios(net, fares, strings):
    res = D("ios", "Masar", "Resources")
    os.makedirs(res, exist_ok=True)
    for name, obj in (("network.json", net), ("fares.json", fares), ("ads.json", ADS)):
        with open(os.path.join(res, name), "w", encoding="utf-8") as f:
            json.dump(obj, f, ensure_ascii=False, indent=1)
    with open(os.path.join(res, "Localizable.xcstrings"), "w", encoding="utf-8") as f:
        json.dump(xcstrings(strings), f, ensure_ascii=False, indent=2)
    # Home-screen name: مسار in Arabic/Urdu, Masar elsewhere
    unit = lambda v: {"stringUnit": {"state": "translated", "value": v}}
    names = {IOS_LANG.get(c, c): unit(v) for c, v in strings["strings"]["app_name"].items()}
    info = {"sourceLanguage": "en", "version": "1.0", "strings": {
        "CFBundleDisplayName": {"extractionState": "manual", "localizations": names},
        "CFBundleName": {"extractionState": "manual", "localizations": names},
        "NSLocationWhenInUseUsageDescription": {"extractionState": "manual", "localizations":
            {IOS_LANG.get(c, c): unit(v) for c, v in strings["strings"]["loc_reason"].items()}}}}
    with open(os.path.join(res, "InfoPlist.xcstrings"), "w", encoding="utf-8") as f:
        json.dump(info, f, ensure_ascii=False, indent=2)

SITE_HEAD = """<!doctype html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="theme-color" content="#00795C">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="default">
<meta name="apple-mobile-web-app-title" content="مسار">
<link rel="apple-touch-icon" href="icon-180.png">
<link rel="icon" type="image/png" sizes="192x192" href="icon-192.png">
<link rel="manifest" href="manifest.webmanifest">
<style>:root{color-scheme:light;padding-top:env(safe-area-inset-top,0px);padding-bottom:env(safe-area-inset-bottom,0px)}body{margin:0;font:14px/1.5 system-ui,sans-serif}img{max-width:100%}[hidden]{display:none!important}</style>
</head>
<body>
"""

def site(page):
    """dist/site: the same app as a standalone HTTPS-ready site. Outside Claude the browser can grant
    location, so the app opens already located; it can also be added to the Home Screen."""
    out = D("dist", "site"); os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, "index.html"), "w", encoding="utf-8") as f:
        f.write(SITE_HEAD + page + "\n</body>\n</html>\n")
    manifest = {"name": "مسار – رحلات مترو الرياض", "short_name": "مسار", "lang": "ar", "dir": "rtl",
                "start_url": "./", "display": "standalone", "background_color": "#EEF3F1", "theme_color": "#00795C",
                "icons": [{"src": "icon-192.png", "sizes": "192x192", "type": "image/png"},
                          {"src": "icon-512.png", "sizes": "512x512", "type": "image/png", "purpose": "any maskable"}]}
    with open(os.path.join(out, "manifest.webmanifest"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=1)
    with open(os.path.join(out, "ads.json"), "w", encoding="utf-8") as f:
        json.dump(ADS, f, ensure_ascii=False, separators=(",", ":"))
    src = D("brand", "png", "AppIcon.png")
    try:
        from PIL import Image
        icon = Image.open(src).convert("RGB")
        for n in (180, 192, 512):
            icon.resize((n, n), Image.LANCZOS).save(os.path.join(out, f"icon-{n}.png"))
    except Exception as e:
        print("note: icons not generated:", e)

if __name__ == "__main__":
    net, fares, strings = load("network.json"), load("fares.json"), load("strings.json")
    check(net, strings)
    # MASAR_ADS=path/to/ads.json builds with another ad book (previews and tests); the default is data/ads.json
    ads_src = json.load(open(os.environ["MASAR_ADS"], encoding="utf-8")) if os.environ.get("MASAR_ADS") else load("ads.json")
    ADS = ads_feed(net, ads_src, strings, load("app.json") if os.path.exists(D("data", "app.json")) else {})
    web(net, fares, strings)
    if os.path.isdir(D("ios")):
        ios(net, fares, strings)
    print("built:", len(net["stations"]), "stations,", len(net["lines"]), "lines,",
          len(strings["strings"]) + len(strings["plurals"]), "strings x", len(strings["languages"]), "languages,", len(ADS["campaigns"]), "ad campaigns")
