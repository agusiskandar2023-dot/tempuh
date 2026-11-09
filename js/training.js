// Program latihan FM JAKIM 2027 (sama dengan lib/domain/training_plan.dart di aplikasi).
// Catatan sesi tersimpan di Neon (training_log), tersinkron dengan HP.

const E = (km, d = 'Santai, bisa ngobrol') => ({ t: `Lari mudah ${km} km`, d, km });
const M = (min, d = 'Lari 3 mnt, jalan 1 mnt') => ({ t: `Lari-jalan ${min} menit`, d, km: Math.round(min / 10 * 10) / 10 });
const W = (min) => ({ t: `Jalan cepat ${min} menit`, d: 'Atau lari sangat ringan', km: Math.round(min / 11 * 10) / 10 });
const L = (km, d = 'Pelan, boleh lari-jalan') => ({ t: `Long run ${km} km`, d, km, long: true });
const Q = (km, t, d) => ({ t, d, km });
const RACE = { t: 'LOMBA · 42,195 km', d: 'Start 04.00 · lari-jalan dari awal', km: 42.2, long: true, race: true };

const PHASES = [
  { name: 'Bangun kembali', from: 1, to: 6 },
  { name: 'Dasar aerobik', from: 7, to: 14 },
  { name: 'Kekuatan & tempo', from: 15, to: 22 },
  { name: 'Puncak', from: 23, to: 28 },
  { name: 'Tapering', from: 29, to: 31 },
];
const PLAN = [
  { s: [M(30), M(30), W(45), L(6, 'Lari 3 mnt, jalan 1 mnt')], n: 'Tujuannya membiasakan lagi. Jangan kejar pace.' },
  { s: [M(30), M(35), W(45), L(7, 'Lari 3 mnt, jalan 1 mnt')] },
  { s: [M(35), M(35), W(50), L(8, 'Lari 4 mnt, jalan 1 mnt')] },
  { s: [M(30), M(30), W(40), L(6)], rec: true },
  { s: [M(40, 'Lari 4 mnt, jalan 1 mnt'), M(40, 'Lari 4 mnt, jalan 1 mnt'), M(30, 'Lari ringan, jalan bila perlu'), L(9, 'Lari 5 mnt, jalan 1 mnt')] },
  { s: [M(40, 'Lari 5 mnt, jalan 1 mnt'), M(40, 'Lari 5 mnt, jalan 1 mnt'), M(35, 'Lari ringan'), L(10, 'Lari 5 mnt, jalan 1 mnt')] },
  { s: [E(6), E(6), E(4), L(11)], n: 'Mulai lari terus-menerus di sesi pendek. Long run masih boleh lari-jalan.' },
  { s: [E(6), Q(7, 'Mudah 7 km + strides', '6× 20 dtk agak cepat di akhir'), E(4), L(12)] },
  { s: [E(7), E(7), E(5), L(13)] },
  { s: [E(5), E(5), E(4), L(10)], rec: true },
  { s: [E(7), Q(8, 'Fartlek 8 km', '6× 1 mnt agak cepat, 2 mnt santai'), E(5), L(14)] },
  { s: [E(8), E(8), E(5), L(16)] },
  { s: [E(8), Q(8, 'Tempo 8 km', 'Pemanasan 2 km, 3 km tempo, sisanya santai'), E(5), L(17)] },
  { s: [E(6), E(6), E(4), L(12)], rec: true },
  { s: [E(8), Q(9, 'Tempo 9 km', '4 km tempo di tengah'), E(5), L(18, 'Latih minum & gel tiap 40 mnt')], n: 'Kamis jadi sesi kualitas. Mulai latih asupan di long run.' },
  { s: [E(8), Q(9, 'Bukit 9 km', '6× 1 mnt tanjakan, turun jalan/jog'), E(6), L(20)] },
  { s: [E(9), Q(10, 'Tempo 10 km', '5 km tempo di tengah'), E(6), L(22)] },
  { s: [E(6), E(7), E(5), L(14)], rec: true },
  { s: [E(9), Q(10, 'Pace maraton 10 km', '6 km di pace MP'), E(6), L(24)] },
  { s: [E(9), Q(10, 'Tempo 10 km', '6 km tempo'), E(6), L(21, 'Atau ikut lomba HM sebagai uji coba')] },
  { s: [E(10), Q(11, 'Pace maraton 11 km', '8 km di pace MP'), E(6), L(26)] },
  { s: [E(7), E(8), E(5), L(16)], rec: true },
  { s: [E(10), Q(12, 'Pace maraton 12 km', '10 km di pace MP'), E(6), L(28)], n: 'Fase puncak. Long run pakai baju, sepatu, dan gel yang sama dengan hari H.' },
  { s: [E(10), Q(12, 'Tempo 12 km', '6 km tempo'), E(6), L(30, 'Jam 04.00 kalau bisa, simulasi start')] },
  { s: [E(8), E(8), E(5), L(18)], rec: true },
  { s: [E(10), Q(13, 'Pace maraton 13 km', '12 km di pace MP'), E(6), L(30)] },
  { s: [E(10), Q(12, 'Tempo 12 km', '6 km tempo'), E(6), L(24)] },
  { s: [E(10), Q(12, 'Pace maraton 12 km', '10 km di pace MP'), E(6), L(32, 'Long run terjauh. Tentukan target finis setelah ini.')] },
  { s: [E(8), Q(10, 'Pace maraton 10 km', '8 km di pace MP'), E(5), L(22)], n: 'Volume turun, intensitas tetap sedikit. Badan sedang mengisi ulang.' },
  { s: [E(7), Q(8, 'Pace maraton 8 km', '5 km di pace MP'), E(5), L(14)] },
  { s: [Q(6, 'Mudah 6 km + strides', '4× 20 dtk'), Q(5, 'Mudah 5 km', '3× 1 mnt di pace MP'), Q(3, 'Shakeout 3 km', 'Sangat santai, ambil racepack'), RACE], n: 'Minggu lomba. Tidur cukup, banyak karbohidrat Jumat–Sabtu, jangan coba hal baru.' },
];
const WEEKS = 31;
const DAYS = [{ k: 'tue', l: 'Selasa', off: 1 }, { k: 'thu', l: 'Kamis', off: 3 }, { k: 'sat', l: 'Sabtu', off: 5 }, { k: 'sun', l: 'Minggu', off: 6 }];
const SDAYS = [['str_mon', 'Sen', 'A'], ['str_tue', 'Sel', 'M'], ['str_wed', 'Rab', 'B'], ['str_thu', 'Kam', 'M'], ['str_fri', 'Jum', 'A'], ['str_sat', 'Sab', 'C'], ['str_sun', 'Min', 'M']];
const ROUTINES = {
  A: ['Kaki & pinggul', 'Squat 2×12 · reverse lunge 2×8/kaki · glute bridge 2×15 · calf raise 2×15'],
  B: ['Core', 'Plank 3×30 dtk · side plank 2×20 dtk/sisi · dead bug 2×10 · bird dog 2×10'],
  C: ['Keseimbangan', 'Berdiri 1 kaki 3×30 dtk · step-up 2×10/kaki · single-leg calf raise 2×10'],
  M: ['Mobilitas', '10 menit setelah lari: ayunan kaki, hip flexor, betis, hamstring'],
};
const DEFAULT_RACE = '2027-06-13';

const fShort = new Intl.DateTimeFormat('id-ID', { day: 'numeric', month: 'short' });
const fLong = new Intl.DateTimeFormat('id-ID', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' });
const kmStr = (v) => (Math.round(v * 10) / 10).toLocaleString('id-ID');
const parseDate = (s) => { const [y, m, d] = s.slice(0, 10).split('-').map(Number); return new Date(y, m - 1, d); };
const addDays = (d, n) => { const x = new Date(d); x.setDate(x.getDate() + n); return x; };
const today0 = () => { const t = new Date(); return new Date(t.getFullYear(), t.getMonth(), t.getDate()); };
const sameDay = (a, b) => a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
const iso = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;

const T = { race: DEFAULT_RACE, log: new Map(), loaded: false, week: null, error: null };

function start() { return addDays(parseDate(T.race), -(30 * 7 + 6)); }
function weekStart(w) { return addDays(start(), (w - 1) * 7); }
function currentWeek() {
  const diff = Math.floor((today0() - start()) / 86400000);
  return diff < 0 ? 0 : Math.min(WEEKS + 1, Math.floor(diff / 7) + 1);
}
const phaseOf = (w) => PHASES.find((p) => w >= p.from && w <= p.to) || PHASES.at(-1);
const planKm = (w) => PLAN[w - 1].s.reduce((t, s) => t + s.km, 0);
const entry = (w, slot) => T.log.get(`${w}|${slot}`);

function actsOn(acts, day) {
  return acts.filter((a) => a.sport_type !== 'cycling' && sameDay(new Date(a.started_at), day));
}
function status(w, i, acts) {
  const d = DAYS[i];
  const e = entry(w, d.k);
  const same = actsOn(acts, addDays(weekStart(w), d.off));
  const actKm = same.reduce((t, a) => t + Number(a.distance_meters) / 1000, 0);
  const manual = e?.km > 0 ? Number(e.km) : null;
  if (e?.done) return { done: true, km: manual ?? (actKm > 0 ? actKm : null), auto: false };
  if (same.length) return { done: true, km: manual ?? actKm, auto: true };
  return { done: false, km: manual, auto: false };
}

async function load(ctx) {
  try {
    const [st, rows] = await Promise.all([
      ctx.api('/training_settings?select=race_date'),
      ctx.api('/training_log?select=week,slot,done,km,updated_at'),
    ]);
    if (st?.[0]?.race_date) T.race = String(st[0].race_date).slice(0, 10);
    T.log = new Map((rows || []).map((r) => [`${r.week}|${r.slot}`, r]));
    T.error = null;
  } catch (e) {
    T.error = ctx.friendlyError(e);
  }
  T.loaded = true;
}

async function saveEntry(ctx, w, slot, done, km) {
  const row = { user_id: ctx.state.user.id, week: w, slot, done, km: km > 0 ? km : null, updated_at: new Date().toISOString() };
  T.log.set(`${w}|${slot}`, row);
  try {
    await ctx.api('/training_log?on_conflict=user_id,week,slot', {
      method: 'POST', prefer: 'resolution=merge-duplicates,return=minimal', body: row,
    });
    return null;
  } catch (e) {
    return ctx.friendlyError(e);
  }
}

async function saveRace(ctx, value) {
  T.race = value;
  await ctx.api('/training_settings?on_conflict=user_id', {
    method: 'POST', prefer: 'resolution=merge-duplicates,return=minimal',
    body: { user_id: ctx.state.user.id, race_date: value, updated_at: new Date().toISOString() },
  });
}

export async function renderTraining(view, ctx) {
  if (!T.loaded) {
    view.innerHTML = '<p class="muted">Memuat program…</p>';
    await load(ctx);
    if (location.hash !== '#/program') return;
  }
  draw(view, ctx);
}

function draw(view, ctx) {
  const { esc } = ctx;
  const acts = ctx.state.activities;
  const cw = currentWeek();
  const w = T.week ?? Math.max(1, Math.min(WEEKS, cw || 1));
  const p = PLAN[w - 1];
  const ws = weekStart(w);
  const race = parseDate(T.race);
  const days = Math.round((race - today0()) / 86400000);

  let total = 0, due = 0, doneN = 0, longest = 0, str = 0;
  const weekDone = [];
  for (let x = 1; x <= WEEKS; x++) {
    let wk = 0;
    DAYS.forEach((d, i) => {
      const date = addDays(weekStart(x), d.off);
      const st = status(x, i, acts);
      if (date <= today0()) due++;
      if (st.done) {
        doneN++;
        const k = st.km ?? PLAN[x - 1].s[i].km;
        wk += k;
        if (i === 3) longest = Math.max(longest, k);
      }
    });
    weekDone.push(wk);
    total += wk;
    SDAYS.forEach(([k]) => { if (entry(x, k)?.done) str++; });
  }
  const note = p.n || PLAN.slice(0, w).reverse().find((x) => x.n)?.n || '';

  const chart = (() => {
    const Wd = 760, H = 200, pl = 30, pb = 22, pt = 8, max = 70, bw = (Wd - pl) / WEEKS;
    const y = (v) => pt + (H - pt - pb) * (1 - Math.min(max, v) / max);
    let s = `<svg viewBox="0 0 ${Wd} ${H}" role="img" aria-label="Km per minggu: rencana dan selesai">`;
    for (let v = 0; v <= max; v += 10) s += `<line x1="${pl}" x2="${Wd}" y1="${y(v)}" y2="${y(v)}" stroke="#243049"/><text x="${pl - 6}" y="${y(v) + 4}" fill="#94A3B8" font-size="10" text-anchor="end">${v}</text>`;
    const longPts = [];
    for (let x = 1; x <= WEEKS; x++) {
      const bx = pl + (x - 1) * bw + bw * 0.15;
      s += `<rect x="${bx}" y="${y(planKm(x))}" width="${bw * 0.7}" height="${y(0) - y(planKm(x))}" rx="2" fill="#243049"><title>Minggu ${x}: rencana ${kmStr(planKm(x))} km, selesai ${kmStr(weekDone[x - 1])} km</title></rect>`;
      if (weekDone[x - 1] > 0) s += `<rect x="${bx}" y="${y(weekDone[x - 1])}" width="${bw * 0.7}" height="${y(0) - y(weekDone[x - 1])}" rx="2" fill="#A3E635"/>`;
      longPts.push(`${bx + bw * 0.35},${y(PLAN[x - 1].s[3].km)}`);
      if (x % 2 === 1 || x === WEEKS) s += `<text x="${bx + bw * 0.35}" y="${H - 6}" fill="${x === cw ? '#F1F5F9' : '#94A3B8'}" font-size="10" text-anchor="middle">${x}</text>`;
    }
    s += `<polyline points="${longPts.join(' ')}" fill="none" stroke="#38BDF8" stroke-width="2"/>`;
    if (cw >= 1 && cw <= WEEKS) { const x = pl + (cw - 0.5) * bw; s += `<line x1="${x}" x2="${x}" y1="${pt}" y2="${y(0)}" stroke="#F1F5F9" stroke-dasharray="3 3"/>`; }
    return s + '</svg>';
  })();

  view.innerHTML = `
    <div class="tr-hero">
      <div>
        <span class="tr-eyebrow">Program full marathon · 31 minggu</span>
        <h2 class="page" style="margin:2px 0">FM JAKIM 2027</h2>
        <p class="sub" style="margin:0">${esc(fLong.format(race))} · start 04.00 WIB · batas 7 jam</p>
      </div>
      <div class="tr-count">
        <div><b class="lime">${days >= 0 ? days : 0}</b><span>hari lagi</span></div>
        <div><b>${cw === 0 ? 0 : Math.min(WEEKS, cw)}</b><span>${cw === 0 ? `mulai ${fShort.format(start())}` : 'minggu ke, dari 31'}</span></div>
        <div><b>${due ? Math.min(100, Math.round(doneN / due * 100)) : 0}%</b><span>sesi lari selesai</span></div>
      </div>
    </div>
    ${T.error ? `<p class="tr-err">Catatan latihan belum bisa dimuat: ${esc(T.error)}</p>` : ''}
    <div class="tr-phases" style="grid-template-columns:${PHASES.map((x) => `${x.to - x.from + 1}fr`).join(' ')}">
      ${PHASES.map((x) => `<div class="${cw >= x.from && cw <= x.to ? 'now' : cw > x.to ? 'past' : ''}" title="Minggu ${x.from}–${x.to}">${x.name}</div>`).join('')}
    </div>

    <section class="card section-gap">
      <div class="tr-weekhead">
        <div style="flex:1;min-width:220px">
          <h3 style="margin:0">Minggu ${w}${w === cw ? ' · minggu ini' : ''}</h3>
          <span class="muted small">${fShort.format(ws)} – ${fShort.format(addDays(ws, 6))} · ${phaseOf(w).name}${p.rec ? ' · <span style="color:var(--amber)">ringan</span>' : ''}</span>
        </div>
        <div class="tr-nav">
          <button type="button" class="btn btn-ghost btn-sm" data-w="${w - 1}" ${w <= 1 ? 'disabled' : ''} aria-label="Minggu sebelumnya">‹</button>
          <button type="button" class="btn btn-ghost btn-sm" data-w="now">Minggu ini</button>
          <button type="button" class="btn btn-ghost btn-sm" data-w="${w + 1}" ${w >= WEEKS ? 'disabled' : ''} aria-label="Minggu berikutnya">›</button>
        </div>
      </div>
      <p class="muted small" style="margin:6px 0 12px">Rencana ±${kmStr(planKm(w))} km · selesai ${kmStr(weekDone[w - 1])} km. ${esc(note)}</p>
      <div class="tr-sessions">
        ${DAYS.map((d, i) => {
          const s = p.s[i];
          const date = addDays(ws, d.off);
          const st = status(w, i, acts);
          const e = entry(w, d.k);
          return `<div class="tr-sess ${st.done ? 'done' : ''} ${sameDay(date, today0()) ? 'today' : ''}">
            <div class="tr-sess-top"><span>${d.l} · ${fShort.format(date)}</span>${s.long ? `<span class="pill">${s.race ? 'LOMBA' : 'utama'}</span>` : ''}</div>
            <b class="tr-sess-title">${esc(s.t)}</b>
            <span class="muted small">${esc(s.d)}</span>
            ${st.auto ? `<span class="small lime">Tercatat dari Tempuh: ${kmStr(st.km || 0)} km</span>` : ''}
            <div class="tr-sess-foot">
              <button type="button" class="tr-check" data-slot="${d.k}" aria-pressed="${st.done}" ${st.auto ? 'disabled' : ''}>${st.done ? (st.auto ? 'Selesai (otomatis)' : 'Selesai ✓') : 'Tandai selesai'}</button>
              <input class="tr-km num" type="number" inputmode="decimal" min="0" step="0.1" placeholder="km" aria-label="Km sebenarnya ${d.l}" data-slot="${d.k}" value="${e?.km > 0 ? Number(e.km) : ''}">
            </div>
          </div>`;
        }).join('')}
      </div>
      <h3 style="margin:16px 0 8px;font-size:15px">Latihan kekuatan 10–15 menit</h3>
      <div class="tr-str">
        ${SDAYS.map(([k, l, code], i) => {
          const on = !!entry(w, k)?.done;
          return `<div><button type="button" data-str="${k}" aria-pressed="${on}" aria-label="Latihan kekuatan ${l}">${on ? '✓' : code}</button><small>${l}<br>${addDays(ws, i).getDate()}</small></div>`;
        }).join('')}
      </div>
      <div class="tr-routines">${Object.entries(ROUTINES).map(([k, [n, d]]) => `<div><b>${k} · ${n}</b> <span class="muted">${d}</span></div>`).join('')}</div>
      <p class="muted small" id="tr-status" style="margin:10px 0 0">Sesi otomatis tercentang bila ada aktivitas lari/jalan di hari itu (dari HP atau upload).</p>
    </section>

    <section class="card section-gap">
      <h3>Progres</h3>
      <div class="kpis" style="margin-top:12px">
        <div class="kpi"><span class="stat-label">Km tercatat</span><span class="kpi-value num">${kmStr(total)}</span></div>
        <div class="kpi"><span class="stat-label">Sesi lari selesai</span><span class="kpi-value num">${doneN}</span></div>
        <div class="kpi"><span class="stat-label">Long run terjauh</span><span class="kpi-value num">${longest ? kmStr(longest) : '–'}<small> km</small></span></div>
        <div class="kpi"><span class="stat-label">Hari latihan kekuatan</span><span class="kpi-value num">${str}</span></div>
      </div>
      <div class="legend" style="margin-top:14px"><span><i style="background:#243049"></i>Rencana</span><span><i style="background:#A3E635"></i>Selesai</span><span><i style="background:#38BDF8"></i>Long run</span></div>
      <div class="tr-chart">${chart}</div>
    </section>

    <div class="grid two-col section-gap">
      <section class="card">
        <h3>Pace & target</h3>
        <div class="tr-pace">
          <div><span>Lari mudah (Selasa, Sabtu)</span><b>9:30–10:30 /km</b></div>
          <div><span>Long run Minggu, boleh lari-jalan</span><b>9:45–11:00 /km</b></div>
          <div><span>Tempo / bukit (Kamis, mulai Feb)</span><b>8:15–8:45 /km</b></div>
          <div><span>Pace maraton (mulai Mar)</span><b>8:45–9:10 /km</b></div>
          <div><span>Detak jantung lari mudah</span><b>≤ 130 bpm</b></div>
          <div><span>Target finis</span><b>&lt; 6:30 (aman &lt; 7:00)</b></div>
        </div>
      </section>
      <section class="card">
        <h3>Tanggal lomba</h3>
        <p class="muted small">Bila jadwal resmi berubah, ubah di sini; seluruh program ikut bergeser (juga di HP).</p>
        <form id="tr-race" class="target-form" style="margin:10px 0 0">
          <label>Hari Minggu <input type="date" id="tr-race-date" value="${T.race}" required style="width:auto"></label>
          <button class="btn btn-primary btn-sm" type="submit">Simpan</button>
          <span class="small muted" id="tr-race-status"></span>
        </form>
        <p class="tr-warn">Sebelum minggu 1, cek kesehatan dulu (tekanan darah dan EKG, idealnya treadmill test). Hentikan lari dan periksa ke dokter bila nyeri dada, sesak tidak wajar, atau pusing.</p>
      </section>
    </div>

    <section class="card section-gap">
      <h3>Rencana lengkap</h3>
      <div class="tr-plan"><table>
        <thead><tr><th>Mg</th><th>Selasa</th><th>Kamis</th><th>Sabtu</th><th>Minggu</th><th>±km</th></tr></thead>
        <tbody>${PHASES.map((ph) => `<tr class="ph"><td colspan="6">${ph.name} · minggu ${ph.from}–${ph.to}</td></tr>` +
          Array.from({ length: ph.to - ph.from + 1 }, (_, j) => {
            const x = ph.from + j;
            const pw = PLAN[x - 1];
            return `<tr class="${x === cw ? 'cur' : ''}"><td><b>${x}</b><small>${fShort.format(weekStart(x))}${pw.rec ? ' · ringan' : ''}</small></td>${pw.s.map((s, i) => `<td class="${i === 3 ? 'long' : ''}">${esc(s.t)}${status(x, i, acts).done ? ' <span class="lime">✓</span>' : ''}<small>${esc(s.d)}</small></td>`).join('')}<td class="num">${kmStr(planKm(x))}</td></tr>`;
          }).join('')).join('')}</tbody>
      </table></div>
    </section>`;

  const setStatus = (msg) => { const el = document.getElementById('tr-status'); if (el) el.textContent = msg; };
  view.querySelectorAll('[data-w]').forEach((b) => b.addEventListener('click', () => {
    T.week = b.dataset.w === 'now' ? null : Math.max(1, Math.min(WEEKS, Number(b.dataset.w)));
    draw(view, ctx);
  }));
  view.querySelectorAll('.tr-check').forEach((b) => b.addEventListener('click', async () => {
    const e = entry(w, b.dataset.slot);
    const err = await saveEntry(ctx, w, b.dataset.slot, !e?.done, e?.km ? Number(e.km) : null);
    draw(view, ctx);
    if (err) setStatus(`Gagal menyimpan: ${err}`);
  }));
  view.querySelectorAll('.tr-km').forEach((inp) => inp.addEventListener('change', async () => {
    const v = parseFloat(String(inp.value).replace(',', '.'));
    const e = entry(w, inp.dataset.slot);
    const err = await saveEntry(ctx, w, inp.dataset.slot, v > 0 ? true : !!e?.done, v > 0 ? v : null);
    draw(view, ctx);
    if (err) setStatus(`Gagal menyimpan: ${err}`);
  }));
  view.querySelectorAll('[data-str]').forEach((b) => b.addEventListener('click', async () => {
    const e = entry(w, b.dataset.str);
    const err = await saveEntry(ctx, w, b.dataset.str, !e?.done, null);
    draw(view, ctx);
    if (err) setStatus(`Gagal menyimpan: ${err}`);
  }));
  document.getElementById('tr-race').addEventListener('submit', async (ev) => {
    ev.preventDefault();
    const v = document.getElementById('tr-race-date').value;
    const out = document.getElementById('tr-race-status');
    if (!v) return;
    if (parseDate(v).getDay() !== 0) { out.textContent = 'Pilih hari Minggu.'; return; }
    try { await saveRace(ctx, v); T.week = null; draw(view, ctx); }
    catch (e) { out.textContent = `Gagal: ${ctx.friendlyError(e)}`; }
  });
}

export { iso };
