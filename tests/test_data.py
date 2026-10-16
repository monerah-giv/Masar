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


if __name__ == "__main__":
    unittest.main()
