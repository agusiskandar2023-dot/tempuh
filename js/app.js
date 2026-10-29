import { WEEKLY_TARGET_KM } from '../config.js';
import { signIn, signUp, signOut, currentUser, api, ApiError } from './neon.js';
import { parseFit, FitError } from './fit.js';
import {
  SPORTS, fmtKm, fmtDuration, fmtPace, perf, computeSplits, routeDistance,
  elevationGain, estimateCalories,
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

const state = { user: null, activities: [], loaded: false, filter: 'all', uploads: [] };

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
      '/activities?select=id,sport_type,title,started_at,finished_at,elapsed_seconds,moving_seconds,paused_seconds,distance_meters,elevation_gain_meters,calories_estimated,avg_heart_rate,max_heart_rate,source,source_device&status=eq.completed&order=started_at.desc',
    ) || [];
  } catch (e) {
    state.activities = [];
    state.loadError = friendlyError(e);
  }
  state.loaded = true;
}

/* ===================== Router ===================== */
let detailMap = null;
function route() {
  if (detailMap) { detailMap.remove(); detailMap = null; }
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
  else renderDashboard(view);
  window.scrollTo(0, 0);
}

/* ===================== Dashboard ===================== */
function startOfWeek(d) {
  const x = new Date(d.getFullYear(), d.getMonth(), d.getDate());
  const day = (x.getDay() + 6) % 7; // Senin = 0
  x.setDate(x.getDate() - day);
  return x;
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

function weeklyChart(weeks) {
  const W = 640, H = 200, padL = 36, padB = 28, padT = 16;
  const max = Math.max(1, ...weeks.map((w) => w.km));
  const step = max > 40 ? 20 : max > 20 ? 10 : max > 8 ? 5 : 2;
  const top = Math.ceil(max / step) * step;
  const bw = (W - padL) / weeks.length;
  const y = (v) => padT + (H - padT - padB) * (1 - v / top);
  let svg = `<svg viewBox="0 0 ${W} ${H}" role="img" aria-label="Jarak per minggu, 12 minggu terakhir">`;
  for (let v = 0; v <= top; v += step) {
    svg += `<line x1="${padL}" x2="${W}" y1="${y(v)}" y2="${y(v)}" stroke="#243049" stroke-width="1"/>`;
    svg += `<text x="${padL - 8}" y="${y(v) + 4}" fill="#94A3B8" font-size="11" text-anchor="end">${v}</text>`;
  }
  weeks.forEach((w, i) => {
    const x = padL + i * bw + bw * 0.18;
    const h = Math.max(0, y(0) - y(w.km));
    const last = i === weeks.length - 1;
    svg += `<rect x="${x}" y="${y(w.km)}" width="${bw * 0.64}" height="${h}" rx="4" fill="${last ? '#A3E635' : '#64748B'}"><title>${w.label}: ${w.km.toFixed(1)} km</title></rect>`;
    if (i % 2 === weeks.length % 2 || last) {
      svg += `<text x="${x + bw * 0.32}" y="${H - 8}" fill="${last ? '#F1F5F9' : '#94A3B8'}" font-size="11" text-anchor="middle">${w.label}</text>`;
    }
  });
  return svg + '</svg>';
}

function renderDashboard(view) {
  const acts = state.activities;
  const now = new Date();
  const wk = startOfWeek(now);
  const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);
  const sum = (list) => ({
    km: list.reduce((s, a) => s + Number(a.distance_meters) / 1000, 0),
    sec: list.reduce((s, a) => s + (a.moving_seconds || 0), 0),
    n: list.length,
  });
  const thisWeek = sum(acts.filter((a) => new Date(a.started_at) >= wk));
  const thisMonth = sum(acts.filter((a) => new Date(a.started_at) >= monthStart));
  const all = sum(acts);
  const weeks = [];
  for (let i = 11; i >= 0; i--) {
    const s = new Date(wk); s.setDate(s.getDate() - 7 * i);
    const e = new Date(s); e.setDate(e.getDate() + 7);
    const km = acts.filter((a) => { const d = new Date(a.started_at); return d >= s && d < e; })
      .reduce((t, a) => t + Number(a.distance_meters) / 1000, 0);
    weeks.push({ km, label: `${s.getDate()}/${s.getMonth() + 1}` });
  }
  const bySport = Object.keys(SPORTS).map((k) => ({ k, ...sum(acts.filter((a) => a.sport_type === k)) }));
  const maxSport = Math.max(1, ...bySport.map((s) => s.km));
  const pct = Math.min(100, (thisWeek.km / WEEKLY_TARGET_KM) * 100);
  const name = state.user.name ? `, ${esc(state.user.name.split(' ')[0])}` : '';

  view.innerHTML = `
    <h2 class="page">Halo${name}</h2>
    <p class="sub">Ringkasan aktivitas Anda.${state.loadError ? ` <span style="color:#fca5a5">${esc(state.loadError)}</span>` : ''}</p>
    <div class="grid grid-4">
      <div class="card">
        <div class="stat-label">Minggu ini</div>
        <div class="stat-value num">${thisWeek.km.toFixed(1).replace('.', ',')} <small>/ ${WEEKLY_TARGET_KM} km</small></div>
        <div class="progress" role="progressbar" aria-valuenow="${Math.round(pct)}" aria-valuemin="0" aria-valuemax="100" aria-label="Progres target mingguan"><div style="width:${pct}%"></div></div>
      </div>
      <div class="card"><div class="stat-label">Bulan ini</div><div class="stat-value num">${thisMonth.km.toFixed(1).replace('.', ',')} <small>km</small></div><div class="muted">${thisMonth.n} aktivitas · ${fmtDuration(thisMonth.sec)}</div></div>
      <div class="card"><div class="stat-label">Waktu aktif minggu ini</div><div class="stat-value num">${fmtDuration(thisWeek.sec)}</div><div class="muted">${thisWeek.n} aktivitas</div></div>
      <div class="card"><div class="stat-label">Total semua</div><div class="stat-value num">${all.km.toFixed(1).replace('.', ',')} <small>km</small></div><div class="muted">${all.n} aktivitas</div></div>
    </div>
    <div class="grid grid-2 section-gap">
      <div class="card chart"><h3>Jarak per minggu <span class="muted">(km, 12 minggu)</span></h3>${weeklyChart(weeks)}</div>
      <div class="card">
        <h3>Per jenis olahraga</h3>
        ${bySport.map((s) => `<div class="sport-row"><span>${SPORTS[s.k].label}</span><div class="bar"><div style="width:${(s.km / maxSport) * 100}%"></div></div><span class="num muted" style="text-align:right">${s.km.toFixed(1).replace('.', ',')} km</span></div>`).join('')}
      </div>
    </div>
    <div class="section-gap">
      <div style="display:flex;align-items:center;gap:12px;margin-bottom:10px">
        <h3 style="margin:0;font-size:17px">Aktivitas terakhir</h3><span class="spacer"></span><a href="#/riwayat">Lihat semua</a>
      </div>
      ${acts.length ? `<div class="list">${acts.slice(0, 5).map(itemHtml).join('')}</div>`
        : `<div class="empty">Belum ada aktivitas. <a href="#/upload">Upload file .FIT dari Garmin</a> atau sinkronkan dari aplikasi HP.</div>`}
    </div>`;
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
    <h2 class="page">Upload dari Garmin</h2>
    <p class="sub">Masukkan file .FIT; rute, jarak, waktu, dan detak jantung tersimpan ke akun Anda.</p>
    <label class="drop" id="drop" for="file">
      <svg viewBox="0 0 24 24" width="40" height="40" fill="none" stroke="#A3E635" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 16V4M7 9l5-5 5 5M4 16v3a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-3"/></svg>
      <h3>Tarik file .FIT ke sini</h3>
      <div class="muted">atau klik untuk memilih (bisa beberapa file sekaligus)</div>
      <input id="file" type="file" accept=".fit,.FIT" multiple hidden>
    </label>
    <ol class="steps">
      <li>Buka <a href="https://connect.garmin.com/modern/activities" target="_blank" rel="noopener">Garmin Connect</a> di browser, pilih aktivitas.</li>
      <li>Klik ikon gerigi › <b>Export Original</b>, lalu ekstrak file .zip yang terunduh.</li>
      <li>Masukkan file <b>.fit</b> di atas. Upload ulang file yang sama tidak membuat data ganda.</li>
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
  for (const file of files) {
    const u = { name: file.name, status: 'wait', note: 'Membaca…' };
    state.uploads.push(u);
    drawUploads();
    try {
      const fit = parseFit(await file.arrayBuffer());
      if (!fit.startTime) throw new FitError('Waktu mulai tidak ditemukan');
      u.fit = fit;
      u.status = 'ready';
      u.note = 'Siap disimpan';
    } catch (e) {
      u.status = 'err';
      u.note = e instanceof FitError ? e.message : `Gagal dibaca: ${e.message}`;
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
    const cls = u.status === 'done' ? 'ok' : u.status === 'err' ? 'err' : 'wait';
    return `<div class="upload-row">
      <span class="icon-tile">${icon(f?.sport || 'running')}</span>
      <div class="item-body"><div class="item-title">${esc(u.name)}</div><div class="item-meta">${meta}</div></div>
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
  const id = await stableUuid(`tempuh:fit:${state.user.id}:${Math.floor(start.getTime() / 1000)}`);
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
    source: 'fit_file',
    source_device: f.isGarmin ? 'Garmin' : u.name,
  };
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
