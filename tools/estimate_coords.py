#!/usr/bin/env python3
"""Give every station a latitude/longitude until official coordinates are imported.

Method: each line is pinned at a few anchor stations; stations between two anchors are
spaced evenly along the straight segment joining them (lines follow near-straight arterials:
Olaya/Batha, King Abdullah Rd, Madinah Rd/Prince Saad Rd, King Abdulaziz Rd).

Quality flags written to data/network.json:
  "ref"  coordinates published for that place (Wikipedia: Qasr Al Hokm station, Riyadh
         railway station; King Khalid airport reference point for T1-2)
  "est"  estimated from the anchors above and the corridor geometry — expect 0.2–1 km error
  "official"  written later by tools/import_rcrc.py from the RCRC open-data download

Run:  python3 tools/estimate_coords.py   (only fills stations that are not "official")
"""
import json, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NET = os.path.join(ROOT, "data", "network.json")

REF = {  # published coordinates
    "qasrhokm": (24.6287, 46.7162),   # en.wikipedia.org/wiki/Qasr_Al-Hukm_metro_station
    "railway": (24.6504, 46.7406),    # en.wikipedia.org/wiki/Riyadh_railway_station
    "t12": (24.9578, 46.6989),        # en.wikipedia.org/wiki/King_Khalid_International_Airport (airport point)
}

# line id -> {index on the line: (lat, lng)}; everything not in REF is an estimate.
ANCHORS = {
    1: {0: (24.8150, 46.6215), 2: (24.7668, 46.6435), 6: (24.7353, 46.6612), 11: (24.6848, 46.6880),
        15: (24.6470, 46.7120), 17: REF["qasrhokm"], 21: (24.5905, 46.7385), 24: (24.5585, 46.7780)},
    2: {0: (24.7205, 46.6305), 4: (24.7353, 46.6612), 7: (24.7445, 46.6975), 9: (24.7553, 46.7232),
        11: (24.7700, 46.7640), 13: (24.7830, 46.8110), 14: (24.7880, 46.8350)},
    3: {0: (24.5715, 46.5440), 3: (24.6010, 46.6230), 5: (24.6185, 46.6620), 9: REF["qasrhokm"],
        14: REF["railway"], 19: (24.7045, 46.8255), 21: (24.7210, 46.8960)},
    4: {0: (24.7668, 46.6435), 1: (24.7845, 46.6575), 2: (24.7930, 46.6740), 3: (24.8000, 46.6935),
        4: (24.8465, 46.7255), 5: (24.8820, 46.7140), 6: (24.9300, 46.7120), 7: (24.9545, 46.7035), 8: REF["t12"]},
    5: {0: (24.7445, 46.6975), 11: (24.6470, 46.7120)},
    6: {0: (24.7668, 46.6435), 1: (24.7845, 46.6575), 2: (24.7930, 46.6740), 3: (24.8000, 46.6935),
        4: (24.7895, 46.7255), 5: (24.7850, 46.7480), 6: (24.7700, 46.7640), 7: (24.7560, 46.7790),
        8: (24.7390, 46.7930), 9: (24.7225, 46.8100), 10: (24.7045, 46.8255)},
}

def estimate(net):
    est = {}
    for line in net["lines"]:
        a = ANCHORS[line["id"]]
        keys = sorted(a)
        assert keys[0] == 0 and keys[-1] == len(line["stations"]) - 1, f"line {line['id']} anchors must cover both ends"
        for k0, k1 in zip(keys, keys[1:]):
            (la0, ln0), (la1, ln1) = a[k0], a[k1]
            for i in range(k0, k1 + 1):
                f = (i - k0) / (k1 - k0)
                sid = line["stations"][i]
                est.setdefault(sid, (la0 + (la1 - la0) * f, ln0 + (ln1 - ln0) * f))
    return est

if __name__ == "__main__":
    net = json.load(open(NET, encoding="utf-8"))
    est = estimate(net)
    n = 0
    for s in net["stations"]:
        if s.get("geo") == "official":
            continue
        lat, lng = REF.get(s["id"], est[s["id"]])
        s["lat"], s["lng"] = round(lat, 5), round(lng, 5)
        s["geo"] = "ref" if s["id"] in REF else "est"
        n += 1
    net["geoNote"] = "lat/lng: 'ref' published, 'est' estimated (0.2–1 km), 'official' RCRC open data"
    json.dump(net, open(NET, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(f"coordinates written for {n} stations")
