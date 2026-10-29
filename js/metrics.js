// Perhitungan metrik (port dari lib/domain/metrics.dart).

export function haversine(lat1, lon1, lat2, lon2) {
  const R = 6371000;
  const r = (d) => (d * Math.PI) / 180;
  const dLat = r(lat2 - lat1);
  const dLon = r(lon2 - lon1);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(r(lat1)) * Math.cos(r(lat2)) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(a)));
}

/** Jarak total, abaikan lompatan antar segmen (pause). */
export function routeDistance(pts) {
  let d = 0;
  for (let i = 1; i < pts.length; i++) {
    if (pts[i].segment_start) continue;
    d += haversine(pts[i - 1].latitude, pts[i - 1].longitude, pts[i].latitude, pts[i].longitude);
  }
  return d;
}

export function elevationGain(pts) {
  let gain = 0, ref = null;
  for (const p of pts) {
    if (p.altitude == null) continue;
    if (ref == null) ref = p.altitude;
    else if (p.altitude > ref + 3) { gain += p.altitude - ref; ref = p.altitude; }
    else if (p.altitude < ref - 3) ref = p.altitude;
  }
  return gain;
}

/** Split per km berdasarkan waktu bergerak. */
export function computeSplits(pts, splitMeters = 1000) {
  const out = [];
  let segDist = 0, segTime = 0;
  const t = (p) => new Date(p.recorded_at).getTime() / 1000;
  for (let i = 1; i < pts.length; i++) {
    const a = pts[i - 1], b = pts[i];
    if (b.segment_start) continue;
    let d = haversine(a.latitude, a.longitude, b.latitude, b.longitude);
    let dt = t(b) - t(a);
    while (segDist + d >= splitMeters && d > 0) {
      const need = splitMeters - segDist;
      const frac = need / d;
      segTime += dt * frac;
      out.push({ number: out.length + 1, distance: splitMeters, seconds: Math.round(segTime) });
      d -= need;
      dt -= dt * frac;
      segDist = 0;
      segTime = 0;
    }
    segDist += d;
    segTime += dt;
  }
  if (segDist >= 50) out.push({ number: out.length + 1, distance: segDist, seconds: Math.round(segTime) });
  return out;
}

export function estimateCalories(sport, movingSeconds, avgKmh, weightKg = 70) {
  let met;
  if (sport === 'walking') met = avgKmh < 4.5 ? 3.0 : 4.3;
  else if (sport === 'jogging') met = 7.0;
  else if (sport === 'running') met = avgKmh < 9.5 ? 9.0 : 11.0;
  else met = avgKmh < 16 ? 4.0 : avgKmh < 22 ? 8.0 : 10.0;
  return Math.round((met * weightKg * movingSeconds) / 3600);
}

export const fmtKm = (m) => (m / 1000).toFixed(2).replace('.', ',');

export function fmtDuration(s) {
  s = Math.max(0, Math.round(s || 0));
  const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60;
  const mm = String(m).padStart(2, '0'), ss = String(sec).padStart(2, '0');
  return h > 0 ? `${h}:${mm}:${ss}` : `${mm}:${ss}`;
}

export function fmtPace(secPerKm) {
  if (!secPerKm || secPerKm <= 0 || secPerKm > 3600) return '--:--';
  const t = Math.round(secPerKm);
  return `${Math.floor(t / 60)}:${String(t % 60).padStart(2, '0')}`;
}

export const SPORTS = {
  running: { label: 'Lari', speed: false },
  jogging: { label: 'Jogging', speed: false },
  walking: { label: 'Jalan Kaki', speed: false },
  cycling: { label: 'Sepeda', speed: true },
};

export function perf(a) {
  const dist = Number(a.distance_meters) || 0;
  const mov = Number(a.moving_seconds) || 0;
  if (SPORTS[a.sport_type]?.speed) {
    return `${(mov > 0 ? (dist / mov) * 3.6 : 0).toFixed(1).replace('.', ',')} km/j`;
  }
  return `${fmtPace(dist > 0 ? mov / (dist / 1000) : 0)} /km`;
}
