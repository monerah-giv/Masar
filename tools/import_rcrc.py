#!/usr/bin/env python3
"""Replace estimated station coordinates with the official ones from the RCRC open-data portal.

1. In a browser open
   https://opendata.rcrc.gov.sa/explore/assets/metro-stations-in-riyadh-by-metro-line-and-station-type-2024/
   and download the file (CSV, XLSX saved as CSV, or GeoJSON). Coordinates are in the download only.
2. python3 tools/import_rcrc.py path/to/download.csv      (or .geojson / .json)
3. python3 tools/build.py

Matching: by English or Arabic station name after normalisation; an interchange station appears
once per line in the download and the positions are averaged. Unmatched rows are listed so you can
add them to ALIASES below. Nothing is written unless at least half the stations match.
"""
import csv, json, os, re, sys, unicodedata

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NET = os.path.join(ROOT, "data", "network.json")

ALIASES = {  # normalised name in the download -> station id
    "king fahd sports city": "kfstadium", "king fahad stadium": "kfstadium",
    "dr sulaiman al habib": "habib", "sab": "sabb", "sab bank": "sabb",
    "airport t1 2": "t12", "airport t3 4": "t34", "airport terminals 1 2": "t12", "airport terminals 3 4": "t34",
    "mewa": "mewa", "mew a": "mewa", "railway": "railway", "railway station": "railway",
}

def norm(s):
    s = unicodedata.normalize("NFKD", str(s)).lower()
    s = re.sub(r"[ً-ْـ]", "", s)
    s = re.sub(r"[أإآ]", "ا", s).replace("ة", "ه").replace("ى", "ي")
    s = re.sub(r"\b(station|metro|محطه|محطة)\b", " ", s)
    s = re.sub(r"[^\w]+", " ", s)
    return re.sub(r"\s+", " ", s).strip()

def rows(path):
    if path.lower().endswith((".geojson", ".json")):
        data = json.load(open(path, encoding="utf-8-sig"))
        feats = data.get("features", data if isinstance(data, list) else [])
        for f in feats:
            props = dict(f.get("properties", f))
            geom = f.get("geometry") or {}
            if geom.get("type") == "Point":
                props["_lng"], props["_lat"] = geom["coordinates"][:2]
            yield props
    else:
        with open(path, encoding="utf-8-sig", newline="") as fh:
            sample = fh.read(4096); fh.seek(0)
            dialect = csv.Sniffer().sniff(sample, delimiters=",;\t")
            yield from csv.DictReader(fh, dialect=dialect)

def coords(r):
    if "_lat" in r: return float(r["_lat"]), float(r["_lng"])
    keys = {k.lower().strip(): k for k in r}
    for la, ln in (("latitude", "longitude"), ("lat", "lon"), ("lat", "lng"), ("y", "x")):
        if la in keys and ln in keys and r[keys[la]] and r[keys[ln]]:
            return float(r[keys[la]]), float(r[keys[ln]])
    for k in keys:  # "geo_point_2d" / "geopoint" as "lat, lng"
        if "geo" in k and isinstance(r[keys[k]], str) and "," in r[keys[k]]:
            a, b = (float(x) for x in r[keys[k]].split(",")[:2])
            return a, b
    return None

def main(path):
    net = json.load(open(NET, encoding="utf-8"))
    index = {}
    for s in net["stations"]:
        for name in (s["en"], s["ar"], s.get("alias", "")):
            if name: index.setdefault(norm(name), s["id"])
    index.update(ALIASES)
    found, unmatched = {}, []
    for r in rows(path):
        c = coords(r)
        if not c: continue
        names = [v for k, v in r.items() if isinstance(v, str) and "name" in k.lower()]
        sid = next((index[norm(n)] for n in names if norm(n) in index), None)
        if sid: found.setdefault(sid, []).append(c)
        else: unmatched.append(" / ".join(names) or str(r)[:80])
    if len(found) < len(net["stations"]) / 2:
        sys.exit(f"only {len(found)} of {len(net['stations'])} stations matched — check the file; nothing written")
    for s in net["stations"]:
        if s["id"] in found:
            pts = found[s["id"]]
            s["lat"] = round(sum(p[0] for p in pts) / len(pts), 6)
            s["lng"] = round(sum(p[1] for p in pts) / len(pts), 6)
            s["geo"] = "official"
    json.dump(net, open(NET, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    missing = [s["id"] for s in net["stations"] if s["id"] not in found]
    print(f"official coordinates for {len(found)} stations")
    if missing: print("still estimated:", ", ".join(missing))
    if unmatched: print("unmatched rows (add to ALIASES):", *sorted(set(unmatched)), sep="\n  ")

if __name__ == "__main__":
    if len(sys.argv) != 2: sys.exit(__doc__)
    main(sys.argv[1])
