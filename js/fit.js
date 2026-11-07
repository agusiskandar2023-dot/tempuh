// Parser .FIT minimal (port dari lib/services/fit_parser.dart di aplikasi HP).
// Membaca file_id, session, event (timer start/stop), dan record.

const FIT_EPOCH = 631065600; // 1989-12-31T00:00:00Z
const SEMI = 180 / 2147483648;

export class FitError extends Error {}

function readInt(dv, pos, size, baseType, little) {
  const base = baseType & 0x1f;
  if (pos + size > dv.byteLength) return null;
  let v;
  switch (base) {
    case 0: case 2: case 10: case 13:
      if (size !== 1) return null;
      v = dv.getUint8(pos);
      return base === 10 ? (v === 0 ? null : v) : (v === 0xff ? null : v);
    case 1:
      if (size !== 1) return null;
      v = dv.getInt8(pos);
      return v === 0x7f ? null : v;
    case 3:
      if (size !== 2) return null;
      v = dv.getInt16(pos, little);
      return v === 0x7fff ? null : v;
    case 4: case 11:
      if (size !== 2) return null;
      v = dv.getUint16(pos, little);
      return base === 11 ? (v === 0 ? null : v) : (v === 0xffff ? null : v);
    case 5:
      if (size !== 4) return null;
      v = dv.getInt32(pos, little);
      return v === 0x7fffffff ? null : v;
    case 6: case 12:
      if (size !== 4) return null;
      v = dv.getUint32(pos, little);
      return base === 12 ? (v === 0 ? null : v) : (v === 0xffffffff ? null : v);
    default:
      return null;
  }
}

const toDate = (fitSeconds) => new Date((fitSeconds + FIT_EPOCH) * 1000);

function mapSport(s) {
  if (s === 2) return 'cycling';
  if (s === 11 || s === 17) return 'walking';
  return 'running';
}

/** @param {ArrayBuffer} buffer */
export function parseFit(buffer) {
  const bytes = new Uint8Array(buffer);
  if (bytes.length < 12) throw new FitError('File terlalu kecil');
  const dv = new DataView(buffer);
  const headerSize = bytes[0];
  if (headerSize !== 12 && headerSize !== 14) throw new FitError('Header FIT tidak dikenal');
  if (String.fromCharCode(...bytes.slice(8, 12)) !== '.FIT') throw new FitError('Bukan file .FIT');
  const dataSize = dv.getUint32(4, true);
  const end = Math.min(headerSize + dataSize, bytes.length);

  const defs = new Map();
  let pos = headerSize;
  let lastTs = null;
  let sport = null, sessionStart = null, elapsed = null, timer = null, distance = null;
  let calories = null, avgHr = null, maxHr = null, ascent = null, manufacturer = null;
  const points = [];
  const heartRates = [];
  let nextSegment = false;
  let timerStopped = false;

  while (pos < end) {
    const header = bytes[pos++];
    let local;
    let compressedTs = null;
    if (header & 0x80) {
      local = (header >> 5) & 0x03;
      const offset = header & 0x1f;
      if (lastTs != null) {
        let ts = (lastTs & ~0x1f) + offset;
        if (offset < (lastTs & 0x1f)) ts += 0x20;
        compressedTs = ts >>> 0;
        lastTs = compressedTs;
      }
    } else if (header & 0x40) {
      local = header & 0x0f;
      const hasDev = (header & 0x20) !== 0;
      if (pos + 5 > end) break;
      const little = bytes[pos + 1] !== 1;
      const globalNum = dv.getUint16(pos + 2, little);
      const n = bytes[pos + 4];
      pos += 5;
      const fields = [];
      for (let i = 0; i < n; i++) {
        fields.push({ num: bytes[pos], size: bytes[pos + 1], type: bytes[pos + 2] });
        pos += 3;
      }
      let devSize = 0;
      if (hasDev) {
        const nd = bytes[pos++];
        for (let i = 0; i < nd; i++) { devSize += bytes[pos + 1]; pos += 3; }
      }
      defs.set(local, { globalNum, little, fields, devSize });
      continue;
    } else {
      local = header & 0x0f;
    }
    const def = defs.get(local);
    if (!def) throw new FitError(`Pesan tanpa definisi (local ${local})`);
    const v = {};
    for (const f of def.fields) {
      const x = readInt(dv, pos, f.size, f.type, def.little);
      if (x != null) v[f.num] = x;
      pos += f.size;
    }
    pos += def.devSize;
    if (v[253] != null) lastTs = v[253];
    const when = v[253] ?? compressedTs;

    switch (def.globalNum) {
      case 0:
        manufacturer = v[1] ?? manufacturer;
        break;
      case 21:
        if (v[0] === 0) {
          if (v[1] === 1 || v[1] === 4) timerStopped = true;
          else if (v[1] === 0 && timerStopped) { timerStopped = false; nextSegment = points.length > 0; }
        }
        break;
      case 18:
        sport = v[5] ?? sport;
        sessionStart = v[2] ?? sessionStart;
        if (v[7] != null) elapsed = v[7] / 1000;
        if (v[8] != null) timer = v[8] / 1000;
        if (v[9] != null) distance = v[9] / 100;
        calories = v[11] ?? calories;
        avgHr = v[16] ?? avgHr;
        maxHr = v[17] ?? maxHr;
        ascent = v[22] ?? ascent;
        break;
      case 20: {
        const hr = v[3];
        if (hr != null) heartRates.push(hr);
        if (v[0] == null || v[1] == null || when == null) break;
        const altRaw = v[78] ?? v[2];
        const spdRaw = v[73] ?? v[6];
        points.push({
          sequence_no: points.length,
          recorded_at: toDate(when),
          latitude: v[0] * SEMI,
          longitude: v[1] * SEMI,
          altitude: altRaw == null ? null : altRaw / 5 - 500,
          speed: spdRaw == null ? null : spdRaw / 1000,
          heart_rate: hr ?? null,
          segment_start: nextSegment,
        });
        nextSegment = false;
        break;
      }
    }
  }
  if (avgHr == null && heartRates.length) {
    avgHr = Math.round(heartRates.reduce((a, b) => a + b, 0) / heartRates.length);
    maxHr = Math.max(...heartRates);
  }
  return {
    sport: mapSport(sport),
    startTime: sessionStart != null ? toDate(sessionStart) : (points[0]?.recorded_at ?? null),
    totalElapsedSeconds: elapsed,
    totalTimerSeconds: timer,
    totalDistanceMeters: distance,
    totalCalories: calories,
    avgHeartRate: avgHr,
    maxHeartRate: maxHr,
    totalAscentMeters: ascent,
    isGarmin: manufacturer === 1,
    points,
    heartRates,
  };
}
