// Ad selection, availability and pricing for the web app: `node --test tests/ads.test.mjs` (run tools/build.py first).
// Uses the sample ad book in tests/fixtures, expanded by the same build code the site uses.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import vm from "node:vm";

const root = new URL("..", import.meta.url).pathname;
const html = readFileSync(new URL("../dist/index.html", import.meta.url), "utf8");
function slice(from, to) {
  const a = html.indexOf(from), b = html.indexOf(to, a);
  assert.ok(a > 0 && b > a, `marker not found: ${from} … ${to}`);
  return html.slice(a, b);
}
const feed = execFileSync("python3", ["-c", `
import json, sys; sys.path.insert(0, "tools"); import build
load = build.load
print(json.dumps(build.ads_feed(load("network.json"), json.load(open("tests/fixtures/ads.sample.json")), load("strings.json"), load("app.json"))))
`], { cwd: root, encoding: "utf8" });

const ctx = vm.createContext({ navigator: { languages: ["en"] }, Intl, Math, JSON, Map, Set, Object, Array, Number, String, Date });
vm.runInContext(
  slice("const NET = ", "/* ---------- fares ---------- */") +
  "\nconst ADS = " + feed + ";\n" +
  slice("const todayISO", "const loc = ") +
  "\nglobalThis.api = { ADS, LBY, hash01, adsAt, freeSlots, quote, tierOf, addDays, todayISO };", ctx);
const E = ctx.api;

test("rotation hash matches the iOS app (AdsTests.testHashMatchesTheWebApp)", () => {
  assert.equal(E.hash01("demo-qasr-1|qasrhokm|2026-10-20"), 0.95095232955645770);
  assert.equal(E.hash01("مقهى|kafd|2027-01-01"), 0.57876523805316538);
});

test("line campaigns are expanded to every station on the line", () => {
  const c = E.ADS.campaigns.find(x => x.id === "demo-line4");
  assert.deepEqual([...c.stations], [...E.LBY[4].stations]);
});

test("only campaigns running that day at that station are shown", () => {
  assert.equal(E.adsAt("qasrhokm", "2026-09-30", 5).length, 0);
  assert.deepEqual([...E.adsAt("qasrhokm", "2026-10-05", 5).map(c => c.id)], ["demo-qasr-1"]);
  assert.equal(E.adsAt("qasrhokm", "2026-10-20", 5).length, 2);
  assert.equal(E.adsAt("qasrhokm", "2027-01-01", 5).length, 0);
  assert.equal(E.adsAt("malaz", "2026-10-20", 5).length, 0);
  assert.deepEqual([...E.adsAt("t12", "2026-10-20", 5).map(c => c.id)], ["demo-line4"]);
});

test("rotation is stable within a day and follows the weights", () => {
  assert.equal(E.adsAt("qasrhokm", "2026-10-20")[0].id, E.adsAt("qasrhokm", "2026-10-20")[0].id);
  let heavy = 0, n = 0;
  for (let d = "2026-10-10"; d <= "2026-10-31"; d = E.addDays(d, 1)) {
    n++; if (E.adsAt("qasrhokm", d)[0].id === "demo-qasr-2") heavy++;   // weight 2 vs 1
  }
  assert.ok(heavy / n > 0.45 && heavy / n < 0.9, `weight-2 share ${heavy}/${n}`);
});

test("an ad shows only while paid for; suspended, unpaid and cancelled ads never show", () => {
  assert.deepEqual([...E.adsAt("qasrhokm", "2026-10-31", 5).map(c => c.id)].sort(), ["demo-qasr-1", "demo-qasr-2"]);
  assert.deepEqual([...E.adsAt("qasrhokm", "2026-11-01", 5).map(c => c.id)], ["demo-qasr-1"]);   // paid to Oct 31
  assert.equal(E.adsAt("malaz", "2026-11-01", 5).length, 0);                                     // suspended
  assert.equal(E.adsAt("owd", "2026-11-01", 5).length, 0);                                       // never paid
  assert.ok(!E.ADS.campaigns.some(c => c.id === "demo-cancelled"));                              // dropped at build
  E.ADS.graceDays = 2;
  assert.equal(E.adsAt("qasrhokm", "2026-11-02", 5).length, 2);
  assert.equal(E.adsAt("qasrhokm", "2026-11-03", 5).length, 1);
  E.ADS.graceDays = 0;
});

test("free slots account for every overlapping booking", () => {
  assert.equal(E.freeSlots("malaz", "2026-10-01", "2026-12-31"), 1);   // a suspended booking still holds its slot
  assert.equal(E.freeSlots("malaz", "2027-01-01", "2027-01-07"), 2);
  assert.equal(E.freeSlots("qasrhokm", "2026-10-01", "2026-10-05"), 1);
  assert.equal(E.freeSlots("qasrhokm", "2026-10-01", "2026-10-15"), 0);   // second booking starts on the 10th
  assert.equal(E.freeSlots("qasrhokm", "2027-01-01", "2027-01-28"), 2);
});

test("prices follow the rate card, durations and packages", () => {
  const A = E.ADS.rates.A, C = E.ADS.rates.C;
  assert.equal(E.tierOf("kafd"), "A"); assert.equal(E.tierOf("malaz"), "B"); assert.equal(E.tierOf("owd"), "C");
  assert.equal(E.quote("station", "owd", 1, "2027-01-03").net, C);
  assert.equal(E.quote("station", "kafd", 4, "2027-01-03").net, Math.round(A * 4 * 0.9));
  assert.equal(E.quote("station", "kafd", 12, "2027-01-03").net, Math.round(A * 12 * 0.8));
  const line = E.quote("line", 5, 1, "2027-01-03");
  const sum = E.LBY[5].stations.reduce((s, id) => s + E.ADS.rates[E.tierOf(id)], 0);
  assert.equal(line.net, Math.round(sum * 0.65));
  assert.equal(line.total, Math.round(line.net * 1.15));
  assert.equal(E.quote("network", null, 1, "2027-01-03").sts.length, 83);
  assert.equal(E.quote("station", "kafd", 4, "2027-01-03").end, "2027-01-30");
});
