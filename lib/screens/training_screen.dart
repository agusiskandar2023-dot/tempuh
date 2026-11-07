import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../data/activity_store.dart';
import '../data/training_store.dart';
import '../domain/training_plan.dart';
import '../models/activity.dart';

const _sky = Color(0xFF38BDF8);
String _km(double v) {
  final r = (v * 10).round() / 10;
  return r == r.roundToDouble() ? r.round().toString() : r.toString().replaceAll('.', ',');
}

/// Kartu ringkas program FM di Beranda.
class TrainingHomeCard extends StatelessWidget {
  const TrainingHomeCard({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.watch<TrainingStore>();
    final items = context.watch<ActivityStore>().items;
    final cal = t.calendar;
    final now = DateTime.now();
    final w = cal.weekOf(now);
    final days = cal.daysToRace(now);
    String headline;
    String sub;
    if (w == 0) {
      headline = 'Mulai ${DateFormat('d MMM', 'id_ID').format(cal.start)}';
      sub = 'Minggu 1: ${fmPlan[0].sessions[0].title}';
    } else if (w > fmWeeks) {
      headline = 'Program selesai';
      sub = 'Selamat! Lihat catatan latihan Anda.';
    } else {
      final i = runDays.indexWhere((d) => cal.dateOf(w, d.offset).isAfter(now.subtract(const Duration(days: 1))));
      final next = i < 0 ? null : runDays[i];
      headline = 'Minggu $w · ${cal.phaseOf(w).name}';
      if (next == null) {
        sub = 'Sesi minggu ini sudah lewat';
      } else {
        final date = cal.dateOf(w, next.offset);
        final st = sessionStatus(t.entry(w, next.key), activitiesOn(items, date));
        final s = fmPlan[w - 1].sessions[i];
        final isToday = DateUtils.isSameDay(date, now);
        sub = '${isToday ? 'Hari ini' : next.label}: ${s.title}${st.done ? ' ✓' : ''}';
      }
    }
    return Material(
      color: AppColors.charcoal,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const TrainingScreen())),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                  color: AppColors.lime.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14)),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(days >= 0 ? '$days' : '–',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.lime)),
                const Text('hari', style: TextStyle(fontSize: 10, color: AppColors.lime)),
              ]),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('PROGRAM FM JAKIM 2027',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                        color: AppColors.lime)),
                const SizedBox(height: 2),
                Text(headline,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                Text(sub,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: AppColors.soft)),
              ]),
            ),
            const Icon(Icons.chevron_right, color: AppColors.muted),
          ]),
        ),
      ),
    );
  }
}

class TrainingScreen extends StatefulWidget {
  const TrainingScreen({super.key});

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  int? _week;

  int _clampWeek(int w) => w.clamp(1, fmWeeks);

  Future<void> _editKm(BuildContext context, int week, RunDay d, double? current) async {
    final store = context.read<TrainingStore>();
    final ctrl = TextEditingController(text: current == null ? '' : _km(current));
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.charcoal,
        title: Text('Km ${d.label}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(suffixText: 'km', hintText: 'Jarak sebenarnya'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(
                  ctx, double.tryParse(ctrl.text.replaceAll(',', '.')) ?? 0),
              child: const Text('Simpan')),
        ],
      ),
    );
    if (v == null) return;
    await store.setEntry(week, d.key, done: v > 0 ? true : (store.entry(week, d.key)?.done ?? false), km: v > 0 ? v : null);
  }

  Future<void> _pickRaceDate(BuildContext context) async {
    final store = context.read<TrainingStore>();
    final d = await showDatePicker(
      context: context,
      initialDate: store.raceDate,
      firstDate: DateTime(2026, 1, 1),
      lastDate: DateTime(2030, 12, 31),
      selectableDayPredicate: (d) => d.weekday == DateTime.sunday,
      helpText: 'Hari lomba (hari Minggu)',
    );
    if (d != null) await store.setRaceDate(d);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<TrainingStore>();
    final items = context.watch<ActivityStore>().items;
    final cal = t.calendar;
    final now = DateTime.now();
    final cw = cal.weekOf(now);
    final week = _week ?? _clampWeek(cw == 0 ? 1 : cw);
    final plan = fmPlan[week - 1];
    final ws = cal.weekStart(week);
    final f = DateFormat('d MMM', 'id_ID');

    // Statistik keseluruhan.
    var totalKm = 0.0, runsDone = 0, runsDue = 0, longest = 0.0, strength = 0;
    final weekDone = List<double>.filled(fmWeeks, 0);
    for (var w = 1; w <= fmWeeks; w++) {
      for (var i = 0; i < runDays.length; i++) {
        final d = runDays[i];
        final date = cal.dateOf(w, d.offset);
        final st = sessionStatus(t.entry(w, d.key), activitiesOn(items, date));
        if (!date.isAfter(now)) runsDue++;
        if (st.done) {
          runsDone++;
          final k = st.km ?? fmPlan[w - 1].sessions[i].km;
          totalKm += k;
          weekDone[w - 1] += k;
          if (i == 3 && k > longest) longest = k;
        }
      }
      for (final s in strengthDays) {
        if (t.entry(w, s.$1)?.done == true) strength++;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Program FM JAKIM 2027'),
        actions: [
          IconButton(
              tooltip: 'Ubah tanggal lomba',
              onPressed: () => _pickRaceDate(context),
              icon: const Icon(Icons.event_outlined)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          Text(
              '${DateFormat('EEEE, d MMMM yyyy', 'id_ID').format(cal.raceDate)} · start 04.00 · batas 7 jam',
              style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: 12),
          Row(children: [
            _big('${cal.daysToRace(now).clamp(0, 9999)}', 'hari lagi', lime: true),
            const SizedBox(width: 8),
            _big(cw == 0 ? '0' : '${_clampWeek(cw)}', 'minggu ke, dari 31'),
            const SizedBox(width: 8),
            _big(runsDue == 0 ? '–' : '${(runsDone / runsDue * 100).round().clamp(0, 100)}%',
                'sesi lari selesai'),
          ]),
          const SizedBox(height: 14),
          _PhaseBar(current: cw),
          const SizedBox(height: 18),
          Row(children: [
            IconButton.outlined(
                tooltip: 'Minggu sebelumnya',
                onPressed: week > 1 ? () => setState(() => _week = week - 1) : null,
                icon: const Icon(Icons.chevron_left)),
            Expanded(
              child: Column(children: [
                Text('Minggu $week${week == cw ? ' · minggu ini' : ''}',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                Text('${f.format(ws)} – ${f.format(ws.add(const Duration(days: 6)))} · '
                    '${cal.phaseOf(week).name}${plan.recovery ? ' · ringan' : ''}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12.5,
                        color: plan.recovery ? AppColors.amber : AppColors.muted)),
              ]),
            ),
            IconButton.outlined(
                tooltip: 'Minggu berikutnya',
                onPressed: week < fmWeeks ? () => setState(() => _week = week + 1) : null,
                icon: const Icon(Icons.chevron_right)),
          ]),
          if (week != _clampWeek(cw == 0 ? 1 : cw))
            Center(
              child: TextButton(
                  onPressed: () => setState(() => _week = null),
                  child: const Text('Kembali ke minggu ini')),
            ),
          const SizedBox(height: 6),
          Text(
              'Rencana ±${_km(plan.km)} km · selesai ${_km(weekDone[week - 1])} km. '
              '${plan.note ?? fmPlan.take(week).lastWhere((p) => p.note != null, orElse: () => plan).note ?? ''}',
              style: const TextStyle(fontSize: 13, color: AppColors.soft, height: 1.4)),
          const SizedBox(height: 12),
          for (var i = 0; i < runDays.length; i++)
            _SessionCard(
              week: week,
              day: runDays[i],
              session: plan.sessions[i],
              date: cal.dateOf(week, runDays[i].offset),
              sameDay: activitiesOn(items, cal.dateOf(week, runDays[i].offset)),
              onKm: (cur) => _editKm(context, week, runDays[i], cur),
            ),
          const SizedBox(height: 10),
          const Text('Latihan kekuatan 10–15 menit',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Row(children: [
            for (var i = 0; i < strengthDays.length; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: _StrengthCell(
                    week: week,
                    slot: strengthDays[i].$1,
                    label: strengthDays[i].$2,
                    code: strengthDays[i].$3,
                    date: cal.dateOf(week, i),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 8),
          for (final e in strengthRoutines.entries)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text.rich(TextSpan(children: [
                TextSpan(
                    text: '${e.key} · ${e.value.$1}: ',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.text)),
                TextSpan(text: e.value.$2),
              ])),
            ),
          const SizedBox(height: 22),
          const Text('Progres', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _stat('${_km(totalKm)} km', 'total tercatat'),
            _stat('$runsDone', 'sesi lari selesai'),
            _stat(longest > 0 ? '${_km(longest)} km' : '–', 'long run terjauh'),
            _stat('$strength', 'hari latihan kekuatan'),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            height: 150,
            child: CustomPaint(
              painter: _WeeksChart(done: weekDone, current: cw, plan: fmPlan.map((p) => p.km).toList()),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: 6),
          const Row(children: [
            _Legend(color: AppColors.raised, label: 'Rencana'),
            SizedBox(width: 14),
            _Legend(color: AppColors.lime, label: 'Selesai'),
            SizedBox(width: 14),
            _Legend(color: _sky, label: 'Long run'),
          ]),
          const SizedBox(height: 22),
          const Text('Pace & target', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          ..._paceRows(),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.amber.withValues(alpha: 0.07),
              border: Border.all(color: AppColors.amber.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Text(
              'Sebelum minggu 1, cek kesehatan dulu (tekanan darah dan EKG, idealnya treadmill test). '
              'Hentikan lari dan periksa ke dokter bila nyeri dada, sesak tidak wajar, atau pusing.',
              style: TextStyle(fontSize: 13, color: AppColors.soft, height: 1.45),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Sesi otomatis tercentang bila ada aktivitas lari/jalan yang direkam Tempuh di hari itu.',
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  List<Widget> _paceRows() {
    const rows = [
      ('Lari mudah (Selasa, Sabtu)', '9:30–10:30 /km'),
      ('Long run Minggu, boleh lari-jalan', '9:45–11:00 /km'),
      ('Tempo / bukit (Kamis, mulai Feb)', '8:15–8:45 /km'),
      ('Pace maraton (mulai Mar)', '8:45–9:10 /km'),
      ('Detak jantung lari mudah', '≤ 130 bpm'),
      ('Target finis', '< 6:30 (aman < 7:00)'),
    ];
    return [
      for (final r in rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Expanded(child: Text(r.$1, style: const TextStyle(fontSize: 13.5, color: AppColors.soft))),
            Text(r.$2, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
          ]),
        ),
    ];
  }

  Widget _big(String v, String l, {bool lime = false}) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration:
              BoxDecoration(color: AppColors.charcoal, borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(v,
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: lime ? AppColors.lime : AppColors.text)),
            Text(l, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
          ]),
        ),
      );

  Widget _stat(String v, String l) => Container(
        width: 150,
        padding: const EdgeInsets.all(12),
        decoration:
            BoxDecoration(color: AppColors.charcoal, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(v, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          Text(l, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
        ]),
      );
}

class _PhaseBar extends StatelessWidget {
  final int current;
  const _PhaseBar({required this.current});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      for (final p in fmPhases)
        Expanded(
          flex: p.to - p.from + 1,
          child: Container(
            height: 30,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: current >= p.from && current <= p.to
                  ? AppColors.lime
                  : current > p.to
                      ? const Color(0xFF3D5A1C)
                      : AppColors.raised,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(p.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: current >= p.from && current <= p.to ? AppColors.navy : AppColors.soft)),
          ),
        ),
    ]);
  }
}

class _SessionCard extends StatelessWidget {
  final int week;
  final RunDay day;
  final PlanSession session;
  final DateTime date;
  final List<Activity> sameDay;
  final ValueChanged<double?> onKm;
  const _SessionCard({
    required this.week,
    required this.day,
    required this.session,
    required this.date,
    required this.sameDay,
    required this.onKm,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.watch<TrainingStore>();
    final e = t.entry(week, day.key);
    final st = sessionStatus(e, sameDay);
    final today = DateUtils.isSameDay(date, DateTime.now());
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.charcoal,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: st.done ? AppColors.lime : (today ? _sky : AppColors.raised),
            width: today && !st.done ? 2 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
                '${day.label.toUpperCase()} · ${DateFormat('d MMM', 'id_ID').format(date)}${today ? ' · HARI INI' : ''}',
                style: const TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.muted, letterSpacing: 0.6)),
          ),
          if (session.long)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                  color: AppColors.lime.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(99)),
              child: Text(session.race ? 'LOMBA' : 'utama',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.lime)),
            ),
        ]),
        const SizedBox(height: 4),
        Text(session.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        Text(session.detail, style: const TextStyle(fontSize: 13, color: AppColors.soft)),
        if (st.auto)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Tercatat dari Tempuh: ${_km(st.km ?? 0)} km',
                style: const TextStyle(fontSize: 12.5, color: AppColors.lime)),
          ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: st.done
                ? FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                    onPressed: st.auto ? null : () => t.toggle(week, day.key),
                    icon: const Icon(Icons.check, size: 18),
                    label: Text(st.auto ? 'Selesai (otomatis)' : 'Selesai'),
                  )
                : OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                    onPressed: () => t.toggle(week, day.key),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Tandai selesai'),
                  ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size(80, 44)),
            onPressed: () => onKm(e?.km),
            child: Text((e?.km ?? 0) > 0 ? '${_km(e!.km!)} km' : 'Isi km'),
          ),
        ]),
      ]),
    );
  }
}

class _StrengthCell extends StatelessWidget {
  final int week;
  final String slot, label, code;
  final DateTime date;
  const _StrengthCell(
      {required this.week, required this.slot, required this.label, required this.code, required this.date});

  @override
  Widget build(BuildContext context) {
    final t = context.watch<TrainingStore>();
    final on = t.entry(week, slot)?.done == true;
    return Column(children: [
      Material(
        color: on ? AppColors.lime : Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: on ? AppColors.lime : AppColors.raised)),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => t.toggle(week, slot),
          child: SizedBox(
            height: 44,
            child: Center(
              child: on
                  ? const Icon(Icons.check, size: 18, color: AppColors.navy)
                  : Text(code,
                      style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.muted)),
            ),
          ),
        ),
      ),
      const SizedBox(height: 3),
      Text('$label\n${date.day}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 10.5, color: AppColors.muted, height: 1.2)),
    ]);
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 11, height: 11, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.soft)),
      ]);
}

class _WeeksChart extends CustomPainter {
  final List<double> done;
  final List<double> plan;
  final int current;
  _WeeksChart({required this.done, required this.plan, required this.current});

  @override
  void paint(Canvas canvas, Size size) {
    const max = 70.0;
    final bw = size.width / plan.length;
    double y(double v) => size.height - 14 - (size.height - 18) * (v.clamp(0, max) / max);
    final grid = Paint()..color = AppColors.raised.withValues(alpha: 0.6);
    for (var v = 0.0; v <= max; v += 20) {
      canvas.drawLine(Offset(0, y(v)), Offset(size.width, y(v)), grid);
    }
    final longPath = Path();
    for (var i = 0; i < plan.length; i++) {
      final x = i * bw + bw * 0.15;
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTRB(x, y(plan[i]), x + bw * 0.7, y(0)), const Radius.circular(2)),
          Paint()..color = AppColors.raised);
      if (done[i] > 0) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromLTRB(x, y(done[i]), x + bw * 0.7, y(0)), const Radius.circular(2)),
            Paint()..color = AppColors.lime);
      }
      final ly = y(fmPlan[i].sessions[3].km);
      i == 0 ? longPath.moveTo(x + bw * 0.35, ly) : longPath.lineTo(x + bw * 0.35, ly);
      if (i + 1 == current) {
        canvas.drawLine(Offset(x + bw * 0.35, 0), Offset(x + bw * 0.35, y(0)),
            Paint()
              ..color = AppColors.text
              ..strokeWidth = 1);
      }
      if ((i + 1) % 5 == 0 || i == 0) {
        final tp = TextPainter(
            text: TextSpan(text: '${i + 1}', style: const TextStyle(fontSize: 9.5, color: AppColors.muted)),
            textDirection: TextDirection.ltr)
          ..layout();
        tp.paint(canvas, Offset(x + bw * 0.35 - tp.width / 2, size.height - 12));
      }
    }
    canvas.drawPath(
        longPath,
        Paint()
          ..color = _sky
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6);
  }

  @override
  bool shouldRepaint(covariant _WeeksChart old) => true;
}
