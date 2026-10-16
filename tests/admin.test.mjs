// Billing rules of the admin control page: `node --test tests/admin.test.mjs` (run tools/build.py first).
// Money buys days: payments decide paidUntil, and the apps hide an ad after its paid days.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

const html = readFileSync(new URL("../dist/site/admin/index.html", import.meta.url), "utf8");
const app = readFileSync(new URL("../dist/index.html", import.meta.url), "utf8");
function cut(src, from, to) {
  const a = src.indexOf(from), b = src.indexOf(to, a);
  assert.ok(a > 0 && b > a, `marker not found: ${from} … ${to}`);
  return src.slice(a, b);
}
const ctx = vm.createContext({ Intl, Math, JSON, Object, Array, Number, String, Date, Set, Map, Promise, Uint8Array,
  crypto: globalThis.crypto, TextEncoder, TextDecoder, btoa, atob });
vm.runInContext(cut(html, "const NET = ", "/* ---------- billing ---------- */") + cut(html, "/* ---------- billing ---------- */", "/* ---------- github ---------- */") +
  "\nglobalThis.api = { isoAdd, isoDiff, quoteFor, schedule, paidOf, paidUntilFor, nextDue, dueByToday, statusOf, applyBilling, kpis, overbooked, waNumber, parseLatLng, seal, unseal, stationsOf };", ctx);
const E = ctx.api;
const book0 = JSON.parse(readFileSync(new URL("../data/ads.json", import.meta.url), "utf8"));
const camp = (o) => Object.assign({ id: "c1", name: { ar: "x" }, title: { ar: "y" }, category: "cafe", stations: ["kafd"], start: "2026-11-01", end: "2026-11-28", status: "active" }, o);
const inv = (o) => Object.assign({ advertiser: { name: "a", phone: "" }, net: 4320, vat: 648, total: 4968, plan: "full", payments: [] }, o);
const pay = (...a) => a.map((amount, i) => ({ id: "p" + i, date: "2026-11-01", amount, method: "transfer" }));

test("nothing paid: no paidUntil, the ad waits", () => {
  const c = camp(), i = inv();
  assert.equal(E.paidUntilFor(i, c), null);
  assert.equal(E.statusOf(c, i, "2026-10-20", 0), "awaiting");
  assert.equal(E.statusOf(c, i, "2026-11-01", 0), "overdue");
});

test("paying in full covers the whole booking", () => {
  const c = camp(), i = inv({ payments: pay(4968) });
  assert.equal(E.paidUntilFor(i, c), "2026-11-28");
  c.paidUntil = E.paidUntilFor(i, c);
  assert.equal(E.statusOf(c, i, "2026-10-25", 0), "scheduled");
  assert.equal(E.statusOf(c, i, "2026-11-15", 0), "live");
  assert.equal(E.statusOf(c, i, "2026-11-29", 0), "ended");
});

test("partial payments buy days pro rata, and the ad hides the day after", () => {
  const c = camp(), i = inv({ payments: pay(1242) });               // a quarter of 4968 → 7 of 28 days
  assert.equal(E.paidUntilFor(i, c), "2026-11-07");
  c.paidUntil = "2026-11-07";
  assert.equal(E.statusOf(c, i, "2026-11-05", 0), "due_soon");
  assert.equal(E.statusOf(c, i, "2026-11-08", 0), "overdue");
  assert.equal(E.statusOf(c, i, "2026-11-08", 2), "due_soon");     // inside grace days
  assert.equal(E.statusOf(c, i, "2026-11-10", 2), "overdue");
  i.payments = pay(1242, 1242);
  assert.equal(E.paidUntilFor(i, c), "2026-11-14");
  assert.equal(E.paidUntilFor(inv({ payments: pay(1241.99) }), c), "2026-11-06");   // a cent short is a day short
});

test("instalment plans split the total and track what is due", () => {
  const c = camp(), w = inv({ plan: "weekly" });
  const s = E.schedule(w, c);
  assert.equal(s.length, 4);
  assert.deepEqual([...s.map(x => x.due)], ["2026-11-01", "2026-11-08", "2026-11-15", "2026-11-22"]);
  assert.equal(Math.round(s.reduce((a, x) => a + x.amount, 0) * 100) / 100, 4968);
  assert.equal(E.dueByToday(w, c, "2026-11-09"), 2484);
  w.payments = pay(1242);
  assert.deepEqual({ ...E.nextDue(w, c) }, { due: "2026-11-08", amount: 1242 });
  const m = E.schedule(inv({ plan: "monthly", total: 1000 }), camp({ end: "2027-01-23" }));   // 84 days → 3 × 28
  assert.equal(m.length, 3);
  assert.equal(Math.round(m.reduce((a, x) => a + x.amount, 0) * 100) / 100, 1000);
  assert.equal(E.schedule(inv({ plan: "monthly", total: 100 }), camp({ end: "2026-11-01" })).length, 1);
});

test("suspension and cancellation override payment", () => {
  const i = inv({ payments: pay(4968) });
  assert.equal(E.statusOf(camp({ status: "suspended", paidUntil: "2026-11-28" }), i, "2026-11-10", 0), "suspended");
  assert.equal(E.statusOf(camp({ status: "cancelled", paidUntil: "2026-11-28" }), i, "2026-11-10", 0), "cancelled");
  assert.equal(E.statusOf(camp({ paidUntil: "2026-11-07" }), inv({ payments: pay(1242) }), "2026-12-01", 0), "ended_due");
});

test("applyBilling writes paidUntil from the ledger and the public app agrees", () => {
  const book = JSON.parse(JSON.stringify(book0));
  book.campaigns = [camp({ id: "a" }), camp({ id: "b", stations: ["malaz"] }), camp({ id: "manual", stations: ["owd"], paidUntil: "2026-11-28" })];
  const ledger = { invoices: { a: inv({ payments: pay(1242) }), b: inv() } };
  E.applyBilling(book, ledger);
  assert.equal(book.campaigns[0].paidUntil, "2026-11-07");
  assert.ok(!("paidUntil" in book.campaigns[1]));
  assert.equal(book.campaigns[2].paidUntil, "2026-11-28");          // no invoice: left as written
  // the same rule the public app uses to show or hide
  const isShown = new Function("addDays", "ADS", "return " + cut(app, "const isShown = ", ";\n").slice("const isShown = ".length))(E.isoAdd, { graceDays: 0 });
  assert.equal(isShown(book.campaigns[0], "2026-11-07"), true);
  assert.equal(isShown(book.campaigns[0], "2026-11-08"), false);
  assert.equal(isShown(book.campaigns[1], "2026-11-02"), false);
});

test("quotes match the public price card", () => {
  const q = E.quoteFor(book0, { kind: "station", id: "kafd" }, 4);
  assert.equal(q.net, Math.round(book0.rates.A * 4 * 0.9));
  assert.equal(q.total, q.net + Math.round(q.net * book0.vat));
  assert.equal(E.quoteFor(book0, { kind: "station", id: "kafd" }, 6).net, Math.round(book0.rates.A * 6 * 0.9));   // best discount ≤ 6 weeks
  assert.equal(E.quoteFor(book0, { kind: "network" }, 1).sts.length, 83);
});

test("bookings cannot exceed the slots at any station", () => {
  const book = JSON.parse(JSON.stringify(book0));
  book.campaigns = [camp({ id: "a" }), camp({ id: "b" })];
  assert.deepEqual([...E.overbooked(book, camp({ id: "c" }))], ["kafd"]);
  assert.equal(E.overbooked(book, camp({ id: "c", start: "2026-11-29", end: "2026-12-05" })).length, 0);
  assert.equal(E.overbooked(book, camp({ id: "a" }), "a").length, 0);            // editing itself
  book.campaigns[1].status = "cancelled";
  assert.equal(E.overbooked(book, camp({ id: "c" })).length, 0);
  assert.ok(E.overbooked(book, camp({ id: "c", stations: [], lines: [4] })).length === 0);
});

test("ledger encryption round-trips and rejects a wrong passphrase", async () => {
  const data = { v: 1, invoices: { a: inv({ advertiser: { name: "مقهى الديرة", phone: "0500000000" } }) } };
  const sealed = await E.seal(data, "correct horse battery", 1000);
  assert.ok(!sealed.includes("الديرة") && !sealed.includes("0500000000"));
  assert.deepEqual(JSON.parse(JSON.stringify(await E.unseal(sealed, "correct horse battery"))), data);
  await assert.rejects(E.unseal(sealed, "wrong passphrase"));
});

test("helpers: WhatsApp numbers and map links", () => {
  assert.equal(E.waNumber("0551234567"), "966551234567");
  assert.equal(E.waNumber("+966 55 123 4567"), "966551234567");
  assert.equal(E.waNumber("00966551234567"), "966551234567");
  assert.equal(E.parseLatLng("https://www.google.com/maps/@24.6301,46.7149,17z").lat, 24.6301);
  assert.equal(E.parseLatLng("٢٤٫٦٣٠١، ٤٦٫٧١٤٩").lng, 46.7149);
  assert.equal(E.parseLatLng("21.5, 39.2"), null);
});
