// Routing-engine tests for the web app: `node --test tests/engine.test.mjs`  (run tools/build.py first).
// The app ships as one self-contained HTML file, so the tests lift its engine out of dist/index.html
// by fixed markers and run it in an isolated VM context.
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
const code = [
  slice("const NET = ", "/* ---------- fares ---------- */"),       // data, state, i18n, time, routing
  slice("const isApprox", "function setHere("),                      // geography + location parsing
  slice("const MAX_WALK", "function refreshPlan(){"),                // door-to-door planner
].join("\n");

const ctx = vm.createContext({ navigator: { languages: ["en"] }, Intl, Math, JSON, Map, Set, Object, Array, Number, String });
vm.runInContext(code + `
  /* reference oracle: the original linear-scan Dijkstra */
  function oracle(from, to, mode){
    const cost = (tm, x) => mode === "few" ? x*10000 + tm : tm + x*0.001;
    const dist = new Map(), done = new Set();
    at[from].forEach(l => dist.set(from+"@"+l, {t:0, x:0}));
    for(;;){
      let best = null, bc = Infinity;
      for(const [k,v] of dist){ if(!done.has(k)){ const c = cost(v.t, v.x); if(c < bc){ bc = c; best = k; } } }
      if(best === null) return null;
      done.add(best);
      const [sid, ls] = best.split("@"), lid = +ls, cur = dist.get(best);
      if(sid === to) return cur;
      const L = LBY[lid], i = L.stations.indexOf(sid), nb = [];
      if(i > 0) nb.push([L.stations[i-1]+"@"+lid, L.hop, 0]);
      if(i < L.stations.length-1) nb.push([L.stations[i+1]+"@"+lid, L.hop, 0]);
      at[sid].forEach(o => { if(o !== lid) nb.push([sid+"@"+o, XFER, 1]); });
      for(const [k, dt, dx] of nb){ if(done.has(k)) continue; const n = {t: cur.t+dt, x: cur.x+dx}, old = dist.get(k);
        if(!old || cost(n.t, n.x) < cost(old.t, old.x)) dist.set(k, n); }
    }
  }
  globalThis.api = { NET, st, route, search, planTrip, nearestTo, walkMin, parseLoc, oracle, WAIT0, XFER, MAX_WALK,
                     setLang: c => { lang = c; PR = new Intl.PluralRules(LOC[c]); }, t, pl, minTxt, xferTxt };
`, ctx);
const E = ctx.api;
const ids = E.NET.stations.map(s => s.id);

test("every pair of stations is reachable in both modes", () => {
  for (const mode of ["fast", "few"])
    for (const a of ids) for (const b of ids)
      if (a !== b) assert.ok(E.route(a, b, mode), `${a} → ${b} (${mode})`);
});

test("heap search matches the reference Dijkstra on all 13,612 pairs", () => {
  for (const mode of ["fast", "few"])
    for (const a of ids) for (const b of ids) {
      if (a === b) continue;
      const r = E.route(a, b, mode), o = E.oracle(a, b, mode);
      assert.ok(Math.abs(r.total - (E.WAIT0 + o.t)) < 1e-9, `${a} → ${b} ${mode}`);
      assert.equal(r.xfers, o.x, `${a} → ${b} ${mode}`);
    }
});

test("fewest-changes never has more changes than fastest", () => {
  for (const a of ids) for (const b of ids)
    if (a !== b) assert.ok(E.route(a, b, "few").xfers <= E.route(a, b, "fast").xfers);
});

test("door-to-door single pass equals trying every nearby station", () => {
  let seed = 7; const rnd = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648;
  for (let n = 0; n < 300; n++) {
    E.st.here = { lat: 24.57 + rnd() * 0.33, lng: 46.56 + rnd() * 0.33 };
    E.st.fromHere = true;
    for (const mode of ["fast", "few"]) {
      E.st.to = ids[Math.floor(rnd() * ids.length)];
      const one = E.planTrip(mode);
      const near = E.nearestTo(E.st.here, 4), reach = near.filter(x => x.m <= E.MAX_WALK);
      let best = null;
      for (const c of (reach.length ? reach : near.slice(0, 1))) {
        const r = c.id === E.st.to ? null : E.route(c.id, E.st.to, mode);
        if (c.id !== E.st.to && !r) continue;
        const tr = { total: E.walkMin(c.m) + (r ? r.total : 0), xfers: r ? r.xfers : 0 };
        if (!best || (mode === "few" ? (tr.xfers < best.xfers || (tr.xfers === best.xfers && tr.total < best.total)) : tr.total < best.total)) best = tr;
      }
      assert.ok(Math.abs(one.total - best.total) < 1e-9 && one.xfers === best.xfers, JSON.stringify(E.st.here));
    }
  }
});

test("location parsing accepts links, coordinates and Arabic digits; rejects places outside Riyadh", () => {
  const ok = [
    ["https://www.google.com/maps/@24.6900,46.6850,15z", 24.69],
    ["https://www.google.com/maps/place/x/@24.1,46.1,17z/data=!3m1!4b1!4m6!3m5!1s0!8m2!3d24.6287!4d46.7162", 24.6287],
    ["https://maps.google.com/?q=24.7136,46.6753", 24.7136],
    ["24.7136, 46.6753", 24.7136],
    ["٢٤٫٧١٣٦، ٤٦٫٦٧٥٣", 24.7136],
    ["46.6753, 24.7136", 24.7136],
  ];
  for (const [s, lat] of ok) assert.ok(Math.abs(E.parseLoc(s).lat - lat) < 1e-6, s);
  for (const s of ["hello", "51.5, -0.12", "", "24.7"]) assert.equal(E.parseLoc(s), null, s);
});

test("plurals resolve in every language", () => {
  for (const code of ["ar", "en", "ur", "hi", "bn", "fil", "id", "zh"]) {
    E.setLang(code);
    for (const n of [0, 1, 2, 3, 11, 100]) {
      assert.match(E.pl("p_min", n), /\S/);
      assert.doesNotMatch(E.pl("p_stop", n), /\{n\}/);
    }
  }
  E.setLang("ar");
  assert.equal(E.minTxt(2), "دقيقتان");
  assert.equal(E.xferTxt(0), "بدون تحويل");
});
