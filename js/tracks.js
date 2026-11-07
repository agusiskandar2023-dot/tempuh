// Impor GPX, TCX, dan ZIP (ekspor Strava / Garmin) di browser.
// Hasil berbentuk sama dengan parseFit() agar alur simpan bisa dipakai ulang.
import { parseFit, FitError } from './fit.js';

const GAP_SECONDS = 60; // jeda lebih lama dari ini dianggap pause

export function sportFromText(s) {
  if (s == null) return null;
  const t = String(s).trim().toLowerCase();
  if (!t) return null;
  if (t === '1') return 'cycling';
  if (t === '4' || t === '10') return 'walking';
  if (t === '9') return 'running';
  if (t.includes('jog')) return 'jogging';
  if (t.includes('run') || t.includes('lari')) return 'running';
  if (t.includes('walk') || t.includes('hike') || t.includes('jalan')) return 'walking';
  if (t.includes('ride') || t.includes('bik') || t.includes('cycl') || t.includes('sepeda')) return 'cycling';
  return null;
}

function haversine(a, b) {
  const R = 6371008.8, r = Math.PI / 180;
  const dLat = (b.latitude - a.latitude) * r, dLon = (b.longitude - a.longitude) * r;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(a.latitude * r) * Math.cos(b.latitude * r) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

function build(sport, raw, { distance = null, timer = null, calories = null } = {}) {
  raw.sort((a, b) => a.recorded_at - b.recorded_at);
  if (raw.length < 2) throw new FitError('File tidak berisi rute GPS dengan waktu.');
  let paused = 0;
  const points = raw.map((p, i) => {
    let seg = false;
    if (i > 0) {
      const gap = (p.recorded_at - raw[i - 1].recorded_at) / 1000;
      if (gap > GAP_SECONDS) { seg = true; paused += gap; }
    }
    return { ...p, sequence_no: i, speed: null, segment_start: seg };
  });
  const elapsed = (points.at(-1).recorded_at - points[0].recorded_at) / 1000;
  const hrs = points.map((p) => p.heart_rate).filter((h) => h > 0);
  return {
    sport,
    startTime: points[0].recorded_at,
    totalElapsedSeconds: elapsed,
    totalTimerSeconds: timer ?? Math.max(0, elapsed - paused),
    totalDistanceMeters: distance,
    totalCalories: calories,
    avgHeartRate: hrs.length ? Math.round(hrs.reduce((a, b) => a + b, 0) / hrs.length) : null,
    maxHeartRate: hrs.length ? Math.max(...hrs) : null,
    totalAscentMeters: null,
    isGarmin: false,
    points,
    heartRates: hrs,
  };
}

const local = (el, name) => [...el.getElementsByTagName('*')].filter((e) => e.localName === name);
const firstText = (el, name) => {
  const e = local(el, name)[0];
  return e ? e.textContent.trim() : null;
};
const num = (s) => (s == null || s === '' ? null : Number(s));

export function parseGpx(text, sportHint) {
  const doc = new DOMParser().parseFromString(text, 'application/xml');
  if (doc.getElementsByTagName('parsererror').length) throw new FitError('File GPX rusak.');
  const raw = [];
  for (const pt of local(doc, 'trkpt')) {
    const time = firstText(pt, 'time');
    const lat = num(pt.getAttribute('lat')), lon = num(pt.getAttribute('lon'));
    if (!time || lat == null || lon == null) continue;
    const t = new Date(time);
    if (Number.isNaN(t.getTime())) continue;
    raw.push({ recorded_at: t, latitude: lat, longitude: lon, altitude: num(firstText(pt, 'ele')), heart_rate: num(firstText(pt, 'hr')) });
  }
  const trk = local(doc, 'trk')[0];
  const type = trk ? [...trk.children].find((c) => c.localName === 'type')?.textContent : null;
  const name = trk ? [...trk.children].find((c) => c.localName === 'name')?.textContent?.trim() : null;
  const f = build(sportHint || sportFromText(type) || 'running', raw);
  f.title = name || null;
  return f;
}

export function parseTcx(text, sportHint) {
  const doc = new DOMParser().parseFromString(text.trimStart(), 'application/xml');
  if (doc.getElementsByTagName('parsererror').length) throw new FitError('File TCX rusak.');
  const act = local(doc, 'Activity')[0];
  const sport = sportHint || sportFromText(act?.getAttribute('Sport')) || 'running';
  const raw = [];
  for (const tp of local(doc, 'Trackpoint')) {
    const time = firstText(tp, 'Time');
    const lat = num(firstText(tp, 'LatitudeDegrees')), lon = num(firstText(tp, 'LongitudeDegrees'));
    if (!time || lat == null || lon == null) continue;
    const hrEl = local(tp, 'HeartRateBpm')[0];
    raw.push({
      recorded_at: new Date(time), latitude: lat, longitude: lon,
      altitude: num(firstText(tp, 'AltitudeMeters')),
      heart_rate: hrEl ? num(firstText(hrEl, 'Value')) : null,
    });
  }
  let dist = null, timer = null, kcal = null;
  for (const lap of local(doc, 'Lap')) {
    const direct = (n) => [...lap.children].find((c) => c.localName === n)?.textContent;
    const t = num(direct('TotalTimeSeconds')), d = num(direct('DistanceMeters')), c = num(direct('Calories'));
    if (t != null) timer = (timer ?? 0) + t;
    if (d != null) dist = (dist ?? 0) + d;
    if (c != null) kcal = (kcal ?? 0) + c;
  }
  const f = build(sport, raw, { distance: dist, timer, calories: kcal });
  f.title = null;
  return f;
}

export function isTrackName(n) {
  const l = n.toLowerCase();
  return ['.fit', '.gpx', '.tcx', '.fit.gz', '.gpx.gz', '.tcx.gz'].some((x) => l.endsWith(x));
}

/** Membaca satu file non-ZIP. `bytes`: Uint8Array. */
export function parseTrackBytes(name, bytes, { sport = null, title = null } = {}) {
  let n = name.toLowerCase();
  let data = bytes;
  if (n.endsWith('.gz')) {
    if (typeof fflate === 'undefined') throw new FitError('Pustaka unzip gagal dimuat.');
    data = fflate.gunzipSync(bytes);
    n = n.slice(0, -3);
  }
  let f;
  if (n.endsWith('.fit')) {
    f = parseFit(data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength));
    if (sport) f.sport = sport;
  } else if (n.endsWith('.gpx')) {
    f = parseGpx(new TextDecoder().decode(data), sport);
  } else if (n.endsWith('.tcx')) {
    f = parseTcx(new TextDecoder().decode(data), sport);
  } else {
    throw new FitError('Format tidak didukung. Pakai .fit, .gpx, .tcx, atau .zip.');
  }
  if (title) f.title = title;
  if (!f.startTime) throw new FitError('Waktu mulai tidak ditemukan');
  return f;
}

export function parseCsv(text) {
  const rows = [];
  let row = [], cell = '', q = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (q) {
      if (c === '"') { if (text[i + 1] === '"') { cell += '"'; i++; } else q = false; } else cell += c;
    } else if (c === '"') q = true;
    else if (c === ',') { row.push(cell); cell = ''; }
    else if (c === '\n' || c === '\r') {
      if (c === '\r' && text[i + 1] === '\n') i++;
      row.push(cell); cell = ''; rows.push(row); row = [];
    } else cell += c;
  }
  if (cell || row.length) { row.push(cell); rows.push(row); }
  return rows;
}

/** activities.csv ekspor Strava → { filename: {title, sport, skip} }. */
export function stravaMeta(csv) {
  const rows = parseCsv(csv);
  if (!rows.length) return {};
  const h = rows[0].map((x) => x.trim().toLowerCase());
  const iName = h.indexOf('activity name'), iType = h.indexOf('activity type'), iFile = h.indexOf('filename');
  if (iFile < 0) return {};
  const out = {};
  for (const r of rows.slice(1)) {
    const file = (r[iFile] || '').trim();
    if (!file) continue;
    const type = iType >= 0 ? r[iType] : null;
    const sport = sportFromText(type);
    out[file] = { title: iName >= 0 && r[iName]?.trim() ? r[iName].trim() : null, sport, skip: !!(type && type.trim() && !sport) };
  }
  return out;
}

/** Membuka ZIP; mengembalikan daftar {name, fit | error | skipped}. */
export function readZip(bytes) {
  if (typeof fflate === 'undefined') throw new FitError('Pustaka unzip gagal dimuat.');
  const files = fflate.unzipSync(bytes, {
    filter: (f) => isTrackName(f.name) || f.name.toLowerCase().endsWith('activities.csv'),
  });
  const csvName = Object.keys(files).find((n) => n.toLowerCase().endsWith('activities.csv'));
  const meta = csvName ? stravaMeta(new TextDecoder().decode(files[csvName])) : {};
  const out = [];
  for (const [name, data] of Object.entries(files)) {
    if (!isTrackName(name)) continue;
    const m = meta[name] || Object.entries(meta).find(([k]) => name.endsWith(k))?.[1];
    if (m?.skip) { out.push({ name, skipped: true }); continue; }
    try {
      out.push({ name, fit: parseTrackBytes(name, data, { sport: m?.sport, title: m?.title }) });
    } catch (e) {
      out.push({ name, error: e instanceof FitError ? e.message : `Gagal dibaca: ${e.message}` });
    }
  }
  return out;
}

export { haversine };
