import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../data/database.dart';
import '../models/activity.dart';

/// Konfigurasi Neon (alamat publik, bukan rahasia; data dilindungi login +
/// row-level security). Sama dengan web/config.js.
class CloudConfig {
  static const authUrl =
      'https://ep-ancient-smoke-azbojehs.neonauth.c-3.ap-southeast-1.aws.neon.tech/neondb/auth';
  static const apiUrl =
      'https://ep-ancient-smoke-azbojehs.apirest.c-3.ap-southeast-1.aws.neon.tech/neondb/rest/v1';

  /// Origin yang terdaftar sebagai trusted domain di Neon Auth.
  static const origin = 'https://agusiskandar2023-dot.github.io';
  static const webUrl = 'https://agusiskandar2023-dot.github.io/tempuh/';
}

class CloudException implements Exception {
  final String message;
  final int? status;
  CloudException(this.message, [this.status]);
  @override
  String toString() => message;
}

/// UUID deterministik (format v5) dari teks — sama persis dengan
/// `stableUuid` di web, sehingga file .FIT yang sama yang diunggah lewat
/// web maupun HP menjadi satu aktivitas, bukan dua.
String stableUuid(String text) {
  final b = sha256.convert(utf8.encode(text)).bytes.sublist(0, 16);
  b[6] = (b[6] & 0x0f) | 0x50;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

final _cookieRe = RegExp(
    r'(?:^|[;,]\s*)((?:__Secure-|__Host-)?[A-Za-z0-9_.-]*auth[A-Za-z0-9_.-]*)=([^;,\s]*)');

/// Mengambil cookie Neon Auth dari header Set-Cookie. dart:io menggabungkan
/// beberapa Set-Cookie dengan koma, dan tanggal Expires juga berisi koma,
/// jadi hanya cookie yang namanya mengandung "auth" yang diambil.
Map<String, String> parseAuthCookies(String? setCookie) {
  final out = <String, String>{};
  if (setCookie == null || setCookie.isEmpty) return out;
  for (final m in _cookieRe.allMatches(setCookie)) {
    out[m.group(1)!] = m.group(2)!;
  }
  return out;
}

final _uuidRe = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');

class SyncResult {
  final int pushed;
  final int pulled;
  final int deleted;
  const SyncResult(this.pushed, this.pulled, this.deleted);
  bool get changedLocal => pulled > 0;
}

/// Login Neon Auth + sinkron dua arah aktivitas HP <-> Neon.
///
/// Data lokal tidak pernah dihapus oleh proses sinkron; yang dihapus hanya
/// aktivitas yang memang dihapus pengguna di HP (ikut dihapus di server).
class CloudService extends ChangeNotifier {
  CloudService({AppDatabase? db, http.Client? client})
      : _db = db ?? AppDatabase.instance,
        _http = client ?? http.Client();

  final AppDatabase _db;
  final http.Client _http;
  final _storage = const FlutterSecureStorage();

  String? _session;

  /// Cookie sesi dari Neon Auth (nama -> nilai), dikirim balik seperti
  /// browser. Neon Auth mengenali sesi lewat cookie, bukan bearer token.
  final Map<String, String> _cookies = {};
  String? _jwt;
  int _jwtExp = 0;

  String? userId;
  String? email;
  String? name;
  bool syncing = false;
  DateTime? lastSync;
  String? lastError;
  int pending = 0;

  /// Info diagnosa singkat (langkah auth terakhir + status HTTP).
  String? lastAuthStatus;

  /// Dipanggil setelah sinkron mengubah data lokal (misalnya menarik
  /// aktivitas dari web), agar daftar di layar dimuat ulang.
  VoidCallback? onLocalChanged;

  Timer? _debounce;

  bool get loggedIn => _session != null && userId != null;

  Future<void> init() async {
    try {
      _session = await _storage.read(key: 'neon_session');
      final c = await _storage.read(key: 'neon_cookies');
      if (c != null) {
        _cookies.addAll(Map<String, String>.from(jsonDecode(c) as Map));
      }
      userId = await _storage.read(key: 'neon_user_id');
      email = await _storage.read(key: 'neon_email');
      name = await _storage.read(key: 'neon_name');
      final ls = await _storage.read(key: 'last_sync');
      if (ls != null) lastSync = DateTime.tryParse(ls);
    } catch (_) {}
    await refreshPending();
    notifyListeners();
    if (loggedIn) requestSync(delay: const Duration(seconds: 2));
  }

  Future<void> refreshPending() async {
    pending = (await _db.activitiesToPush()).length;
  }

  // ---------------- Auth ----------------

  Map<String, String> _authHeaders() => {
        'Content-Type': 'application/json',
        'Origin': CloudConfig.origin,
        if (_session != null) 'Authorization': 'Bearer $_session',
        if (_cookies.isNotEmpty)
          'Cookie': _cookies.entries.map((e) => '${e.key}=${e.value}').join('; '),
      };

  void _captureCookies(String? setCookie) {
    parseAuthCookies(setCookie).forEach((name, value) {
      if (value.isEmpty) {
        _cookies.remove(name);
      } else {
        _cookies[name] = value;
      }
    });
  }

  Future<Map<String, dynamic>?> _auth(String path,
      {String method = 'GET', Map<String, dynamic>? body}) async {
    final uri = Uri.parse('${CloudConfig.authUrl}$path');
    final res = method == 'POST'
        ? await _http.post(uri, headers: _authHeaders(), body: jsonEncode(body ?? {}))
        : await _http.get(uri, headers: _authHeaders());
    final bearer = res.headers['set-auth-token'];
    if (bearer != null && bearer.isNotEmpty) _session = bearer;
    _captureCookies(res.headers['set-cookie']);
    _rememberJwt(res.headers['set-auth-jwt']);
    lastAuthStatus = '$path → HTTP ${res.statusCode}';
    dynamic data;
    try {
      data = res.body.isEmpty ? null : jsonDecode(res.body);
    } catch (_) {
      data = null;
    }
    if (res.statusCode >= 400) {
      final msg = data is Map ? (data['message'] ?? data['error'] ?? '').toString() : '';
      throw CloudException(_friendlyAuth(res.statusCode, msg), res.statusCode);
    }
    return data is Map<String, dynamic> ? data : null;
  }

  String _friendlyAuth(int status, String msg) {
    if (RegExp('already|exist', caseSensitive: false).hasMatch(msg)) {
      return 'Email ini sudah terdaftar. Silakan masuk.';
    }
    if (status == 401 || RegExp('invalid', caseSensitive: false).hasMatch(msg)) {
      return 'Email atau kata sandi salah.';
    }
    if (RegExp('password', caseSensitive: false).hasMatch(msg)) {
      return 'Kata sandi minimal 8 karakter.';
    }
    return msg.isEmpty ? 'Gagal login (HTTP $status).' : msg;
  }

  void _rememberJwt(String? jwt) {
    if (jwt == null || jwt.split('.').length != 3) return;
    try {
      final payload = jsonDecode(utf8.decode(
          base64Url.decode(base64Url.normalize(jwt.split('.')[1])))) as Map;
      _jwt = jwt;
      _jwtExp = (payload['exp'] as num?)?.toInt() ?? 0;
      final sub = payload['sub'];
      if (sub is String && userId == null) userId = sub;
    } catch (_) {}
  }

  Future<void> _afterLogin(Map<String, dynamic>? data, String fallbackEmail) async {
    final token = data?['token'];
    if (token is String && token.isNotEmpty) _session = token;
    final user = data?['user'];
    if (user is Map) {
      userId = user['id']?.toString();
      email = user['email']?.toString() ?? fallbackEmail;
      name = user['name']?.toString();
    }
    if (_session == null) {
      throw CloudException('Login berhasil tetapi token sesi tidak diterima.');
    }
    if (userId == null) {
      final s = await _auth('/get-session');
      final u = s?['user'];
      if (u is Map) {
        userId = u['id']?.toString();
        email = u['email']?.toString() ?? fallbackEmail;
        name = u['name']?.toString();
      }
    }
    if (userId == null) throw CloudException('Tidak bisa membaca data akun.');
    await _storage.write(key: 'neon_session', value: _session);
    await _storage.write(key: 'neon_cookies', value: jsonEncode(_cookies));
    await _storage.write(key: 'neon_user_id', value: userId);
    await _storage.write(key: 'neon_email', value: email);
    if (name != null) await _storage.write(key: 'neon_name', value: name);
    lastError = null;
    notifyListeners();
    unawaited(sync());
  }

  Future<void> signIn(String email, String password) async {
    final data =
        await _auth('/sign-in/email', method: 'POST', body: {'email': email, 'password': password});
    await _afterLogin(data, email);
  }

  Future<void> signUp(String name, String email, String password) async {
    final data = await _auth('/sign-up/email',
        method: 'POST', body: {'name': name, 'email': email, 'password': password});
    await _afterLogin(data, email);
  }

  Future<void> signOut() async {
    try {
      await _auth('/sign-out', method: 'POST');
    } catch (_) {}
    _session = null;
    _cookies.clear();
    _jwt = null;
    userId = null;
    email = null;
    name = null;
    for (final k in ['neon_session', 'neon_cookies', 'neon_user_id', 'neon_email', 'neon_name', 'last_sync']) {
      await _storage.delete(key: k);
    }
    lastSync = null;
    notifyListeners();
  }

  Future<String> _getJwt() async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (_jwt != null && _jwtExp - 60 > now) return _jwt!;
    String? step1, step2;
    try {
      final data = await _auth('/token');
      _rememberJwt(data?['token'] as String?);
    } catch (e) {
      step1 = '$e';
    }
    step1 ??= lastAuthStatus;
    if (_jwt == null || _jwtExp - 60 <= now) {
      try {
        final s = await _auth('/get-session');
        if (s == null || s['user'] == null) step2 = 'get-session kosong';
      } catch (e) {
        step2 = '$e';
      }
      step2 ??= lastAuthStatus;
    }
    if (_jwt == null || _jwtExp - 60 <= now) {
      final noCookie = _cookies.isEmpty ? ' (cookie sesi belum ada — keluar lalu masuk lagi)' : '';
      throw CloudException(
          'Sesi tidak dikenali server$noCookie. [token: $step1; session: $step2]', 401);
    }
    return _jwt!;
  }

  // ---------------- Data API ----------------

  Future<dynamic> _api(String path,
      {String method = 'GET', Object? body, String? prefer}) async {
    final jwt = await _getJwt();
    final uri = Uri.parse('${CloudConfig.apiUrl}$path');
    final headers = {
      'Authorization': 'Bearer $jwt',
      'Content-Type': 'application/json',
      if (prefer != null) 'Prefer': prefer,
    };
    late http.Response res;
    switch (method) {
      case 'POST':
        res = await _http.post(uri, headers: headers, body: jsonEncode(body));
      case 'DELETE':
        res = await _http.delete(uri, headers: headers);
      default:
        res = await _http.get(uri, headers: headers);
    }
    if (res.statusCode >= 400) {
      String msg = 'HTTP ${res.statusCode}';
      try {
        final m = jsonDecode(res.body);
        if (m is Map && m['message'] != null) msg = '${m['message']}';
      } catch (_) {}
      throw CloudException('Server: $msg', res.statusCode);
    }
    if (res.body.isEmpty) return null;
    return jsonDecode(res.body);
  }

  // ---------------- Sinkron ----------------

  /// Minta sinkron sebentar lagi (digabung bila dipanggil berkali-kali).
  void requestSync({Duration delay = const Duration(seconds: 3)}) {
    if (!loggedIn) {
      refreshPending().then((_) => notifyListeners());
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(delay, () => sync());
  }

  String cloudIdFor(Activity a, String? existing) {
    if (existing != null) return existing;
    if (_uuidRe.hasMatch(a.id)) return a.id;
    if (a.id.startsWith('fit-')) {
      return stableUuid('tempuh:fit:$userId:${a.id.substring(4)}');
    }
    return stableUuid('tempuh:local:$userId:${a.id}');
  }

  Future<SyncResult?> sync() async {
    if (!loggedIn || syncing) return null;
    syncing = true;
    lastError = null;
    notifyListeners();
    var pushed = 0, pulled = 0, deleted = 0;
    try {
      // 0. Pastikan profil ada (aktivitas mereferensikan profiles.id).
      await _api('/profiles?on_conflict=id',
          method: 'POST',
          prefer: 'resolution=ignore-duplicates,return=minimal',
          body: {
            'id': userId,
            'display_name': name,
            'auth_provider': 'neon_auth',
            'auth_subject': userId,
          });

      // 1. Hapus di server aktivitas yang dihapus pengguna di HP.
      for (final cid in await _db.pendingRemoteDeletes()) {
        await _api('/activities?id=eq.$cid', method: 'DELETE');
        await _db.clearRemoteDelete(cid);
        deleted++;
      }

      // 2. Kirim aktivitas lokal yang baru / berubah.
      for (final row in await _db.activitiesToPush()) {
        final a = Activity.fromMap(row);
        final cid = cloudIdFor(a, row['cloud_id'] as String?);
        await _pushActivity(a, cid);
        await _db.markSynced(a.id, cid);
        pushed++;
        pending = (pending - 1).clamp(0, 1 << 30);
        notifyListeners();
      }

      // 3. Tarik aktivitas yang ada di server tapi belum ada di HP
      //    (misalnya upload .FIT lewat web).
      final known = await _db.knownCloudIds();
      final skip = (await _db.pendingRemoteDeletes()).toSet();
      final remote = await _api(
              '/activities?select=id,sport_type,started_at,finished_at,elapsed_seconds,moving_seconds,paused_seconds,distance_meters,elevation_gain_meters,calories_estimated,avg_heart_rate,max_heart_rate,source,source_device&status=eq.completed&order=started_at.desc')
          as List? ??
          const [];
      for (final r in remote) {
        final m = r as Map<String, dynamic>;
        final id = m['id'] as String;
        if (known.contains(id) || skip.contains(id)) continue;
        await _pullActivity(m);
        pulled++;
      }

      lastSync = DateTime.now();
      await _storage.write(key: 'last_sync', value: lastSync!.toIso8601String());
      if (pulled > 0 || deleted > 0) onLocalChanged?.call();
      return SyncResult(pushed, pulled, deleted);
    } on CloudException catch (e) {
      lastError = e.message;
      return null;
    } catch (e) {
      lastError = 'Sinkron gagal: $e';
      return null;
    } finally {
      syncing = false;
      await refreshPending();
      notifyListeners();
    }
  }

  static double _r(double v, int digits) {
    final f = 1.0 * (digits == 2 ? 100 : 1000);
    return (v * f).round() / f;
  }

  Future<void> _pushActivity(Activity a, String cid) async {
    final elapsed = a.elapsedSeconds;
    final moving = elapsed > 0 ? a.movingSeconds.clamp(0, elapsed) : a.movingSeconds;
    final dist = a.distanceMeters;
    final finished = a.finishedAt ?? a.startedAt.add(Duration(seconds: elapsed));
    await _api('/activities?on_conflict=id',
        method: 'POST',
        prefer: 'resolution=merge-duplicates,return=minimal',
        body: {
          'id': cid,
          'sport_type': a.sport.name,
          'status': 'completed',
          'started_at': a.startedAt.toUtc().toIso8601String(),
          'finished_at': (finished.isBefore(a.startedAt) ? a.startedAt : finished)
              .toUtc()
              .toIso8601String(),
          'elapsed_seconds': elapsed,
          'moving_seconds': moving,
          'paused_seconds': a.pausedSeconds < 0 ? 0 : a.pausedSeconds,
          'distance_meters': _r(dist, 2),
          'average_pace_seconds_per_km':
              dist > 0 ? _r(moving / (dist / 1000), 2) : null,
          'average_speed_mps': moving > 0 ? _r(dist / moving, 3) : null,
          'elevation_gain_meters': a.elevationGainMeters.round(),
          'calories_estimated': a.caloriesEstimated,
          'avg_heart_rate': _hr(a.avgHeartRate),
          'max_heart_rate': _hr(a.maxHeartRate),
          'source': a.source,
          'source_device': a.sourceDevice,
        });
    final pts = await _db.points(a.id);
    final src = a.source == ActivitySource.fitFile ? 'fit' : 'gps';
    for (var i = 0; i < pts.length; i += 1000) {
      final chunk = pts.sublist(i, (i + 1000).clamp(0, pts.length));
      await _api('/activity_points?on_conflict=activity_id,sequence_no',
          method: 'POST',
          prefer: 'resolution=merge-duplicates,return=minimal',
          body: [
            for (final p in chunk)
              {
                'activity_id': cid,
                'sequence_no': p.sequenceNo,
                'recorded_at': p.recordedAt.toUtc().toIso8601String(),
                'latitude': p.latitude,
                'longitude': p.longitude,
                'altitude_meters': p.altitude,
                'accuracy_meters':
                    p.accuracy != null && p.accuracy! >= 0 ? p.accuracy : null,
                'speed_mps': p.speed != null && p.speed! >= 0 ? p.speed : null,
                'heart_rate': _hr(p.heartRate),
                'segment_start': p.segmentStart,
                'source': src,
              }
          ]);
    }
  }

  static int? _hr(int? v) => v != null && v >= 1 && v <= 300 ? v : null;

  Future<void> _pullActivity(Map<String, dynamic> m) async {
    final id = m['id'] as String;
    final ptsRaw = await _api(
            '/activity_points?activity_id=eq.$id&select=sequence_no,recorded_at,latitude,longitude,altitude_meters,accuracy_meters,speed_mps,heart_rate,segment_start&order=sequence_no')
        as List? ??
        const [];
    double? d(Object? v) => v == null ? null : (v as num).toDouble();
    final pts = [
      for (final r in ptsRaw.cast<Map<String, dynamic>>())
        TrackPoint(
          sequenceNo: r['sequence_no'] as int,
          recordedAt: DateTime.parse(r['recorded_at'] as String).toLocal(),
          latitude: d(r['latitude'])!,
          longitude: d(r['longitude'])!,
          altitude: d(r['altitude_meters']),
          accuracy: d(r['accuracy_meters']),
          speed: d(r['speed_mps']),
          heartRate: r['heart_rate'] as int?,
          segmentStart: r['segment_start'] == true,
        )
    ];
    final a = Activity(
      id: id,
      sport: SportTypeX.fromName(m['sport_type'] as String),
      startedAt: DateTime.parse(m['started_at'] as String).toLocal(),
      finishedAt: m['finished_at'] == null
          ? null
          : DateTime.parse(m['finished_at'] as String).toLocal(),
      status: ActivityStatus.finished,
      elapsedSeconds: (m['elapsed_seconds'] as num?)?.toInt() ?? 0,
      movingSeconds: (m['moving_seconds'] as num?)?.toInt() ?? 0,
      pausedSeconds: (m['paused_seconds'] as num?)?.toInt() ?? 0,
      distanceMeters: d(m['distance_meters']) ?? 0,
      elevationGainMeters: d(m['elevation_gain_meters']) ?? 0,
      avgHeartRate: (m['avg_heart_rate'] as num?)?.toInt(),
      maxHeartRate: (m['max_heart_rate'] as num?)?.toInt(),
      caloriesEstimated: (m['calories_estimated'] as num?)?.toInt(),
      source: (m['source'] as String?) ?? ActivitySource.phone,
      sourceDevice: m['source_device'] as String?,
    );
    await _db.insertFromCloud(a, pts);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _http.close();
    super.dispose();
  }
}
