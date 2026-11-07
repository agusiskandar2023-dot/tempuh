import { WEEKLY_TARGET_KM } from '../config.js';
import { signIn, signUp, signOut, currentUser, api, ApiError } from './neon.js';
import { FitError } from './fit.js';
import { parseTrackBytes, readZip } from './tracks.js';
import { renderTraining } from './training.js';
import {
  SPORTS, fmtKm, fmtDuration, fmtPace, perf, computeSplits, routeDistance,
  elevationGain, estimateCalories, computeMaxSpeed, fmtKmh,
} from './metrics.js';

const $ = (sel, root = document) => root.querySelector(sel);
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

const ICONS = {
  running: '<path d="M14 4a2 2 0 1 0 0 .1M8 21l3-6 3 2v5M6 11l4-3 4 1 3 3M11 15l-1-5"/>',
  jogging: '<path d="M14 4a2 2 0 1 0 0 .1M8 21l3-6 3 2v5M6 11l4-3 4 1 3 3M11 15l-1-5"/>',
  walking: '<path d="M13 4a2 2 0 1 0 0 .1M10 21l2-7 3 3v4M9 10l3-2 2 4 3 1M12 14l-3 7"/>',
  cycling: '<circle cx="5.5" cy="17.5" r="3.5"/><circle cx="18.5" cy="17.5" r="3.5"/><path d="M5.5 17.5L9 10h6l3.5 7.5M9 10l3 7.5M14 6h3"/>',
};
const icon = (sport, size = 24) =>
  `<svg viewBox="0 0 24 24" width="${size}" height="${size}" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICONS[sport] || ICONS.running}</svg>`;

const dateFmt = new Intl.DateTimeFormat('id-ID', { weekday: 'short', day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' });
const longDate = new Intl.DateTimeFormat('id-ID', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric', hour: '2-digit', minute: '2-digit' });

const state = { user: null, activities: [], loaded: false, filter: 'all', uploads: [], period: 'month', recSport: null, routes: null };

function partOfDay(d) {
  const h = d.getHours();
  return h < 11 ? 'pagi' : h < 15 ? 'siang' : h < 19 ? 'sore' : 'malam';
}
const titleOf = (a) => a.title || `${SPORTS[a.sport_type]?.label ?? 'Aktivitas'} ${partOfDay(new Date(a.started_at))}`;
const isGarmin = (a) => a.source && a.source !== 'phone_gps';

function friendlyError(e) {
  if (e instanceof ApiError) {
    if (e.status === 401 || e.status === 403) return 'Email atau kata sandi salah, atau sesi sudah berakhir.';
    if (/already|exists/i.test(e.message)) return 'Email ini sudah terdaftar. Silakan masuk.';
    if (/password/i.test(e.message)) return 'Kata sandi minimal 8 karakter.';
    return e.message;
  }
  if (e instanceof TypeError) return 'Tidak bisa terhubung ke server. Periksa koneksi internet.';
  return e?.message || String(e);
}

/* ===================== Auth ===================== */
let registering = false;
function setAuthMode(reg) {
  registering = reg;
  $('#auth-title').textContent = reg ? 'Buat akun' : 'Masuk';
  $('#auth-lead').textContent = reg ? 'Satu akun untuk web dan aplikasi Tempuh di HP.' : 'Lihat dashboard dan riwayat aktivitas Anda.';
  $('#auth-submit').textContent = reg ? 'Daftar' : 'Masuk';
  $('#switch-text').textContent = reg ? 'Sudah punya akun?' : 'Belum punya akun?';
  $('#auth-switch').textContent = reg ? 'Masuk' : 'Daftar';
  $('#name-field').hidden = !reg;
  $('#auth-pass').autocomplete = reg ? 'new-password' : 'current-password';
  $('#auth-msg').hidden = true;
}

async function onAuthSubmit(ev) {
  ev.preventDefault();
  const email = $('#auth-email').value.trim();
  const pass = $('#auth-pass').value;
  const name = $('#auth-name').value.trim() || email.split('@')[0];
  const msg = $('#auth-msg');
  if (!email || pass.length < 8) {
    msg.textContent = 'Isi email dan kata sandi (minimal 8 karakter).';
    msg.hidden = false;
    return;
  }
  const btn = $('#auth-submit');
  btn.disabled = true;
  msg.hidden = true;
  try {
    const user = registering ? await signUp(name, email, pass) : await signIn(email, pass);
    state.user = user || (await currentUser());
    if (!state.user) throw new Error('Login berhasil, tetapi sesi tidak tersimpan. Izinkan cookie untuk situs ini lalu coba lagi.');
    await enterApp();
  } catch (e) {
    msg.textContent = friendlyError(e);
    msg.hidden = false;
  } finally {
    btn.disabled = false;
  }
}

async function ensureProfile() {
  const u = state.user;
  await api('/profiles?on_conflict=id', {
    method: 'POST',
    prefer: 'resolution=ignore-duplicates,return=minimal',
    body: { id: u.id, display_name: u.name || null, auth_provider: 'neon_auth', auth_subject: u.id },
  });
}

async function enterApp() {
  $('#loading').hidden = true;
  $('#auth').hidden = true;
  $('#app').hidden = false;
  $('#who').textContent = state.user.name || state.user.email;
  try {
    await ensureProfile();
  } catch (e) {
    console.warn('profile', e);
  }
  await loadActivities();
  route();
}

async function loadActivities() {
  try {
    state.activities = await api(
      '/activities?select=id,sport_type,title,started_at,finished_at,elapsed_seconds,moving_seconds,paused_seconds,distance_meters,elevation_gain_meters,calories_estimated,avg_heart_rate,max_heart_rate,source,source_device,max_speed_mps&status=eq.completed&order=started_at.desc',
    ) || [];
  } catch (e) {
    state.activities = [];
    state.loadError = friendlyError(e);
  }
  state.loaded = true;
  state.routes = null;
}

/* ===================== Router ===================== */
let detailMap = null;
function route() {
  if (detailMap) { detailMap.remove(); detailMap = null; }
  if (allMap) { allMap.remove(); allMap = null; }
  const hash = location.hash.replace(/^#\/?/, '') || 'dashboard';
  const [page, arg] = hash.split('/');
  document.querySelectorAll('.nav a').forEach((a) => {
    if (a.dataset.route === (page === 'aktivitas' ? 'riwayat' : page)) a.setAttribute('aria-current', 'page');
    else a.removeAttribute('aria-current');
  });
  const view = $('#view');
  if (page === 'riwayat') renderHistory(view);
  else if (page === 'aktivitas' && arg) renderDetail(view, arg);
  else if (page === 'upload') renderUpload(view);
  else if (page === 'program') renderTraining(view, { state, api, esc, friendlyError });
  else renderDashboard(view);
  window.scrollTo(0, 0);
}

/* ===================== Dashboard ===================== */
const SPORT_COLORS = { running: '#A3E635', walking: '#38BDF8', cycling: '#FBBF24', jogging: '#A78BFA' };
const SPORT_ORDER = ['running', 'jogging', 'walking', 'cycling'];
const DEFAULT_TARGETS = { week: WEEKLY_TARGET_KM, month: 80, year: 1000 };
const PERIOD_LABEL = { week: 'Minggu', month: 'Bulan', year: 'Tahun' };
const monthName = new Intl.DateTimeFormat('id-ID', { month: 'long', year: 'numeric' });
const shortDate = new Intl.DateTimeFormat('id-ID', { day: 'numeric', month: 'short' });
const shortDateY = new Intl.DateTimeFormat('id-ID', { day: 'numeric', month: 'short', year: 'numeric' });
const nf = new Intl.NumberFormat('id-ID');
const kmStr = (km, d = 1) => km.toFixed(d).replace('.', ',');

function startOfWeek(d) {
  const x = new Date(d.getFullYear(), d.getMonth(), d.getDate());
  const day = (x.getDay() + 6) % 7; // Senin = 0
  x.setDate(x.getDate() - day);
  return x;
}
const dayKey = (d) => `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`;

function getTarget(p) {
  try {
    const v = Number(localStorage.getItem(`tempuh_target_${p}`));
    if (v > 0) return v;
  } catch { /* penyimpanan tidak tersedia */ }
  return DEFAULT_TARGETS[p];
}
function setTarget(p, v) {
  try { localStorage.setItem(`tempuh_target_${p}`, String(v)); } catch { /* abaikan */ }
}

function periodRange(p, now) {
  if (p === 'week') {
    const s = startOfWeek(now);
    const e = new Date(s); e.setDate(e.getDate() + 7);
    const ps = new Date(s); ps.setDate(ps.getDate() - 7);
    const last = new Date(e); last.setDate(last.getDate() - 1);
    return { s, e, ps, label: `${shortDate.format(s)} – ${shortDateY.format(last)}`, prev: 'minggu lalu' };
  }
  if (p === 'month') {
    const s = new Date(now.getFullYear(), now.getMonth(), 1);
    const ps = new Date(now.getFullYear(), now.getMonth() - 1, 1);
    return { s, e: new Date(now.getFullYear(), now.getMonth() + 1, 1), ps, label: monthName.format(s), prev: monthName.format(ps).split(' ')[0] };
  }
  return { s: new Date(now.getFullYear(), 0, 1), e: new Date(now.getFullYear() + 1, 0, 1), ps: new Date(now.getFullYear() - 1, 0, 1), label: String(now.getFullYear()), prev: String(now.getFullYear() - 1) };
}

function summarize(list, s, e) {
  const sel = list.filter((a) => { const d = new Date(a.started_at); return d >= s && d < e; });
  return {
    n: sel.length,
    km: sel.reduce((t, a) => t + Number(a.distance_meters) / 1000, 0),
    sec: sel.reduce((t, a) => t + (a.moving_seconds || 0), 0),
    kcal: sel.reduce((t, a) => t + (a.calories_estimated || 0), 0),
    elev: sel.reduce((t, a) => t + (Number(a.elevation_gain_meters) || 0), 0),
    days: new Set(sel.map((a) => dayKey(new Date(a.started_at)))).size,
  };
}

function delta(cur, prev, abs = false) {
  if (prev <= 0) return cur > 0 ? { t: 'baru', c: 'up' } : { t: '', c: '' };
  if (abs) {
    const d = Math.round(cur - prev);
    return d === 0 ? { t: '= sama', c: 'same' } : { t: `${d > 0 ? '↑' : '↓'} ${Math.abs(d)}`, c: d > 0 ? 'up' : 'down' };
  }
  const pct = Math.round(((cur - prev) / prev) * 100);
  return pct === 0 ? { t: '= sama', c: 'same' } : { t: `${pct > 0 ? '↑' : '↓'} ${Math.abs(pct)}%`, c: pct > 0 ? 'up' : 'down' };
}

function fmtHours(sec) {
  const h = Math.floor(sec / 3600), m = Math.round((sec % 3600) / 60);
  return h > 0 ? `${h}j ${String(m).padStart(2, '0')}m` : `${m}m`;
}

function dayStreak(acts, now) {
  const days = new Set(acts.map((a) => dayKey(new Date(a.started_at))));
  const d = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  if (!days.has(dayKey(d))) d.setDate(d.getDate() - 1);
  let n = 0;
  while (days.has(dayKey(d))) { n++; d.setDate(d.getDate() - 1); }
  return n;
}

function longestStreak(acts) {
  const days = [...new Set(acts.map((a) => { const d = new Date(a.started_at); return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime(); }))].sort((a, b) => a - b);
  let best = 0, cur = 0, prev = null;
  for (const t of days) {
    cur = prev != null && Math.round((t - prev) / 86400000) === 1 ? cur + 1 : 1;
    best = Math.max(best, cur);
    prev = t;
  }
  return best;
}

/** Minggu berturut-turut target tercapai (minggu ini ikut dihitung bila sudah tercapai). */
function weekTargetStreak(acts, now, target) {
  let s = startOfWeek(now), n = 0;
  const kmIn = (st) => { const e = new Date(st); e.setDate(e.getDate() + 7); return summarize(acts, st, e).km; };
  if (kmIn(s) >= target) n++;
  for (;;) {
    s = new Date(s); s.setDate(s.getDate() - 7);
    if (kmIn(s) >= target) n++; else break;
  }
  return n;
}

/** Rekor pribadi: terjauh, terlama, tercepat (≥ 1 km), kecepatan maks. */
function personalRecords(acts, sport, now) {
  const list = acts.filter((a) => a.sport_type === sport)
    .sort((a, b) => new Date(a.started_at) - new Date(b.started_at));
  const recent = new Date(now); recent.setDate(recent.getDate() - 7);
  const best = (val) => {
    let top = null, topV = null, beat = false;
    for (const a of list) {
      const v = val(a);
      if (v == null || !(v > 0)) continue;
      if (topV == null || v > topV) { beat = topV != null; topV = v; top = a; }
    }
    return top ? { a: top, v: topV, isNew: beat && new Date(top.started_at) >= recent } : null;
  };
  const speed = SPORTS[sport]?.speed;
  const avg = (a) => (Number(a.distance_meters) >= 1000 && a.moving_seconds > 0 ? Number(a.distance_meters) / a.moving_seconds : null);
  const out = [];
  const far = best((a) => Number(a.distance_meters));
  if (far) out.push({ label: 'Terjauh', value: fmtKm(far.v), unit: 'km', ...far });
  const lng = best((a) => a.moving_seconds);
  if (lng) out.push({ label: 'Terlama', value: fmtDuration(lng.v), unit: '', ...lng });
  const fast = best(avg);
  if (fast) out.push({ label: 'Tercepat', value: speed ? fmtKmh(fast.v) : fmtPace(1000 / fast.v), unit: speed ? 'km/j' : '/km', ...fast });
  const mx = best((a) => Number(a.max_speed_mps) || null);
  if (mx) out.push({ label: 'Kecepatan maks', value: fmtKmh(mx.v), unit: 'km/j', ...mx });
  return out;
}

function weeklyStackChart(weeks) {
  const W = 640, H = 210, padL = 34, padB = 26, padT = 12;
  const max = Math.max(1, ...weeks.map((w) => w.total));
  const step = max > 80 ? 40 : max > 40 ? 20 : max > 20 ? 10 : max > 8 ? 5 : 2;
  const top = Math.ceil(max / step) * step;
  const bw = (W - padL) / weeks.length;
  const y = (v) => padT + (H - padT - padB) * (1 - v / top);
  let svg = `<svg viewBox="0 0 ${W} ${H}" role="img" aria-label="Jarak per minggu per jenis olahraga, 12 minggu terakhir">`;
  for (let v = 0; v <= top; v += step) {
    svg += `<line x1="${padL}" x2="${W}" y1="${y(v)}" y2="${y(v)}" stroke="#243049" stroke-width="1"/>`;
    svg += `<text x="${padL - 8}" y="${y(v) + 4}" fill="#94A3B8" font-size="11" text-anchor="end">${v}</text>`;
  }
  weeks.forEach((w, i) => {
    const x = padL + i * bw + bw * 0.18;
    let base = 0;
    for (const k of SPORT_ORDER) {
      const v = w.by[k] || 0;
      if (v <= 0) continue;
      svg += `<rect x="${x}" y="${y(base + v)}" width="${bw * 0.64}" height="${Math.max(0, y(base) - y(base + v) - 1)}" fill="${SPORT_COLORS[k]}"><title>${w.label} · ${SPORTS[k].label}: ${kmStr(v)} km</title></rect>`;
      base += v;
    }
    const last = i === weeks.length - 1;
    if (i % 2 === weeks.length % 2 || last) {
      svg += `<text x="${x + bw * 0.32}" y="${H - 8}" fill="${last ? '#F1F5F9' : '#94A3B8'}" font-size="11" text-anchor="middle">${w.label}</text>`;
    }
  });
  return svg + '</svg>';
}

function paceTrendChart(weeks) {
  const pts = weeks.map((w, i) => ({ i, p: w.runKm >= 0.5 ? w.runSec / w.runKm : null, label: w.label })).filter((x) => x.p);
  if (pts.length < 2) return { svg: '<div class="empty small">Belum cukup data lari untuk grafik pace (butuh minimal 2 minggu).</div>', note: '' };
  const W = 640, H = 200, padL = 46, padB = 26, padT = 14;
  const lo = Math.min(...pts.map((x) => x.p)), hi = Math.max(...pts.map((x) => x.p));
  const span = Math.max(30, hi - lo);
  const yMin = lo - span * 0.15, yMax = hi + span * 0.15;
  const x = (i) => padL + ((W - padL - 10) * i) / (weeks.length - 1);
  // Pace lebih kecil = lebih cepat = lebih tinggi di grafik.
  const y = (p) => padT + ((H - padT - padB) * (p - yMin)) / (yMax - yMin);
  let svg = `<svg viewBox="0 0 ${W} ${H}" role="img" aria-label="Pace lari rata-rata per minggu">`;
  for (const p of [lo, (lo + hi) / 2, hi]) {
    svg += `<line x1="${padL}" x2="${W}" y1="${y(p)}" y2="${y(p)}" stroke="#243049"/><text x="${padL - 8}" y="${y(p) + 4}" fill="#94A3B8" font-size="11" text-anchor="end">${fmtPace(p)}</text>`;
  }
  svg += `<polyline fill="none" stroke="#A3E635" stroke-width="3" stroke-linejoin="round" stroke-linecap="round" points="${pts.map((q) => `${x(q.i)},${y(q.p)}`).join(' ')}"/>`;
  for (const q of pts) svg += `<circle cx="${x(q.i)}" cy="${y(q.p)}" r="4" fill="#A3E635"><title>${q.label}: ${fmtPace(q.p)} /km</title></circle>`;
  svg += `<text x="${x(0)}" y="${H - 8}" fill="#94A3B8" font-size="11">${weeks[0].label}</text><text x="${x(weeks.length - 1)}" y="${H - 8}" fill="#F1F5F9" font-size="11" text-anchor="end">Minggu ini</text>`;
  const diff = pts[0].p - pts.at(-1).p;
  const note = Math.abs(diff) < 3 ? 'Stabil' : diff > 0 ? `Makin cepat ${fmtPace(diff)} /km` : `Lebih lambat ${fmtPace(-diff)} /km`;
  return { svg: svg + '</svg>', note, good: diff >= 0 };
}

function heatmapHtml(acts, year) {
  const kmByDay = new Map();
  for (const a of acts) {
    const d = new Date(a.started_at);
    if (d.getFullYear() !== year) continue;
    const k = dayKey(d);
    kmByDay.set(k, (kmByDay.get(k) || 0) + Number(a.distance_meters) / 1000);
  }
  const shades = ['#243049', '#3D5A1C', '#5C8A22', '#82BC2B', '#A3E635'];
  const lvl = (km) => (km <= 0 ? 0 : km < 3 ? 1 : km < 6 ? 2 : km < 10 ? 3 : 4);
  const start = startOfWeek(new Date(year, 0, 1));
  const today = new Date();
  let cells = '';
  const d = new Date(start);
  let weeks = 0;
  while (d.getFullYear() <= year && weeks < 54) {
    for (let i = 0; i < 7; i++) {
      const inYear = d.getFullYear() === year;
      const km = inYear ? kmByDay.get(dayKey(d)) || 0 : 0;
      const future = d > today;
      cells += `<span class="hm-cell" style="background:${inYear && !future ? shades[lvl(km)] : 'transparent'}" title="${inYear ? `${shortDateY.format(d)}: ${km ? `${kmStr(km)} km` : 'tidak ada aktivitas'}` : ''}"></span>`;
      d.setDate(d.getDate() + 1);
    }
    weeks++;
  }
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
  return `<div class="hm-scroll"><div class="hm" style="--weeks:${weeks}">
      <div class="hm-months">${months.map((m) => `<span>${m}</span>`).join('')}</div>
      <div class="hm-grid">${cells}</div>
    </div></div>
    <div class="hm-legend">Sedikit ${shades.map((c) => `<span class="hm-cell" style="background:${c}"></span>`).join('')} Jauh</div>`;
}

function renderDashboard(view) {
  const acts = state.activities;
  const now = new Date();
  const period = state.period || 'month';
  const r = periodRange(period, now);
  const cur = summarize(acts, r.s, r.e);
  const prev = summarize(acts, r.ps, r.s);
  const daysInPeriod = Math.round((r.e - r.s) / 86400000);
  const kpis = [
    { label: 'Jarak', value: kmStr(cur.km), unit: 'km', d: delta(cur.km, prev.km) },
    { label: 'Waktu aktif', value: fmtHours(cur.sec), unit: '', d: delta(cur.sec, prev.sec) },
    { label: 'Aktivitas', value: String(cur.n), unit: '', d: delta(cur.n, prev.n, true) },
    { label: 'Kalori', value: nf.format(cur.kcal), unit: 'kkal', d: delta(cur.kcal, prev.kcal) },
    { label: 'Elevasi', value: nf.format(Math.round(cur.elev)), unit: 'm', d: delta(cur.elev, prev.elev) },
    { label: 'Hari aktif', value: String(cur.days), unit: period === 'year' ? 'hari' : `dari ${daysInPeriod}`, d: delta(cur.days, prev.days, true) },
  ];

  const targets = ['week', 'month', 'year'].map((p) => {
    const rr = periodRange(p, now);
    const km = summarize(acts, rr.s, rr.e).km;
    const goal = getTarget(p);
    const left = goal - km;
    return {
      p, km, goal, pct: Math.min(100, (km / goal) * 100),
      label: p === 'week' ? 'Minggu ini' : p === 'month' ? rr.label : rr.label,
      note: left <= 0 ? `Tercapai! Lebih ${kmStr(-left)} km` : `Perlu ${kmStr(left)} km lagi`,
    };
  });

  const streak = dayStreak(acts, now);
  const longest = longestStreak(acts);
  const weekStreak = weekTargetStreak(acts, now, getTarget('week'));
  const last7 = [];
  for (let i = 6; i >= 0; i--) {
    const d = new Date(now.getFullYear(), now.getMonth(), now.getDate() - i);
    const e = new Date(d); e.setDate(e.getDate() + 1);
    const km = summarize(acts, d, e).km;
    last7.push({ km, day: ['M', 'S', 'S', 'R', 'K', 'J', 'S'][d.getDay()] });
  }
  const shade = (km) => (km <= 0 ? '#243049' : km < 3 ? '#3D5A1C' : km < 6 ? '#5C8A22' : km < 10 ? '#82BC2B' : '#A3E635');

  const sportCounts = SPORT_ORDER.map((k) => [k, acts.filter((a) => a.sport_type === k).length]);
  if (!state.recSport) state.recSport = (sportCounts.slice().sort((a, b) => b[1] - a[1])[0] || ['running'])[0];
  const records = personalRecords(acts, state.recSport, now);

  const wk = startOfWeek(now);
  const weeks = [];
  for (let i = 11; i >= 0; i--) {
    const s = new Date(wk); s.setDate(s.getDate() - 7 * i);
    const e = new Date(s); e.setDate(e.getDate() + 7);
    const sel = acts.filter((a) => { const d = new Date(a.started_at); return d >= s && d < e; });
    const by = {};
    for (const a of sel) by[a.sport_type] = (by[a.sport_type] || 0) + Number(a.distance_meters) / 1000;
    const runs = sel.filter((a) => a.sport_type === 'running' || a.sport_type === 'jogging');
    weeks.push({
      label: `${s.getDate()}/${s.getMonth() + 1}`, by,
      total: Object.values(by).reduce((t, v) => t + v, 0),
      runKm: runs.reduce((t, a) => t + Number(a.distance_meters) / 1000, 0),
      runSec: runs.reduce((t, a) => t + (a.moving_seconds || 0), 0),
    });
  }
  const pace = paceTrendChart(weeks);

  const totalKm = acts.reduce((t, a) => t + Number(a.distance_meters) / 1000, 0);
  const mix = SPORT_ORDER.map((k) => {
    const km = acts.filter((a) => a.sport_type === k).reduce((t, a) => t + Number(a.distance_meters) / 1000, 0);
    return { k, km, pct: totalKm > 0 ? Math.round((km / totalKm) * 100) : 0 };
  }).filter((m) => m.km > 0);

  const dow = [0, 0, 0, 0, 0, 0, 0];
  const tod = { Pagi: 0, Siang: 0, Sore: 0, Malam: 0 };
  const hourCount = new Array(24).fill(0);
  for (const a of acts) {
    const d = new Date(a.started_at);
    dow[(d.getDay() + 6) % 7]++;
    const h = d.getHours();
    hourCount[h]++;
    tod[h < 11 ? 'Pagi' : h < 15 ? 'Siang' : h < 19 ? 'Sore' : 'Malam']++;
  }
  const dowNames = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
  const dowLong = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
  const maxDow = Math.max(1, ...dow);
  const topDow = dow.indexOf(Math.max(...dow));
  const topHour = hourCount.indexOf(Math.max(...hourCount));
  const topPart = topHour < 11 ? 'pagi' : topHour < 15 ? 'siang' : topHour < 19 ? 'sore' : 'malam';
  const habit = acts.length
    ? `${dowLong[topDow]} ${topPart}, ${String(topHour).padStart(2, '0')}.00–${String((topHour + 1) % 24).padStart(2, '0')}.00`
    : '–';

  const name = state.user.name ? `, ${esc(state.user.name.split(' ')[0])}` : '';
  view.innerHTML = `
    <div class="dash-head">
      <div style="flex:1;min-width:220px">
        <h2 class="page">Halo${name}</h2>
        <p class="sub" style="margin:0">${esc(r.label)} · dibanding ${esc(r.prev)}${state.loadError ? ` <span style="color:#fca5a5">${esc(state.loadError)}</span>` : ''}</p>
      </div>
      <div class="seg" role="group" aria-label="Periode">
        ${['week', 'month', 'year'].map((p) => `<button type="button" data-period="${p}" aria-pressed="${p === period}">${PERIOD_LABEL[p]}</button>`).join('')}
      </div>
    </div>

    <section class="kpis" aria-label="Ringkasan periode">
      ${kpis.map((k) => `<div class="kpi"><span class="stat-label">${k.label}</span>
        <span class="kpi-value num">${k.value}${k.unit ? ` <small>${k.unit}</small>` : ''}</span>
        <span class="delta ${k.d.c}">${k.d.t || '&nbsp;'}</span></div>`).join('')}
    </section>

    <div class="grid two-col section-gap">
      <div class="card">
        <div class="card-head"><h3>Target</h3><button class="btn btn-ghost btn-sm" type="button" id="edit-target">Ubah target</button></div>
        <form id="target-form" class="target-form" hidden>
          ${['week', 'month', 'year'].map((p) => `<label>${p === 'week' ? 'Mingguan' : p === 'month' ? 'Bulanan' : 'Tahunan'} <input type="number" min="1" step="1" name="${p}" value="${getTarget(p)}"> km</label>`).join('')}
          <button class="btn btn-primary btn-sm" type="submit">Simpan</button>
        </form>
        ${targets.map((t) => `<div class="target">
          <div class="target-row"><span>${esc(t.label)}</span><span class="num"><b>${kmStr(t.km)}</b><span class="muted"> / ${nf.format(t.goal)} km</span></span></div>
          <div class="progress" role="progressbar" aria-valuenow="${Math.round(t.pct)}" aria-valuemin="0" aria-valuemax="100" aria-label="Target ${esc(t.label)}"><div style="width:${t.pct}%"></div></div>
          <span class="muted small">${t.note}</span></div>`).join('')}
      </div>
      <div class="card">
        <h3>Konsistensi</h3>
        <div class="streaks">
          <div class="streak"><span class="stat-label">Hari aktif beruntun</span><span class="kpi-value lime">${streak} <small>hari</small></span><span class="muted small">Terpanjang: ${longest} hari</span></div>
          <div class="streak"><span class="stat-label">Minggu target tercapai</span><span class="kpi-value">${weekStreak} <small>minggu</small></span><span class="muted small">Berturut-turut</span></div>
        </div>
        <div class="stat-label" style="margin:14px 0 6px">7 hari terakhir</div>
        <div class="last7">${last7.map((d) => `<div><span style="background:${shade(d.km)}" title="${d.km ? `${kmStr(d.km)} km` : 'tidak ada aktivitas'}"></span><small>${d.day}</small></div>`).join('')}</div>
      </div>
    </div>

    <section class="card section-gap">
      <div class="card-head wrap">
        <h3 style="font-size:18px">Rekor pribadi</h3>
        <div class="chips" role="group" aria-label="Jenis olahraga" style="margin:0">
          ${SPORT_ORDER.map((k) => `<button class="chip" type="button" data-rec="${k}" aria-pressed="${k === state.recSport}">${SPORTS[k].label}</button>`).join('')}
        </div>
      </div>
      ${records.length ? `<div class="records">${records.map((x) => `<a class="record ${x.isNew ? 'new' : ''}" href="#/aktivitas/${esc(x.a.id)}">
          <span class="record-top"><span class="stat-label">${x.label}</span>${x.isNew ? '<span class="new-badge">Rekor baru!</span>' : ''}</span>
          <span class="kpi-value num">${x.value}${x.unit ? ` <small>${x.unit}</small>` : ''}</span>
          <span class="muted small">${esc(shortDateY.format(new Date(x.a.started_at)))}</span></a>`).join('')}</div>
          ${records.length < 4 ? '<p class="muted small" style="margin:10px 0 0">Kecepatan maks muncul setelah aktivitas disinkronkan dari aplikasi versi terbaru.</p>' : ''}`
        : `<div class="empty small">Belum ada aktivitas ${esc(SPORTS[state.recSport].label.toLowerCase())}.</div>`}
    </section>

    <div class="grid two-col section-gap">
      <div class="card chart">
        <h3>Jarak per minggu <span class="muted">(km, 12 minggu)</span></h3>
        <div class="legend">${SPORT_ORDER.map((k) => `<span><i style="background:${SPORT_COLORS[k]}"></i>${SPORTS[k].label}</span>`).join('')}</div>
        ${weeklyStackChart(weeks)}
      </div>
      <div class="card chart">
        <div class="card-head"><h3>Pace lari rata-rata</h3>${pace.note ? `<span class="pill ${pace.good ? '' : 'warn'}">${pace.note}</span>` : ''}</div>
        ${pace.svg}
        <p class="muted small" style="margin:6px 0 0">Lari & jogging per minggu. Lebih tinggi = lebih cepat.</p>
      </div>
    </div>

    <section class="card section-gap">
      <h3>Kalender aktivitas ${now.getFullYear()}</h3>
      ${heatmapHtml(acts, now.getFullYear())}
    </section>

    <div class="grid two-col section-gap">
      <div class="card">
        <h3>Porsi olahraga</h3>
        ${mix.length ? mix.map((m) => `<div class="target">
          <div class="target-row"><span>${SPORTS[m.k].label}</span><span class="num">${kmStr(m.km)} km · <b>${m.pct}%</b></span></div>
          <div class="bar"><div style="width:${m.pct}%;background:${SPORT_COLORS[m.k]}"></div></div></div>`).join('') : '<p class="muted">Belum ada data.</p>'}
      </div>
      <div class="card">
        <h3>Kebiasaan</h3>
        <p style="margin:-6px 0 12px">Paling sering: <b class="lime">${esc(habit)}</b></p>
        <div class="dow">${dow.map((n, i) => `<div><span style="height:${Math.max(4, (n / maxDow) * 100)}%;background:${i === topDow && n ? '#A3E635' : '#3D5A1C'}" title="${dowLong[i]}: ${n} aktivitas"></span><small>${dowNames[i]}</small></div>`).join('')}</div>
        <div class="tod">${Object.entries(tod).map(([k, n]) => `<div><span class="muted">${k}</span><b>${acts.length ? Math.round((n / acts.length) * 100) : 0}%</b></div>`).join('')}</div>
      </div>
    </div>

    <div class="grid two-col section-gap">
      <div class="card">
        <div class="card-head"><h3>Peta semua rute</h3><span class="muted small" id="routes-count"></span></div>
        <div class="all-map" id="all-map"><div class="no-route">Memuat rute…</div></div>
        <p class="muted small" style="margin:8px 0 0">Makin terang = makin sering dilewati.</p>
      </div>
      <div class="card">
        <div class="card-head"><h3>Aktivitas terbaru</h3><a href="#/riwayat">Lihat semua</a></div>
        ${acts.length ? `<div class="list">${acts.slice(0, 4).map(itemHtml).join('')}</div>`
          : `<div class="empty small">Belum ada aktivitas. <a href="#/upload">Upload file .FIT dari Garmin</a> atau sinkronkan dari aplikasi HP.</div>`}
      </div>
    </div>`;

  view.querySelectorAll('[data-period]').forEach((b) => b.addEventListener('click', () => {
    state.period = b.dataset.period;
    renderDashboard(view);
  }));
  view.querySelectorAll('[data-rec]').forEach((b) => b.addEventListener('click', () => {
    state.recSport = b.dataset.rec;
    renderDashboard(view);
  }));
  const tf = $('#target-form');
  $('#edit-target').addEventListener('click', () => { tf.hidden = !tf.hidden; });
  tf.addEventListener('submit', (e) => {
    e.preventDefault();
    for (const p of ['week', 'month', 'year']) {
      const v = Number(tf.elements[p].value);
      if (v > 0) setTarget(p, v);
    }
    renderDashboard(view);
  });
  drawAllRoutes();
}

let allMap = null;
async function drawAllRoutes() {
  if (allMap) { allMap.remove(); allMap = null; }
  const el = $('#all-map');
  if (!el) return;
  if (typeof L === 'undefined') { el.innerHTML = '<div class="no-route">Peta gagal dimuat.</div>'; return; }
  const ids = state.activities.slice(0, 200).map((a) => a.id);
  if (!ids.length) { el.innerHTML = '<div class="no-route">Belum ada rute.</div>'; return; }
  try {
    if (!state.routes) {
      const rows = await api(`/route_preview?select=activity_id,sequence_no,latitude,longitude,segment_start&order=activity_id,sequence_no&limit=60000`) || [];
      const by = new Map();
      for (const p of rows) {
        if (!by.has(p.activity_id)) by.set(p.activity_id, [[]]);
        const segs = by.get(p.activity_id);
        if (p.segment_start && segs.at(-1).length) segs.push([]);
        segs.at(-1).push([p.latitude, p.longitude]);
      }
      state.routes = by;
    }
  } catch (e) {
    el.innerHTML = `<div class="no-route">${esc(friendlyError(e))}</div>`;
    return;
  }
  if (!document.body.contains(el)) return;
  const sport = new Map(state.activities.map((a) => [a.id, a.sport_type]));
  const routes = [...state.routes.entries()].filter(([id]) => sport.has(id));
  $('#routes-count').textContent = `${routes.length} rute`;
  if (!routes.length) { el.innerHTML = '<div class="no-route">Belum ada rute GPS.</div>'; return; }
  el.innerHTML = '';
  allMap = L.map(el, { zoomControl: true, attributionControl: true });
  L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', { maxZoom: 19, attribution: '© OpenStreetMap contributors' }).addTo(allMap);
  const group = L.featureGroup();
  for (const [id, segs] of routes) {
    L.polyline(segs, { color: SPORT_COLORS[sport.get(id)] || '#A3E635', weight: 4, opacity: 0.35 }).addTo(group);
  }
  group.addTo(allMap);
  allMap.fitBounds(group.getBounds(), { padding: [20, 20] });
}

function itemHtml(a) {
  return `<a class="item" href="#/aktivitas/${esc(a.id)}">
    <span class="icon-tile">${icon(a.sport_type)}</span>
    <span class="item-body">
      <span class="item-title">${esc(titleOf(a))} · ${fmtKm(Number(a.distance_meters))} km ${isGarmin(a) ? '<span class="badge">Garmin</span>' : ''}</span>
      <span class="item-meta">${esc(dateFmt.format(new Date(a.started_at)))}</span><br>
      <span class="item-stats num">${fmtDuration(a.moving_seconds)} · ${perf(a)}${a.avg_heart_rate ? ` · ${a.avg_heart_rate} bpm` : ''}</span>
    </span>
    <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true"><path d="M9 6l6 6-6 6" fill="none" stroke="#94A3B8" stroke-width="2" stroke-linecap="round"/></svg>
  </a>`;
}

/* ===================== Riwayat ===================== */
function renderHistory(view) {
  const f = state.filter;
  const list = f === 'all' ? state.activities : state.activities.filter((a) => a.sport_type === f);
  const chips = [['all', 'Semua'], ...Object.entries(SPORTS).map(([k, v]) => [k, v.label])];
  view.innerHTML = `
    <h2 class="page">Riwayat</h2>
    <p class="sub">${state.activities.length} aktivitas tersimpan.</p>
    <div class="chips" role="group" aria-label="Filter olahraga">
      ${chips.map(([k, l]) => `<button class="chip" type="button" data-f="${k}" aria-pressed="${k === f}">${l}</button>`).join('')}
    </div>
    ${list.length ? `<div class="list">${list.map(itemHtml).join('')}</div>` : '<div class="empty">Belum ada aktivitas untuk jenis ini.</div>'}`;
  view.querySelectorAll('.chip').forEach((b) => b.addEventListener('click', () => {
    state.filter = b.dataset.f;
    renderHistory(view);
  }));
}

/* ===================== Detail ===================== */
async function renderDetail(view, id) {
  const a = state.activities.find((x) => x.id === id);
  if (!a) {
    view.innerHTML = '<a class="back" href="#/riwayat">← Riwayat</a><div class="empty">Aktivitas tidak ditemukan.</div>';
    return;
  }
  const speed = SPORTS[a.sport_type]?.speed;
  const dist = Number(a.distance_meters);
  view.innerHTML = `
    <a class="back" href="#/riwayat">← Riwayat</a>
    <div class="detail-head">
      <span class="icon-tile">${icon(a.sport_type)}</span>
      <div style="flex:1;min-width:200px">
        <div class="title-row">
          <h2 class="page" style="font-size:24px" id="act-title">${esc(titleOf(a))}</h2>
          <button class="icon-btn" type="button" id="rename" aria-label="Ubah nama aktivitas" title="Ubah nama">
            <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 20h9M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z"/></svg>
          </button>
        </div>
        <form class="rename-form" id="rename-form" hidden>
          <label class="sr-only" for="rename-input">Nama aktivitas</label>
          <input id="rename-input" maxlength="60" placeholder="Misalnya: Lari CFD Sudirman">
          <button class="btn btn-primary" type="submit">Simpan</button>
          <button class="btn btn-ghost" type="button" id="rename-auto">Nama otomatis</button>
          <button class="btn btn-ghost" type="button" id="rename-cancel">Batal</button>
        </form>
        <div class="muted">${esc(longDate.format(new Date(a.started_at)))}${isGarmin(a) ? ` · ${a.source === 'fit_file' ? 'File .FIT' : 'Health Connect'}${a.source_device ? ` (${esc(a.source_device)})` : ''}` : ''}</div>
      </div>
      <button class="btn btn-danger" type="button" id="del">Hapus</button>
    </div>
    <div class="map-wrap" id="map-wrap">
      <div class="map" id="map"><div class="no-route">Memuat rute…</div></div>
      <button class="map-btn" type="button" id="fs" aria-label="Peta layar penuh" hidden>
        <svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true" id="fs-icon"><path d="M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5"/></svg>
      </button>
      <div class="map-summary num">
        <span><span class="stat-label">Jarak</span><br><b>${fmtKm(dist)} km</b></span>
        <span><span class="stat-label">Waktu aktif</span><br><b>${fmtDuration(a.moving_seconds)}</b></span>
        <span><span class="stat-label">${speed ? 'Kecepatan' : 'Pace'}</span><br><b>${perf(a)}</b></span>
      </div>
    </div>
    <div class="grid grid-2 section-gap">
      <div class="card">
        <div class="stats-grid num">
          <div><div class="stat-label">Jarak</div><div class="stat-value">${fmtKm(dist)} <small>km</small></div></div>
          <div><div class="stat-label">Waktu aktif</div><div class="stat-value">${fmtDuration(a.moving_seconds)}</div></div>
          <div><div class="stat-label">${speed ? 'Kecepatan rata-rata' : 'Pace rata-rata'}</div><div class="stat-value">${perf(a).replace(/ (\/km|km\/j)$/, ' <small>$1</small>')}</div></div>
          <div><div class="stat-label">Elevasi naik</div><div class="stat-value">${Math.round(Number(a.elevation_gain_meters) || 0)} <small>m</small></div></div>
          <div><div class="stat-label">Kalori (est.)</div><div class="stat-value">${a.calories_estimated ?? '-'}</div></div>
          <div><div class="stat-label">Waktu total</div><div class="stat-value">${fmtDuration(a.elapsed_seconds)}</div></div>
          <div class="hl" id="max-speed" hidden></div>
          <div class="hl" id="best-pace" hidden></div>
          ${a.avg_heart_rate ? `<div><div class="stat-label">HR rata-rata</div><div class="stat-value">${a.avg_heart_rate} <small>bpm</small></div></div>` : ''}
          ${a.max_heart_rate ? `<div><div class="stat-label">HR maks</div><div class="stat-value">${a.max_heart_rate} <small>bpm</small></div></div>` : ''}
        </div>
      </div>
      <div class="card"><h3>Split per km</h3><div id="splits" class="muted">Memuat…</div></div>
    </div>`;

  const form = $('#rename-form');
  const input = $('#rename-input');
  const openRename = () => {
    form.hidden = false;
    input.value = titleOf(a);
    input.focus();
    input.select();
  };
  const saveTitle = async (title) => {
    const value = title && title.trim() ? title.trim() : null;
    try {
      await api(`/activities?id=eq.${encodeURIComponent(id)}`, {
        method: 'PATCH',
        prefer: 'return=minimal',
        body: { title: value, updated_at: new Date().toISOString() },
      });
      a.title = value;
      $('#act-title').textContent = titleOf(a);
      form.hidden = true;
    } catch (e) {
      alert(friendlyError(e));
    }
  };
  $('#rename').addEventListener('click', openRename);
  form.addEventListener('submit', (e) => { e.preventDefault(); saveTitle(input.value); });
  $('#rename-auto').addEventListener('click', () => saveTitle(null));
  $('#rename-cancel').addEventListener('click', () => { form.hidden = true; });

  $('#del').addEventListener('click', async () => {
    if (!confirm('Hapus aktivitas ini beserta rutenya? Tindakan ini tidak bisa dibatalkan.')) return;
    try {
      await api(`/activities?id=eq.${encodeURIComponent(id)}`, { method: 'DELETE' });
      state.activities = state.activities.filter((x) => x.id !== id);
      location.hash = '#/riwayat';
    } catch (e) {
      alert(friendlyError(e));
    }
  });

  let pts = [];
  try {
    pts = await api(`/activity_points?activity_id=eq.${encodeURIComponent(id)}&select=sequence_no,recorded_at,latitude,longitude,altitude_meters,segment_start&order=sequence_no`) || [];
  } catch (e) {
    $('#map').innerHTML = `<div class="no-route">${esc(friendlyError(e))}</div>`;
  }
  if (location.hash !== `#/aktivitas/${id}`) return; // pengguna sudah pindah halaman

  // Kecepatan maks: dari database, atau dihitung dari rute lalu disimpan.
  let maxMps = Number(a.max_speed_mps) || 0;
  if (!maxMps && pts.length > 1) {
    maxMps = computeMaxSpeed(pts, a.sport_type) || 0;
    if (maxMps > 0) {
      a.max_speed_mps = Math.round(maxMps * 1000) / 1000;
      api(`/activities?id=eq.${encodeURIComponent(id)}&max_speed_mps=is.null`, {
        method: 'PATCH', prefer: 'return=minimal', body: { max_speed_mps: a.max_speed_mps },
      }).catch((e) => console.warn('max speed', e));
    }
  }
  if (maxMps > 0) {
    const ms = $('#max-speed');
    ms.hidden = false;
    ms.innerHTML = `<div class="stat-label">Kecepatan maks</div><div class="stat-value lime">${fmtKmh(maxMps)} <small>km/j</small></div>`;
    if (!speed) {
      const bp = $('#best-pace');
      bp.hidden = false;
      bp.innerHTML = `<div class="stat-label">Pace tercepat</div><div class="stat-value lime">${fmtPace(1000 / maxMps)} <small>/km</small></div>`;
    }
  }

  const splits = computeSplits(pts);
  const splitBox = $('#splits');
  if (!splits.length) {
    splitBox.textContent = 'Tidak ada data rute untuk split.';
  } else {
    const full = splits.filter((s) => s.distance >= 999);
    const pace = (s) => s.seconds / (s.distance / 1000);
    const best = Math.min(...(full.length ? full : splits).map(pace));
    splitBox.classList.remove('muted');
    splitBox.innerHTML = splits.map((s) => {
      const p = pace(s);
      const label = speed ? `${(s.distance / Math.max(1, s.seconds) * 3.6).toFixed(1).replace('.', ',')}` : fmtPace(p);
      return `<div class="split-row num ${p === best ? 'best' : ''}"><span class="muted">${s.distance >= 999 ? s.number : fmtKm(s.distance)}</span><b>${label}</b><div class="bar"><div style="width:${Math.max(5, (best / p) * 100)}%"></div></div><span class="muted" style="text-align:right">${fmtDuration(s.seconds)}</span></div>`;
    }).join('');
  }

  const mapEl = $('#map');
  if (pts.length < 2 || typeof L === 'undefined') {
    mapEl.innerHTML = `<div class="no-route">${typeof L === 'undefined' ? 'Peta gagal dimuat.' : 'Tidak ada rute GPS untuk aktivitas ini.'}</div>`;
    return;
  }
  mapEl.innerHTML = '';
  detailMap = L.map(mapEl, { zoomControl: true, attributionControl: true });
  L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom: 19,
    attribution: '© OpenStreetMap contributors',
  }).addTo(detailMap);
  const segs = [];
  let cur = [];
  for (const p of pts) {
    if (p.segment_start && cur.length) { segs.push(cur); cur = []; }
    cur.push([p.latitude, p.longitude]);
  }
  if (cur.length) segs.push(cur);
  L.polyline(segs, { color: '#0B1220', weight: 9, opacity: 0.9 }).addTo(detailMap);
  const line = L.polyline(segs, { color: '#A3E635', weight: 5 }).addTo(detailMap);
  const dot = (ll, fill) => L.circleMarker(ll, { radius: 7, color: '#0B1220', weight: 3, fillColor: fill, fillOpacity: 1 }).addTo(detailMap);
  dot([pts[0].latitude, pts[0].longitude], '#F1F5F9').bindTooltip('Start');
  dot([pts.at(-1).latitude, pts.at(-1).longitude], '#EF4444').bindTooltip('Finish');
  detailMap.fitBounds(line.getBounds(), { padding: [30, 30] });

  const wrap = $('#map-wrap');
  const fsBtn = $('#fs');
  fsBtn.hidden = false;
  const setFs = (on) => {
    wrap.classList.toggle('fullscreen', on);
    fsBtn.setAttribute('aria-label', on ? 'Tutup layar penuh' : 'Peta layar penuh');
    $('#fs-icon').innerHTML = on ? '<path d="M9 4v5H4M15 4v5h5M9 20v-5H4M15 20v-5h5"/>' : '<path d="M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5"/>';
    document.body.style.overflow = on ? 'hidden' : '';
    setTimeout(() => { detailMap?.invalidateSize(); detailMap?.fitBounds(line.getBounds(), { padding: [40, 40] }); }, 50);
  };
  fsBtn.addEventListener('click', () => setFs(!wrap.classList.contains('fullscreen')));
  document.addEventListener('keydown', function onKey(e) {
    if (!detailMap) { document.removeEventListener('keydown', onKey); return; }
    if (e.key === 'Escape' && wrap.classList.contains('fullscreen')) setFs(false);
  });
}

/* ===================== Upload ===================== */
async function stableUuid(text) {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  const b = new Uint8Array(buf).slice(0, 16);
  b[6] = (b[6] & 0x0f) | 0x50; // versi 5 (berbasis nama)
  b[8] = (b[8] & 0x3f) | 0x80;
  const h = [...b].map((x) => x.toString(16).padStart(2, '0')).join('');
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}

function renderUpload(view) {
  view.innerHTML = `
    <h2 class="page">Upload & impor</h2>
    <p class="sub">File .FIT, .GPX, .TCX, atau .ZIP dari Garmin, Strava, dan aplikasi lain. Rute, jarak, waktu, dan detak jantung tersimpan ke akun Anda.</p>
    <label class="drop" id="drop" for="file">
      <svg viewBox="0 0 24 24" width="40" height="40" fill="none" stroke="#A3E635" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 16V4M7 9l5-5 5 5M4 16v3a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-3"/></svg>
      <h3>Tarik file ke sini</h3>
      <div class="muted">atau klik untuk memilih (bisa beberapa file sekaligus)</div>
      <input id="file" type="file" accept=".fit,.FIT,.gpx,.GPX,.tcx,.TCX,.zip,.ZIP,.gz" multiple hidden>
    </label>
    <ol class="steps">
      <li><b>Garmin:</b> buka <a href="https://connect.garmin.com/modern/activities" target="_blank" rel="noopener">Garmin Connect</a>, pilih aktivitas, ikon gerigi › <b>Export Original</b>. File .zip-nya bisa langsung dimasukkan.</li>
      <li><b>Strava:</b> <a href="https://www.strava.com/athlete/delete_your_account" target="_blank" rel="noopener">Settings › My Account › Download or Delete Your Account</a> › <b>Request your archive</b>. Masukkan file .zip dari email Strava; semua lari, jalan, dan sepeda dibaca beserta namanya.</li>
      <li>Aktivitas yang sudah ada dilewati, jadi aman diunggah ulang.</li>
    </ol>
    <div id="up-list" class="list section-gap"></div>
    <div class="toolbar" id="up-bar" hidden>
      <button class="btn btn-primary" type="button" id="save-all">Simpan semua</button>
      <button class="btn btn-ghost" type="button" id="clear">Bersihkan</button>
      <span class="muted" id="up-note"></span>
    </div>`;
  const drop = $('#drop');
  const input = $('#file');
  input.addEventListener('change', () => addFiles(input.files));
  ['dragenter', 'dragover'].forEach((t) => drop.addEventListener(t, (e) => { e.preventDefault(); drop.classList.add('over'); }));
  ['dragleave', 'drop'].forEach((t) => drop.addEventListener(t, (e) => { e.preventDefault(); drop.classList.remove('over'); }));
  drop.addEventListener('drop', (e) => addFiles(e.dataTransfer.files));
  $('#save-all').addEventListener('click', saveAll);
  $('#clear').addEventListener('click', () => { state.uploads = []; drawUploads(); });
  drawUploads();
}

async function addFiles(files) {
  const known = new Set(state.activities.map((a) => a.id));
  const push = async (name, fit, err, skipped) => {
    const u = { name };
    if (skipped) { u.status = 'skip'; u.note = 'Bukan lari/jalan/sepeda'; }
    else if (err) { u.status = 'err'; u.note = err; }
    else {
      u.fit = fit;
      u.id = await stableUuid(`tempuh:fit:${state.user.id}:${Math.floor(fit.startTime.getTime() / 1000)}`);
      if (known.has(u.id)) { u.status = 'skip'; u.note = 'Sudah ada'; }
      else { u.status = 'ready'; u.note = 'Siap disimpan'; known.add(u.id); }
    }
    state.uploads.push(u);
  };
  for (const file of files) {
    const reading = { name: file.name, status: 'wait', note: 'Membaca…' };
    state.uploads.push(reading);
    drawUploads();
    try {
      const bytes = new Uint8Array(await file.arrayBuffer());
      state.uploads.splice(state.uploads.indexOf(reading), 1);
      if (file.name.toLowerCase().endsWith('.zip')) {
        const items = readZip(bytes);
        if (!items.length) await push(file.name, null, 'ZIP tidak berisi file aktivitas (.fit/.gpx/.tcx)');
        for (const it of items) await push(it.name.split('/').pop(), it.fit, it.error, it.skipped);
      } else {
        await push(file.name, parseTrackBytes(file.name, bytes));
      }
    } catch (e) {
      reading.status = 'err';
      reading.note = e instanceof FitError ? e.message : `Gagal dibaca: ${e.message}`;
      if (!state.uploads.includes(reading)) state.uploads.push(reading);
    }
    drawUploads();
  }
}

function drawUploads() {
  const box = $('#up-list');
  if (!box) return;
  box.innerHTML = state.uploads.map((u) => {
    const f = u.fit;
    const meta = f
      ? `${SPORTS[f.sport].label} · ${fmtKm(f.totalDistanceMeters ?? routeDistance(f.points))} km · ${fmtDuration(f.totalTimerSeconds ?? f.totalElapsedSeconds ?? 0)} · ${esc(dateFmt.format(f.startTime))}${f.avgHeartRate ? ` · ${f.avgHeartRate} bpm` : ''} · ${f.points.length} titik GPS`
      : '';
    const cls = u.status === 'done' ? 'ok' : u.status === 'err' ? 'err' : u.status === 'skip' ? 'skip' : 'wait';
    return `<div class="upload-row">
      <span class="icon-tile">${icon(f?.sport || 'running')}</span>
      <div class="item-body"><div class="item-title">${esc(f?.title || u.name)}</div><div class="item-meta">${meta}</div></div>
      <span class="status ${cls}">${esc(u.note)}</span>
    </div>`;
  }).join('');
  const ready = state.uploads.filter((u) => u.status === 'ready').length;
  $('#up-bar').hidden = state.uploads.length === 0;
  $('#save-all').disabled = ready === 0;
  $('#up-note').textContent = ready ? `${ready} file siap disimpan` : '';
}

async function saveFit(u) {
  const f = u.fit;
  const start = f.startTime;
  const id = u.id || await stableUuid(`tempuh:fit:${state.user.id}:${Math.floor(start.getTime() / 1000)}`);
  const pts = f.points;
  const elapsed = Math.round(f.totalElapsedSeconds ?? (pts.length > 1 ? (pts.at(-1).recorded_at - pts[0].recorded_at) / 1000 : 0));
  const moving = Math.min(elapsed || Infinity, Math.round(f.totalTimerSeconds ?? elapsed));
  const dist = f.totalDistanceMeters ?? routeDistance(pts);
  const kmh = moving > 0 ? (dist / moving) * 3.6 : 0;
  const activity = {
    id,
    sport_type: f.sport,
    status: 'completed',
    started_at: start.toISOString(),
    finished_at: new Date(start.getTime() + elapsed * 1000).toISOString(),
    elapsed_seconds: elapsed,
    moving_seconds: Number.isFinite(moving) ? moving : 0,
    paused_seconds: Math.max(0, elapsed - (Number.isFinite(moving) ? moving : 0)),
    distance_meters: Math.round(dist * 100) / 100,
    average_pace_seconds_per_km: dist > 0 ? Math.round((moving / (dist / 1000)) * 100) / 100 : null,
    average_speed_mps: moving > 0 ? Math.round((dist / moving) * 1000) / 1000 : null,
    elevation_gain_meters: Math.round(f.totalAscentMeters ?? elevationGain(pts)),
    calories_estimated: f.totalCalories ?? estimateCalories(f.sport, moving, kmh),
    avg_heart_rate: f.avgHeartRate ?? null,
    max_heart_rate: f.maxHeartRate ?? null,
    max_speed_mps: (() => {
      const v = computeMaxSpeed(pts.map((p) => ({ ...p, recorded_at: p.recorded_at.toISOString() })), f.sport);
      return v ? Math.round(v * 1000) / 1000 : null;
    })(),
    source: 'fit_file',
    source_device: f.isGarmin ? 'Garmin' : u.name,
  };
  if (f.title) activity.title = f.title;
  await api('/activities?on_conflict=id', {
    method: 'POST',
    prefer: 'resolution=merge-duplicates,return=minimal',
    body: activity,
  });
  const rows = pts.map((p) => ({
    activity_id: id,
    sequence_no: p.sequence_no,
    recorded_at: p.recorded_at.toISOString(),
    latitude: p.latitude,
    longitude: p.longitude,
    altitude_meters: p.altitude,
    speed_mps: p.speed != null && p.speed >= 0 ? p.speed : null,
    heart_rate: p.heart_rate != null && p.heart_rate >= 1 && p.heart_rate <= 300 ? p.heart_rate : null,
    segment_start: p.segment_start,
    source: 'fit',
  }));
  for (let i = 0; i < rows.length; i += 1000) {
    u.note = `Menyimpan rute ${Math.min(i + 1000, rows.length)}/${rows.length}…`;
    drawUploads();
    await api('/activity_points?on_conflict=activity_id,sequence_no', {
      method: 'POST',
      prefer: 'resolution=merge-duplicates,return=minimal',
      body: rows.slice(i, i + 1000),
    });
  }
}

async function saveAll() {
  const btn = $('#save-all');
  btn.disabled = true;
  for (const u of state.uploads.filter((x) => x.status === 'ready')) {
    u.status = 'saving';
    u.note = 'Menyimpan…';
    drawUploads();
    try {
      await saveFit(u);
      u.status = 'done';
      u.note = 'Tersimpan ✓';
    } catch (e) {
      u.status = 'ready';
      u.note = `Gagal: ${friendlyError(e)}`;
    }
    drawUploads();
  }
  await loadActivities();
  btn.disabled = false;
  drawUploads();
}

/* ===================== Boot ===================== */
async function boot() {
  $('#auth-form').addEventListener('submit', onAuthSubmit);
  $('#auth-switch').addEventListener('click', () => setAuthMode(!registering));
  $('#toggle-pass').addEventListener('click', () => {
    const input = $('#auth-pass');
    const show = input.type === 'password';
    input.type = show ? 'text' : 'password';
    const btn = $('#toggle-pass');
    btn.setAttribute('aria-pressed', String(show));
    btn.setAttribute('aria-label', show ? 'Sembunyikan kata sandi' : 'Tampilkan kata sandi');
    $('#eye-icon').innerHTML = show
      ? '<path d="M3 3l18 18M10.6 10.6a3 3 0 0 0 4.2 4.2M9.9 5.2A9.8 9.8 0 0 1 12 5c6.5 0 10 7 10 7a17.6 17.6 0 0 1-3.2 4.1M6.6 6.6A17.4 17.4 0 0 0 2 12s3.5 7 10 7a9.7 9.7 0 0 0 5.4-1.6"/>'
      : '<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>';
    input.focus();
  });
  $('#logout').addEventListener('click', async () => {
    await signOut();
    state.user = null;
    state.activities = [];
    $('#app').hidden = true;
    $('#auth').hidden = false;
  });
  window.addEventListener('hashchange', () => { if (state.user) route(); });
  state.user = await currentUser();
  $('#loading').hidden = true;
  if (state.user) await enterApp();
  else $('#auth').hidden = false;
}

boot();
