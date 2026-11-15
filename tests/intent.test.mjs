// The on-device intent engine: `node --test tests/intent.test.mjs` (run tools/build.py first).
// It may only re-order the ads a station has sold. These tests pin that promise: relevance stays inside
// fixed bounds, an ad that is not booked or not paid never appears, and the rider's controls work.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

const html = readFileSync(new URL("../dist/index.html", import.meta.url), "utf8");
function slice(from, to) {
  const a = html.indexOf(from), b = html.indexOf(to, a);
  assert.ok(a > 0 && b > a, `marker not found: ${from} … ${to}`);
  return html.slice(a, b);
}
const camp = (id, category, extra = {}) => Object.assign({ id, name: { en: id }, title: { en: id }, category, stations: ["qasrhokm"],
  start: "2026-01-01", end: "2027-12-31", paidUntil: "2027-12-31", weight: 1, status: "active" }, extra);
const ADS = {
  slotsPerStation: 2, graceDays: 0,
  context: {
    momentCats: { morning: ["cafe"], evening: ["food"] }, weekendCats: ["fun"], placeCats: { work: ["cafe"] },
    kindOf: { qasrhokm: ["heritage"] }, kindCats: { heritage: ["shop"] },
  },
  campaigns: [
    camp("cafe", "cafe", { lat: 24.6301, lng: 46.7149 }),          // north-west of Qasr Al Hokm; the grill is south-east
    camp("grill", "food", { lat: 24.6240, lng: 46.7230, moments: ["evening", "night"] }),
    camp("unpaid", "cafe", { paidUntil: null, stations: ["owd"] }),
  ],
};
const store = {};
const ctx = vm.createContext({ navigator: { languages: ["en"] }, Intl, Math, JSON, Map, Set, Object, Array, Number, String, Date,
  localStorage: { getItem: k => store[k] ?? null, setItem: (k, v) => { store[k] = v; } } });
vm.runInContext(
  slice("const NET = ", "/* ---------- fares ---------- */") +
  slice("const isApprox", "function setHere(") +
  "\nconst MAX_WALK = 2500;\nconst ADS = " + JSON.stringify(ADS) + ";\n" +
  slice("const todayISO", "const loc = ") +
  "\nglobalThis.api = { ADS, S, st, taste, momentOf, adContext, relevance, adsAt, offersNear, tasteNote, tasteClear, tasteLoad, bearing, angDiff, noteFix, curHeading, addDays };", ctx);
const E = ctx.api;
const [cafe, grill] = E.ADS.campaigns;
const share = (cx, id = "cafe", days = 400) => {
  let n = 0;
  for (let i = 0, d = "2026-02-01"; i < days; i++, d = E.addDays(d, 1)) if (E.adsAt("qasrhokm", d, 1, cx)[0].id === id) n++;
  return n / days;
};

test("the day splits into five moments in Riyadh time", () => {
  assert.deepEqual([0, 299, 300, 659, 660, 899, 900, 1079, 1080, 1319, 1320, 1439, 1440 + 480].map(m => E.momentOf(m)),
    ["night", "night", "morning", "morning", "midday", "midday", "afternoon", "afternoon", "evening", "evening", "night", "night", "morning"]);
});

test("bearings and the direction of travel", () => {
  const p = { lat: 24.7, lng: 46.7 };
  assert.ok(E.angDiff(E.bearing(p, { lat: 24.71, lng: 46.7 }), 0) < 0.01);      // north
  assert.ok(E.angDiff(E.bearing(p, { lat: 24.7, lng: 46.71 }), 90) < 0.01);     // east
  assert.ok(E.angDiff(E.bearing(p, { lat: 24.69, lng: 46.7 }), 180) < 0.01);    // south
  assert.equal(E.angDiff(350, 10), 20);
  assert.equal(E.curHeading(), null);
  E.noteFix(p); E.noteFix({ lat: 24.70001, lng: 46.7 });                        // 1 m: GPS jitter, not movement
  assert.equal(E.curHeading(), null);
  E.noteFix({ lat: 24.7, lng: 46.701 });                                        // ~100 m east
  assert.ok(E.angDiff(E.curHeading(), 90) < 1);
});

test("with no context the rotation is the plain paid one", () => {
  for (const d of ["2026-03-01", "2026-03-02", "2026-03-03"])
    assert.deepEqual([...E.adsAt("qasrhokm", d, 5).map(c => c.id)].sort(), ["cafe", "grill"]);
  assert.equal(E.relevance(cafe, null).m, 1);
});

test("the moment of arrival moves the share, inside fixed bounds", () => {
  const morning = E.adContext("qasrhokm", 8 * 60, "Mon"), evening = E.adContext("qasrhokm", 20 * 60, "Mon");
  assert.equal(morning.moment, "morning");
  assert.deepEqual([...morning.kinds], ["heritage"]);
  assert.ok(Math.abs(E.relevance(cafe, morning).m - 1.3) < 1e-9);               // a café in the morning
  assert.ok(Math.abs(E.relevance(grill, morning).m - 0.7) < 1e-9);              // the advertiser asked for evenings
  assert.ok(Math.abs(E.relevance(grill, evening).m - 1.6) < 1e-9);
  assert.deepEqual([...E.relevance(grill, evening).why], ["time"]);
  const am = share(morning), pm = share(evening);
  assert.ok(am > 0.55 && am < 0.8, `café share in the morning ${am}`);
  assert.ok(pm > 0.25 && pm < 0.5, `café share in the evening ${pm}`);          // out of favour, never shut out
});

test("relevance never leaves 0.5–3, whatever the rider did", () => {
  E.taste.cats.cafe = 99; E.taste.cats.food = -99;
  const cx = { moment: "morning", weekend: true, place: "work", kinds: ["heritage"] };
  assert.ok(E.relevance(cafe, cx).m <= 3);
  assert.ok(E.relevance(grill, cx).m >= 0.5);
  E.tasteClear();
});

test("taste is learned from taps, capped, and cleared on request", () => {
  const cx = E.adContext("qasrhokm", 13 * 60, "Mon");                           // midday: no rule in this book
  const before = E.relevance(cafe, cx).m;
  for (let i = 0; i < 10; i++) E.tasteNote(cafe, 1);
  assert.equal(E.taste.cats.cafe, 3);
  assert.ok(Math.abs(E.relevance(cafe, cx).m - before * 1.5) < 1e-9);
  assert.ok(E.relevance(cafe, cx).why.includes("taste"));
  assert.ok(share(cx) > 0.6);
  E.taste.on = false;                                                            // switched off: taps count for nothing
  assert.equal(E.relevance(cafe, cx).m, before);
  E.tasteNote(grill, 1);
  assert.equal(E.taste.cats.food, undefined);
  E.taste.on = true;
  E.tasteClear();
  assert.equal(E.relevance(cafe, cx).m, before);
  assert.deepEqual(JSON.parse(store["masar.taste.v1"]), { on: true, cats: {}, hide: [] });
});

test("«ليس لي» hides that ad for this rider and counts against its category", () => {
  const cx = E.adContext("qasrhokm", 13 * 60, "Mon");
  E.tasteNote(grill, -1.5, true);
  assert.deepEqual([...E.adsAt("qasrhokm", "2026-03-01", 5, cx).map(c => c.id)], ["cafe"]);
  assert.equal(E.adsAt("qasrhokm", "2026-03-01", 5).length, 2);                  // the booking itself is untouched
  assert.equal(E.taste.cats.food, -1.5);
  E.tasteLoad();                                                                 // survives a reload from this device's storage
  assert.deepEqual([...E.taste.hide], ["grill"]);
  E.tasteClear();
});

test("a saved work stop favours the categories set for work, only while personalising is on", () => {
  E.st.places = [{ id: "p", kind: "work", label: "", station: "qasrhokm" }];
  const cx = E.adContext("qasrhokm", 13 * 60, "Mon");
  assert.equal(cx.place, "work");
  assert.ok(Math.abs(E.relevance(cafe, cx).m - 1.2) < 1e-9);
  E.taste.on = false;
  assert.equal(E.adContext("qasrhokm", 13 * 60, "Mon").place, "");
  E.taste.on = true; E.st.places = [];
});

test("an ad that is not paid for is never shown, however relevant", () => {
  for (let i = 0; i < 10; i++) E.tasteNote(cafe, 1);
  assert.equal(E.adsAt("owd", "2026-03-01", 5, E.adContext("owd", 8 * 60, "Mon")).length, 0);
  E.tasteClear();
});

test("offers around the rider: within walking reach, and those ahead come first", () => {
  const here = { lat: E.S.qasrhokm.lat, lng: E.S.qasrhokm.lng };
  const all = E.offersNear(here, null, "2026-03-01");
  assert.deepEqual([...all.map(o => o.c.id)].sort(), ["cafe", "grill"]);
  assert.ok(all.every(o => o.m <= 2500 && !o.ahead));
  const toCafe = E.bearing(here, cafe), toGrill = E.bearing(here, grill);
  assert.ok(E.angDiff(toCafe, toGrill) > 120);                                   // they lie in opposite directions
  assert.equal(E.offersNear(here, toCafe, "2026-03-01")[0].c.id, "cafe");
  assert.ok(E.offersNear(here, toCafe, "2026-03-01")[0].why.includes("way"));
  const south = E.offersNear(here, toGrill, "2026-03-01");
  assert.equal(south.find(o => o.c.id === "grill").ahead, true);
  assert.equal(south.find(o => o.c.id === "cafe").ahead, false);
  assert.equal(E.offersNear({ lat: 24.95, lng: 46.70 }, null, "2026-03-01").length, 0);   // far from every booked station
});
