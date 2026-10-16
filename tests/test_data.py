"""Data integrity tests: run with `python3 -m unittest discover -s tests`."""
import json
import os
import re
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load(*parts):
    with open(os.path.join(ROOT, *parts), encoding="utf-8") as f:
        return json.load(f)


class NetworkTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.net = load("data", "network.json")
        cls.ids = [s["id"] for s in cls.net["stations"]]

    def test_station_ids_are_unique(self):
        self.assertEqual(len(self.ids), len(set(self.ids)))

    def test_lines_reference_known_stations_once(self):
        known = set(self.ids)
        for line in self.net["lines"]:
            self.assertTrue(set(line["stations"]) <= known, line["id"])
            self.assertEqual(len(line["stations"]), len(set(line["stations"])), line["id"])

    def test_every_station_is_served(self):
        served = {s for line in self.net["lines"] for s in line["stations"]}
        self.assertEqual(served, set(self.ids))

    def test_published_line_sizes(self):
        sizes = {l["id"]: len(l["stations"]) for l in self.net["lines"]}
        self.assertEqual(sizes, {1: 25, 2: 15, 3: 22, 4: 9, 5: 12, 6: 11})

    def test_coordinates_are_inside_riyadh(self):
        for s in self.net["stations"]:
            self.assertIn(s.get("geo"), {"est", "ref", "official"}, s["id"])
            self.assertTrue(24.3 < s["lat"] < 25.2 and 46.3 < s["lng"] < 47.2, s["id"])

    def test_line_colours_are_hex(self):
        for line in self.net["lines"]:
            for key in ("colorLight", "colorDark"):
                self.assertRegex(line[key], r"^#[0-9A-Fa-f]{6}$")

    def test_network_is_connected(self):
        adj = {i: set() for i in self.ids}
        for line in self.net["lines"]:
            for a, b in zip(line["stations"], line["stations"][1:]):
                adj[a].add(b)
                adj[b].add(a)
        seen, todo = set(), [self.ids[0]]
        while todo:
            n = todo.pop()
            if n not in seen:
                seen.add(n)
                todo.extend(adj[n] - seen)
        self.assertEqual(seen, set(self.ids))


class StringsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.s = load("data", "strings.json")
        cls.langs = [l["code"] for l in cls.s["languages"]]

    def test_every_string_is_translated(self):
        optional = {"model_body"}           # long technical text, English fallback is acceptable
        missing = [(k, c) for k, v in self.s["strings"].items() if k not in optional for c in self.langs if not v.get(c)]
        self.assertEqual(missing, [])

    def test_placeholders_match_english(self):
        ph = re.compile(r"\{(\w+)\}")
        for key, tr in self.s["strings"].items():
            want = set(ph.findall(tr["en"]))
            for code, text in tr.items():
                self.assertEqual(set(ph.findall(text)), want, f"{key}/{code}")

    def test_plurals_have_other_form(self):
        for key, tr in self.s["plurals"].items():
            for code in self.langs:
                self.assertIn("other", tr[code], f"{key}/{code}")


class FaresTests(unittest.TestCase):
    def test_fares_are_consistent(self):
        f = load("data", "fares.json")
        ids = {t["id"] for t in f["tickets"]}
        self.assertTrue(set(f["discount"]["appliesTo"]) <= ids)
        for t in f["tickets"]:
            self.assertGreater(t["standard"], 0)
            if t.get("first") is not None:
                self.assertGreater(t["first"], t["standard"])
        self.assertTrue(0 < f["discount"]["rate"] < 1)


class AdsTests(unittest.TestCase):
    """The ad book (data/ads.json) and the build's validation of it."""
    @classmethod
    def setUpClass(cls):
        import sys
        sys.path.insert(0, os.path.join(ROOT, "tools"))
        import build
        cls.build = build
        cls.net, cls.strings, cls.app = load("data", "network.json"), load("data", "strings.json"), load("data", "app.json")
        cls.ads = load("data", "ads.json")

    def feed(self, book):
        return self.build.ads_feed(self.net, json.loads(json.dumps(book)), self.strings, self.app)

    def book(self, *campaigns):
        b = json.loads(json.dumps(self.ads)); b["campaigns"] = list(campaigns); return b

    def camp(self, **kw):
        c = {"id": "x", "name": "اسم", "category": "cafe", "title": "عرض", "start": "2027-01-01", "end": "2027-01-31", "stations": ["malaz"]}
        c.update(kw); return c

    def test_live_book_and_sample_are_valid(self):
        self.feed(self.ads)
        f = self.feed(load("tests", "fixtures", "ads.sample.json"))
        self.assertEqual(len(f["campaigns"]), 5)          # the cancelled one is left out of the feed
        self.assertTrue(all("status" in c for c in f["campaigns"]))

    def test_rate_card_is_sane(self):
        r = self.ads["rates"]
        self.assertTrue(r["A"] > r["B"] > r["C"] > 0)
        self.assertTrue(all(0 <= d["off"] < 1 for d in self.ads["durations"]))
        self.assertTrue(all(0 <= v < 1 for v in self.ads["packages"].values()))
        self.assertGreaterEqual(self.ads["slotsPerStation"], 1)

    def test_targets_expand_to_stations(self):
        f = self.feed(self.book(self.camp(id="l", stations=[], lines=[5]), self.camp(id="n", stations=[], network=True,
                                                                                  start="2028-01-01", end="2028-01-02")))
        by = {c["id"]: c for c in f["campaigns"]}
        self.assertEqual(len(by["l"]["stations"]), 12)
        self.assertEqual(len(by["n"]["stations"]), 83)
        self.assertEqual(by["l"]["name"], {"ar": "اسم"})

    def test_bad_campaigns_are_rejected(self):
        bad = [self.camp(stations=["nowhere"]), self.camp(category="casino"), self.camp(start="2027-02-01"),
               self.camp(url="http://insecure.example"), self.camp(lat=21.5, lng=39.2), self.camp(start="1/1/2027"),
               self.camp(title={"xx": "?"}), self.camp(weight=0), self.camp(stations=[]),
               self.camp(status="paused"), self.camp(paidUntil="31/01/2027")]
        for c in bad:
            with self.assertRaises(SystemExit, msg=c):
                self.feed(self.book(c))
        with self.assertRaises(SystemExit):
            self.feed(self.book(self.camp(id="a"), self.camp(id="a", start="2027-03-01", end="2027-03-02")))

    def test_a_station_is_never_overbooked(self):
        cap = self.ads["slotsPerStation"]
        ok = [self.camp(id=f"c{i}") for i in range(cap)]
        self.feed(self.book(*ok))
        with self.assertRaises(SystemExit):
            self.feed(self.book(*ok, self.camp(id="extra", start="2027-01-20", end="2027-02-20")))
        # a cancelled booking frees its slot
        self.feed(self.book(*ok, self.camp(id="gone", status="cancelled")))
        # back-to-back bookings share a slot
        self.feed(self.book(*ok, self.camp(id="next", start="2027-02-01", end="2027-02-28")))


class LedgerTests(unittest.TestCase):
    def test_ledger_in_the_repo_is_only_ciphertext(self):
        path = os.path.join(ROOT, "data", "billing.enc")
        if not os.path.exists(path):
            self.skipTest("no ledger yet")
        f = load("data", "billing.enc")
        self.assertEqual(set(f), {"v", "alg", "kdf", "iter", "salt", "iv", "ct"})
        self.assertEqual(f["alg"], "AES-256-GCM")
        self.assertGreaterEqual(f["iter"], 100000)
        raw = open(path, encoding="utf-8").read()
        for word in ("advertiser", "payments", "phone"):
            self.assertNotIn(word, raw)


if __name__ == "__main__":
    unittest.main()
