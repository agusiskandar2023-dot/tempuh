import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../domain/metrics.dart';
import '../domain/replay.dart';
import '../models/activity.dart';
import '../screens/home_screen.dart' show activityTitle;

/// Ukuran logis satu frame video (9:16). Diekspor ×2 → 720×1280.
const replayLogicalSize = Size(360, 640);

/// Menggambar satu frame video replay pada detik [t].
class ReplayPainter extends CustomPainter {
  final Activity activity;
  final ReplayData data;
  final ReplayTimeline timeline;
  final double t;
  final ui.Image? photo;
  final bool showHeartRate;

  ReplayPainter({
    required this.activity,
    required this.data,
    required this.timeline,
    required this.t,
    this.photo,
    this.showHeartRate = true,
  });

  static const _bg = Color(0xFF0E1729);
  static const _street = Color(0xFF1A2539);
  static const _street2 = Color(0xFF152033);
  static const _water = Color(0xFF16304A);
  static const _park = Color(0xFF13281F);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / replayLogicalSize.width);
    _paintFrame(canvas);
    canvas.restore();
  }

  void _paintFrame(Canvas c) {
    const w = 360.0, h = 640.0;
    final tl = timeline;
    c.drawRect(const Rect.fromLTWH(0, 0, w, h), Paint()..color = _bg);
    _paintMapBackdrop(c);

    // ---- rute ----
    final proj = _Projection.fit(data, const Rect.fromLTWH(34, 220, 292, 380));
    final f = tl.routeFraction(t);
    if (data.length >= 2) {
      final all = Path()..moveTo(proj.x(0), proj.y(0));
      for (var i = 1; i < data.length; i++) {
        all.lineTo(proj.x(i), proj.y(i));
      }
      c.drawPath(
          all,
          Paint()
            ..color = AppColors.lime.withValues(alpha: 0.18)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.4
            ..strokeJoin = StrokeJoin.round
            ..strokeCap = StrokeCap.round);

      final (idx, wgt) = data.locate(f);
      final head = idx >= data.length - 1
          ? Offset(proj.x(data.length - 1), proj.y(data.length - 1))
          : Offset.lerp(Offset(proj.x(idx), proj.y(idx)),
              Offset(proj.x(idx + 1), proj.y(idx + 1)), wgt)!;
      final done = Path()..moveTo(proj.x(0), proj.y(0));
      for (var i = 1; i <= idx && i < data.length; i++) {
        done.lineTo(proj.x(i), proj.y(i));
      }
      done.lineTo(head.dx, head.dy);
      c.drawPath(
          done,
          Paint()
            ..color = AppColors.navy
            ..style = PaintingStyle.stroke
            ..strokeWidth = 8.6
            ..strokeJoin = StrokeJoin.round
            ..strokeCap = StrokeCap.round);
      c.drawPath(
          done,
          Paint()
            ..color = AppColors.lime
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5
            ..strokeJoin = StrokeJoin.round
            ..strokeCap = StrokeCap.round);

      // Titik start.
      final start = Offset(proj.x(0), proj.y(0));
      c.drawCircle(start, 5.4, Paint()..color = AppColors.text);
      c.drawCircle(
          start,
          5.4,
          Paint()
            ..color = AppColors.navy
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);

      // Tanda km yang baru dilewati.
      final chipLife = tl.seconds >= 30 ? 2.4 : 1.6;
      for (final k in data.kms) {
        final tk = tl.timeAtFraction(k.fraction);
        final age = t - tk;
        if (age < 0 || age > chipLife || t >= tl.routeEnd + 0.2) continue;
        final (ki, kw) = data.locate(k.fraction);
        final at = ki >= data.length - 1
            ? Offset(proj.x(ki), proj.y(ki))
            : Offset.lerp(Offset(proj.x(ki), proj.y(ki)),
                Offset(proj.x(ki + 1), proj.y(ki + 1)), kw)!;
        final op = math.min(1.0, math.min(age / 0.2, (chipLife - age) / 0.3)).clamp(0.0, 1.0);
        final perf = activity.sport.showsSpeed
            ? '${(3600 / k.paceSecondsPerKm).toStringAsFixed(1).replaceAll('.', ',')} km/j'
            : formatPace(k.paceSecondsPerKm);
        _chip(c, 'KM ${k.km} · $perf', at.translate(0, -26), op);
      }

      // Momen kecepatan maks.
      final mf = data.maxSpeedFraction;
      final mv = activity.maxSpeedMps ?? data.maxSpeedMps;
      if (mf != null && mv != null && mv > 0) {
        final tm = tl.timeAtFraction(mf);
        final age = t - tm;
        final life = tl.seconds >= 30 ? 3.2 : 2.2;
        if (age >= 0 && age < life && t < tl.routeEnd + 0.3) {
          final (mi, mw) = data.locate(mf);
          final at = mi >= data.length - 1
              ? Offset(proj.x(mi), proj.y(mi))
              : Offset.lerp(Offset(proj.x(mi), proj.y(mi)),
                  Offset(proj.x(mi + 1), proj.y(mi + 1)), mw)!;
          final scale = math.min(1.0, 0.6 + age * 2);
          final op = math.min(1.0, (life - age) / 0.3).clamp(0.0, 1.0);
          _maxCallout(c, at, mv, scale, op);
        }
      }

      // Ikon orang (atau sepeda) yang bergerak.
      _mover(c, head, f);
    }

    // ---- HUD atas (judul + angka berjalan) ----
    final hudOp = t >= tl.finalStart ? 0.0 : 1.0;
    if (hudOp > 0) _hud(c, f);

    // ---- pembuka ----
    if (t < tl.introEnd + 0.5) {
      final op = t < tl.introEnd - 0.5
          ? 1.0
          : (1 - (t - (tl.introEnd - 0.5)) / 1.0).clamp(0.0, 1.0);
      _intro(c, op);
    }

    // ---- foto ----
    if (tl.hasPhoto && photo != null && t >= tl.routeEnd && t < tl.photoEnd + 0.3) {
      final op = math.min((t - tl.routeEnd) / 0.4, (tl.photoEnd + 0.3 - t) / 0.4).clamp(0.0, 1.0);
      _photo(c, op);
    }

    // ---- ringkasan akhir ----
    if (t >= tl.finalStart) {
      final e = ((t - tl.finalStart) / 0.6).clamp(0.0, 1.0);
      final ease = 1 - math.pow(1 - e, 3).toDouble();
      _finale(c, ease);
    }
  }

  // ------------------------------------------------------------------

  void _paintMapBackdrop(Canvas c) {
    final water = Path()
      ..moveTo(47, 0)
      ..cubicTo(73, 133, 40, 253, 87, 367)
      ..cubicTo(130, 480, 73, 547, 110, 640);
    c.drawPath(
        water,
        Paint()
          ..color = _water
          ..style = PaintingStyle.stroke
          ..strokeWidth = 23);
    final st = Paint()
      ..color = _street
      ..strokeWidth = 7.3;
    for (final y in [173.0, 293.0, 417.0, 533.0]) {
      c.drawLine(Offset(0, y), Offset(360, y), st);
    }
    for (final x in [60.0, 173.0, 287.0]) {
      c.drawLine(Offset(x, 0), Offset(x, 640), st);
    }
    final st2 = Paint()
      ..color = _street2
      ..strokeWidth = 4;
    c.drawLine(const Offset(0, 233), const Offset(360, 187), st2);
    c.drawLine(const Offset(0, 477), const Offset(360, 443), st2);
    c.drawLine(const Offset(120, 0), const Offset(140, 640), st2);
    c.drawLine(const Offset(233, 0), const Offset(220, 640), st2);
    final park = Paint()..color = _park;
    c.drawRRect(RRect.fromLTRBR(187, 310, 273, 403, const Radius.circular(20)), park);
    c.drawRRect(RRect.fromLTRBR(77, 430, 150, 497, const Radius.circular(17)), park);
  }

  TextStyle _ts(double size,
          {FontWeight weight = FontWeight.w800, Color color = AppColors.text, double ls = 0}) =>
      GoogleFonts.plusJakartaSans(
          fontSize: size, fontWeight: weight, color: color, letterSpacing: ls, height: 1.1);

  Size _text(Canvas c, String s, Offset o, TextStyle style,
      {double maxWidth = 340, TextAlign align = TextAlign.left, int? maxLines = 1}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: ui.TextDirection.ltr,
      textAlign: align,
      maxLines: maxLines,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    var dx = o.dx;
    if (align == TextAlign.center) dx -= tp.width / 2;
    if (align == TextAlign.right) dx -= tp.width;
    tp.paint(c, Offset(dx, o.dy));
    return tp.size;
  }

  void _rich(Canvas c, List<TextSpan> spans, Offset o, {double maxWidth = 200}) {
    final tp = TextPainter(
      text: TextSpan(children: spans),
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: maxWidth);
    tp.paint(c, o);
  }

  void _chip(Canvas c, String s, Offset center, double op) {
    final style = _ts(11.3, color: AppColors.text.withValues(alpha: op));
    final tp = TextPainter(
        text: TextSpan(text: s, style: style), textDirection: ui.TextDirection.ltr)
      ..layout();
    final r = RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: tp.width + 16, height: tp.height + 10),
        const Radius.circular(99));
    c.drawRRect(r, Paint()..color = AppColors.navy.withValues(alpha: op));
    c.drawRRect(
        r,
        Paint()
          ..color = AppColors.lime.withValues(alpha: op)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2);
    tp.paint(c, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  void _maxCallout(Canvas c, Offset at, double mps, double scale, double op) {
    const bw = 150.0, bh = 50.0;
    final cx = at.dx.clamp(bw / 2 + 12, 360 - bw / 2 - 12);
    final top = at.dy + 22;
    c.save();
    c.translate(cx, top + bh / 2);
    c.scale(scale);
    final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: bw, height: bh), const Radius.circular(9));
    c.drawRRect(rect.shift(const Offset(0, 3)),
        Paint()..color = Colors.black.withValues(alpha: 0.35 * op));
    c.drawRRect(rect, Paint()..color = AppColors.lime.withValues(alpha: op));
    _icon(c, Icons.bolt, Offset(-bw / 2 + 20, 0), 22, AppColors.navy.withValues(alpha: op));
    _text(c, 'Kecepatan maks', Offset(-bw / 2 + 34, -18),
        _ts(8.7, weight: FontWeight.w700, color: AppColors.navy.withValues(alpha: op)));
    _text(c, '${formatSpeedKmh(mps)} km/j', Offset(-bw / 2 + 34, -5),
        _ts(17.3, color: AppColors.navy.withValues(alpha: op), ls: -0.3));
    c.restore();
  }

  void _icon(Canvas c, IconData icon, Offset center, double size, Color color) {
    final tp = TextPainter(
      text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
              fontFamily: icon.fontFamily,
              package: icon.fontPackage,
              fontSize: size,
              color: color,
              height: 1)),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
  }

  /// Ikon orang berlari / berjalan (atau sepeda) di ujung rute.
  void _mover(Canvas c, Offset at, double f) {
    final moving = f > 0 && f < 1;
    final bob = moving ? math.sin(t * 14) * 1.6 : 0.0;
    final center = at.translate(0, -16 + bob);
    // Bayangan & penanda posisi tepat di rute.
    c.drawOval(Rect.fromCenter(center: at.translate(0, 1), width: 14, height: 5),
        Paint()..color = Colors.black.withValues(alpha: 0.35));
    c.drawCircle(at, 3.2, Paint()..color = AppColors.lime);
    // Halo.
    c.drawCircle(center, 17 + math.sin(t * 6) * 2,
        Paint()..color = AppColors.lime.withValues(alpha: 0.2));
    c.drawCircle(center, 13.5, Paint()..color = AppColors.lime);
    c.drawCircle(
        center,
        13.5,
        Paint()
          ..color = AppColors.navy
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2);
    final icon = switch (activity.sport) {
      SportType.cycling => Icons.directions_bike,
      SportType.walking => Icons.directions_walk,
      _ => Icons.directions_run,
    };
    _icon(c, icon, center, 18, AppColors.navy);
  }

  void _hud(Canvas c, double f) {
    final date = DateFormat('EEE, d MMM yyyy · HH:mm', 'id_ID').format(activity.startedAt);
    c.save();
    c.translate(21, 32);
    paintTempuhLogo(c, 24, AppColors.charcoal);
    c.restore();
    _text(c, activityTitle(activity), const Offset(52, 30), _ts(14.7, ls: -0.3), maxWidth: 290);
    _text(c, date, const Offset(52, 49), _ts(8.7, weight: FontWeight.w500, color: AppColors.soft),
        maxWidth: 290);

    final panel = RRect.fromRectAndRadius(
        const Rect.fromLTWH(16, 80, 328, 74), const Radius.circular(12));
    c.drawRRect(panel, Paint()..color = AppColors.navy.withValues(alpha: 0.88));
    final m = data.metersAt(f);
    final s = data.secondsAt(f);
    final unit = _ts(8.7, weight: FontWeight.w600, color: AppColors.muted);
    final big = _ts(21.3, ls: -0.6);
    final cols = [28.0, 136.0, 244.0];
    final perfLabel = activity.sport.showsSpeed ? 'Kecepatan' : 'Pace';
    final perfValue = activity.sport.showsSpeed
        ? (s > 5 ? (m / s * 3.6).toStringAsFixed(1).replaceAll('.', ',') : '--')
        : (m > 30 ? formatPace(s / (m / 1000)) : '--:--');
    final labels = ['Jarak', 'Waktu', perfLabel];
    for (var i = 0; i < 3; i++) {
      _text(c, labels[i], Offset(cols[i], 92), _ts(8.7, weight: FontWeight.w500, color: AppColors.muted));
    }
    _rich(c, [TextSpan(text: formatKm(m).replaceAll('.', ','), style: big), TextSpan(text: ' km', style: unit)],
        Offset(cols[0], 108), maxWidth: 104);
    _rich(c, [TextSpan(text: formatDuration(s.round()), style: big)], Offset(cols[1], 108), maxWidth: 104);
    _rich(c, [
      TextSpan(text: perfValue, style: big),
      TextSpan(text: activity.sport.showsSpeed ? ' km/j' : ' /km', style: unit)
    ], Offset(cols[2], 108), maxWidth: 104);
  }

  void _intro(Canvas c, double op) {
    c.saveLayer(const Rect.fromLTWH(0, 0, 360, 640),
        Paint()..color = Colors.white.withValues(alpha: op));
    c.drawRect(const Rect.fromLTWH(0, 0, 360, 640), Paint()..color = AppColors.navy);
    c.save();
    c.translate(180 - 33, 230);
    paintTempuhLogo(c, 66, AppColors.charcoal);
    c.restore();
    _text(c, activityTitle(activity), const Offset(180, 318), _ts(32, ls: -1),
        align: TextAlign.center, maxWidth: 320, maxLines: 2);
    _text(c, DateFormat('EEEE, d MMMM yyyy', 'id_ID').format(activity.startedAt),
        const Offset(180, 395), _ts(12, weight: FontWeight.w500, color: AppColors.muted),
        align: TextAlign.center);
    _text(c, activity.sport.label.toUpperCase(), const Offset(180, 200),
        _ts(10, weight: FontWeight.w700, color: AppColors.lime, ls: 2), align: TextAlign.center);
    c.restore();
  }

  void _photo(Canvas c, double op) {
    final img = photo!;
    const dst = Rect.fromLTWH(0, 0, 360, 640);
    final src = _coverRect(Size(img.width.toDouble(), img.height.toDouble()), dst.size);
    c.drawImageRect(img, src, dst,
        Paint()
          ..color = Colors.white.withValues(alpha: op)
          ..filterQuality = FilterQuality.medium);
  }

  static Rect _coverRect(Size src, Size dst) {
    final s = math.max(dst.width / src.width, dst.height / src.height);
    final w = dst.width / s, h = dst.height / s;
    return Rect.fromLTWH((src.width - w) / 2, (src.height - h) / 2, w, h);
  }

  void _finale(Canvas c, double e) {
    final a = activity;
    c.drawRect(const Rect.fromLTWH(0, 0, 360, 640),
        Paint()..color = AppColors.navy.withValues(alpha: 0.55 * e));
    c.save();
    c.translate(0, (1 - e) * 133);
    c.saveLayer(const Rect.fromLTWH(0, 0, 360, 640), Paint()..color = Colors.white.withValues(alpha: e));
    final top = 640 - 40 - 250.0;
    final panel = RRect.fromRectAndRadius(Rect.fromLTWH(16, top, 328, 250), const Radius.circular(15));
    c.drawRRect(panel, Paint()..color = AppColors.navy.withValues(alpha: 0.95));
    _text(c, 'Selesai!', Offset(33, top + 16), _ts(10, weight: FontWeight.w700, color: AppColors.lime));
    _text(c, activityTitle(a), Offset(33, top + 30), _ts(24, ls: -0.8), maxWidth: 294);
    final label = _ts(9.3, weight: FontWeight.w500, color: AppColors.muted);
    final unit = _ts(10.7, weight: FontWeight.w600, color: AppColors.muted);
    final hasMax = (a.maxSpeedMps ?? 0) > 0;
    final cells = <(String, String, String, bool)>[
      ('Jarak', formatKm(a.distanceMeters).replaceAll('.', ','), ' km', false),
      ('Waktu aktif', formatDuration(a.movingSeconds), '', false),
      a.sport.showsSpeed
          ? ('Kecepatan rata-rata', a.avgSpeedKmh.toStringAsFixed(1).replaceAll('.', ','), ' km/j', false)
          : ('Pace rata-rata', formatPace(a.avgPaceSecondsPerKm), ' /km', false),
      hasMax
          ? ('Kecepatan maks', formatSpeedKmh(a.maxSpeedMps!), ' km/j', true)
          : ('Elevasi naik', a.elevationGainMeters.round().toString(), ' m', false),
    ];
    for (var i = 0; i < 4; i++) {
      final x = 33.0 + (i % 2) * 150;
      final y = top + 72 + (i ~/ 2) * 62;
      final cell = cells[i];
      _text(c, cell.$1, Offset(x, y), label);
      _rich(c, [
        TextSpan(
            text: cell.$2,
            style: _ts(i < 2 ? 27 : 21, ls: -0.8, color: cell.$4 ? AppColors.lime : AppColors.text)),
        TextSpan(text: cell.$3, style: unit),
      ], Offset(x, y + 14), maxWidth: 145);
    }
    c.drawLine(Offset(33, top + 206), Offset(327, top + 206),
        Paint()
          ..color = AppColors.raised
          ..strokeWidth = 0.7);
    if (showHeartRate && a.avgHeartRate != null) {
      _icon(c, Icons.favorite, Offset(39, top + 225), 11, AppColors.danger);
      _text(c, '${a.avgHeartRate} bpm', Offset(48, top + 219), _ts(8.7, weight: FontWeight.w500, color: AppColors.muted));
    }
    _text(c, 'Tempuh · $appCredit', Offset(327, top + 219),
        _ts(8.7, weight: FontWeight.w500, color: AppColors.muted), align: TextAlign.right);
    c.restore();
    c.restore();
  }

  @override
  bool shouldRepaint(covariant ReplayPainter old) =>
      old.t != t ||
      old.data != data ||
      old.photo != photo ||
      old.showHeartRate != showHeartRate ||
      old.timeline.seconds != timeline.seconds ||
      old.timeline.hasPhoto != timeline.hasPhoto;
}

/// Proyeksi equirectangular sederhana agar rute pas di kotak tujuan.
class _Projection {
  final ReplayData d;
  final double k, minX, minY, scale, ox, oy;
  _Projection(this.d, this.k, this.minX, this.minY, this.scale, this.ox, this.oy);

  factory _Projection.fit(ReplayData d, Rect box) {
    if (d.length == 0) return _Projection(d, 1, 0, 0, 1, box.left, box.top);
    final lat0 = d.lat.reduce((a, b) => a + b) / d.length;
    final k = math.cos(lat0 * math.pi / 180);
    var minX = double.infinity, maxX = -double.infinity;
    var minY = double.infinity, maxY = -double.infinity;
    for (var i = 0; i < d.length; i++) {
      final x = d.lon[i] * k, y = -d.lat[i];
      minX = math.min(minX, x);
      maxX = math.max(maxX, x);
      minY = math.min(minY, y);
      maxY = math.max(maxY, y);
    }
    final w = math.max(maxX - minX, 1e-9), h = math.max(maxY - minY, 1e-9);
    final s = math.min(box.width / w, box.height / h);
    return _Projection(d, k, minX, minY, s, box.left + (box.width - w * s) / 2,
        box.top + (box.height - h * s) / 2);
  }

  double x(int i) => ox + (d.lon[i] * k - minX) * scale;
  double y(int i) => oy + (-d.lat[i] - minY) * scale;
}
