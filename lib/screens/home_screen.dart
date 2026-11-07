import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme.dart';
import '../data/activity_store.dart';
import '../domain/metrics.dart';
import '../domain/stats.dart';
import '../models/activity.dart';
import '../services/cloud_service.dart';
import '../widgets/route_thumbnail.dart';
import 'account_screen.dart';
import 'activity_detail_screen.dart';
import 'training_screen.dart';

/// Target jarak bawaan (km) per periode; bisa diubah dari Beranda.
const defaultTargetsKm = {
  StatPeriod.week: 20.0,
  StatPeriod.month: 80.0,
  StatPeriod.year: 1000.0,
};

class HomeScreen extends StatefulWidget {
  final VoidCallback onStart;
  const HomeScreen({super.key, required this.onStart});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  StatPeriod _period = StatPeriod.week;
  final Map<StatPeriod, double> _targets = Map.of(defaultTargetsKm);

  @override
  void initState() {
    super.initState();
    _loadTargets();
  }

  Future<void> _loadTargets() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      for (final p in StatPeriod.values) {
        final v = prefs.getDouble('target_${p.name}');
        if (v != null && v > 0) _targets[p] = v;
      }
    });
  }

  Future<void> _editTarget() async {
    final p = _period;
    final ctrl = TextEditingController(text: _targets[p]!.toStringAsFixed(0));
    final name = switch (p) {
      StatPeriod.week => 'mingguan',
      StatPeriod.month => 'bulanan',
      StatPeriod.year => 'tahunan',
    };
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.charcoal,
        title: Text('Target $name'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(suffixText: 'km'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(ctx, double.tryParse(ctrl.text.replaceAll(',', '.'))),
              child: const Text('Simpan')),
        ],
      ),
    );
    if (v == null || v <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('target_${p.name}', v);
    if (mounted) setState(() => _targets[p] = v);
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 11) return 'Selamat pagi';
    if (h < 15) return 'Selamat siang';
    if (h < 19) return 'Selamat sore';
    return 'Selamat malam';
  }

  String _delta(double now, double prev) {
    if (prev <= 0) return now > 0 ? 'baru' : '';
    final pct = ((now - prev) / prev * 100).round();
    if (pct == 0) return '= sama';
    return pct > 0 ? '↑ $pct%' : '↓ ${-pct}%';
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ActivityStore>();
    final items = store.items;
    final now = DateTime.now();
    final r = periodRange(_period, now);
    final cur = summarize(items, r.start, r.end);
    final prev = summarize(items, r.prevStart, r.start);
    final target = _targets[_period]!;
    final km = cur.meters / 1000;
    final progress = (km / target).clamp(0.0, 1.0);
    final left = target - km;
    final note = left <= 0
        ? 'Target tercapai! Lebih ${(-left).toStringAsFixed(1).replaceAll('.', ',')} km'
        : 'Perlu ${left.toStringAsFixed(1).replaceAll('.', ',')} km lagi';
    final delta = _delta(cur.meters, prev.meters);
    final streak = dayStreak(items, now);
    final sport = mainSport(items);
    final records = sport == null ? const <PersonalRecord>[] : personalRecords(items, sport);
    final last = items.isEmpty ? null : items.first;
    final today = DateFormat('EEEE, d MMM', 'id_ID').format(now);
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: store.reload,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            children: [
              Row(children: [
                const TempuhLogo(size: 36),
                const SizedBox(width: 10),
                const Text(appName,
                    style: TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
                const Spacer(),
                Text(today, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                const SizedBox(width: 4),
                const _CloudButton(),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_greeting(),
                          style: const TextStyle(fontSize: 14, color: AppColors.muted)),
                      const Text('Siap bergerak hari ini?',
                          style: TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                    ],
                  ),
                ),
                if (streak > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                        color: AppColors.lime.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(99)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.local_fire_department_outlined,
                          size: 16, color: AppColors.lime),
                      const SizedBox(width: 4),
                      Text('$streak hari beruntun',
                          style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.lime)),
                    ]),
                  ),
              ]),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: AppColors.charcoal, borderRadius: BorderRadius.circular(20)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PeriodToggle(
                        value: _period, onChanged: (p) => setState(() => _period = p)),
                    const SizedBox(height: 14),
                    Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(formatKm(cur.meters).replaceAll('.', ','),
                          style: const TextStyle(
                              fontSize: 40,
                              height: 1,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1.2)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: InkWell(
                          onTap: _editTarget,
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(children: [
                              Text('/ ${target.toStringAsFixed(0)} km',
                                  style: const TextStyle(
                                      fontSize: 15,
                                      color: AppColors.muted,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(width: 4),
                              const Icon(Icons.edit_outlined,
                                  size: 14, color: AppColors.muted),
                            ]),
                          ),
                        ),
                      ),
                      if (delta.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(delta,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: delta.startsWith('↓')
                                      ? AppColors.amber
                                      : AppColors.lime)),
                        ),
                    ]),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 9,
                        backgroundColor: AppColors.raised,
                        color: AppColors.lime,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(note, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                    const Divider(height: 24, color: AppColors.raised),
                    Row(children: [
                      Expanded(child: _mini('Waktu', formatDuration(cur.movingSeconds))),
                      Expanded(child: _mini('Aktivitas', '${cur.count}')),
                      Expanded(child: _mini('Kalori', NumberFormat.decimalPattern('id_ID').format(cur.calories))),
                    ]),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const TrainingHomeCard(),
              const SizedBox(height: 16),
              SizedBox(
                height: 58,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                  onPressed: widget.onStart,
                  icon: const Icon(Icons.play_arrow_rounded, size: 28),
                  label: const Text('Mulai Aktivitas',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ),
              ),
              if (records.isNotEmpty) ...[
                const SizedBox(height: 20),
                Row(children: [
                  const Expanded(
                    child: Text('Rekor pribadi',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => RecordsScreen(initial: sport))),
                    child: const Text('Semua rekor'),
                  ),
                ]),
                SizedBox(
                  height: 112,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: records.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, i) => SizedBox(
                        width: 150, child: RecordCard(record: records[i], showSport: true)),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              const Text('Aktivitas terakhir',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              if (last == null)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: AppColors.charcoal, borderRadius: BorderRadius.circular(18)),
                  child: const Text('Belum ada aktivitas. Mulai rekaman pertama Anda!',
                      style: TextStyle(color: AppColors.muted)),
                )
              else
                ActivityCard(activity: last, showRoute: true),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    foregroundColor: AppColors.soft,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                onPressed: () => launchUrl(Uri.parse(CloudConfig.webUrl),
                    mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Dashboard lengkap di web'),
              ),
              const SizedBox(height: 20),
              const Center(
                child: Text(appCredit,
                    style: TextStyle(
                        fontSize: 12, color: AppColors.muted, letterSpacing: 0.3)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mini(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        ],
      );
}

/// Pilihan Minggu / Bulan / Tahun.
class PeriodToggle extends StatelessWidget {
  final StatPeriod value;
  final ValueChanged<StatPeriod> onChanged;
  const PeriodToggle({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration:
          BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        for (final p in StatPeriod.values)
          Expanded(
            child: Material(
              color: p == value ? AppColors.lime : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              child: InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: () => onChanged(p),
                child: SizedBox(
                  height: 38,
                  child: Center(
                    child: Text(p.label,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: p == value ? AppColors.navy : AppColors.soft)),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Teks nilai rekor + satuannya.
(String, String) recordValue(PersonalRecord r) => switch (r.kind) {
      RecordKind.farthest => (formatKm(r.value).replaceAll('.', ','), 'km'),
      RecordKind.longest => (formatDuration(r.value.round()), ''),
      RecordKind.fastest => r.sport.showsSpeed
          ? (formatSpeedKmh(r.value), 'km/j')
          : (formatPace(r.value), '/km'),
      RecordKind.maxSpeed => (formatSpeedKmh(r.value), 'km/j'),
    };

/// Kartu satu rekor pribadi; ketuk untuk membuka aktivitasnya.
class RecordCard extends StatelessWidget {
  final PersonalRecord record;
  final bool showSport;
  const RecordCard({super.key, required this.record, this.showSport = false});

  @override
  Widget build(BuildContext context) {
    final r = record;
    final (value, unit) = recordValue(r);
    final date = DateFormat('d MMM yyyy', 'id_ID').format(r.activity.startedAt);
    return Material(
      color: AppColors.charcoal,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: r.isNew ? AppColors.lime : AppColors.raised),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ActivityDetailScreen(activityId: r.activity.id))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (r.isNew)
                Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(
                      color: AppColors.lime, borderRadius: BorderRadius.circular(99)),
                  child: const Text('Rekor baru!',
                      style: TextStyle(
                          fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.navy)),
                ),
              Text(showSport ? '${r.kind.label} · ${r.sport.label}' : r.kind.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text.rich(TextSpan(children: [
                  TextSpan(
                      text: value,
                      style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
                  if (unit.isNotEmpty)
                    TextSpan(
                        text: ' $unit',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w600)),
                ])),
              ),
              Text(date, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Semua rekor pribadi, per jenis olahraga.
class RecordsScreen extends StatefulWidget {
  final SportType? initial;
  const RecordsScreen({super.key, this.initial});

  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  late SportType _sport = widget.initial ?? SportType.running;

  @override
  Widget build(BuildContext context) {
    final items = context.watch<ActivityStore>().items;
    final records = personalRecords(items, _sport);
    return Scaffold(
      appBar: AppBar(title: const Text('Rekor pribadi')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in SportType.values)
              ChoiceChip(
                label: Text(s.label),
                selected: s == _sport,
                onSelected: (_) => setState(() => _sport = s),
              ),
          ]),
          const SizedBox(height: 16),
          if (records.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: Text('Belum ada aktivitas untuk olahraga ini.',
                  textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
            )
          else
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.45,
              children: [for (final r in records) RecordCard(record: r)],
            ),
          const SizedBox(height: 12),
          const Text(
              'Tercepat = pace rata-rata terbaik (kecepatan rata-rata untuk sepeda) pada aktivitas minimal 1 km.',
              style: TextStyle(fontSize: 12, color: AppColors.muted)),
        ],
      ),
    );
  }
}

String activityTitle(Activity a) {
  final custom = a.title?.trim();
  if (custom != null && custom.isNotEmpty) return custom;
  final h = a.startedAt.hour;
  final part = h < 11 ? 'pagi' : (h < 15 ? 'siang' : (h < 19 ? 'sore' : 'malam'));
  return '${a.sport.label} $part';
}

String activityPerf(Activity a) => a.sport.showsSpeed
    ? '${a.avgSpeedKmh.toStringAsFixed(1).replaceAll('.', ',')} km/j'
    : '${formatPace(a.avgPaceSecondsPerKm)} /km';

class ActivityCard extends StatelessWidget {
  final Activity activity;
  final bool showRoute;
  const ActivityCard({super.key, required this.activity, this.showRoute = false});

  @override
  Widget build(BuildContext context) {
    final a = activity;
    final when = DateFormat('EEE d MMM · HH:mm', 'id_ID').format(a.startedAt);
    final hr = a.avgHeartRate == null ? '' : ' · ${a.avgHeartRate} bpm';
    final garmin = a.source != ActivitySource.phone;
    return Material(
      color: AppColors.charcoal,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ActivityDetailScreen(activityId: a.id))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              if (showRoute)
                RouteThumbnail(activity: a)
              else
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                      color: AppColors.raised, borderRadius: BorderRadius.circular(14)),
                  child: Icon(a.sport.icon, color: AppColors.lime),
                ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(
                            '${activityTitle(a)} · ${formatKm(a.distanceMeters).replaceAll('.', ',')} km',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                      if (garmin) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                              color: AppColors.raised,
                              borderRadius: BorderRadius.circular(99)),
                          child: const Text('Garmin',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.soft)),
                        ),
                      ],
                    ]),
                    const SizedBox(height: 2),
                    Text(when,
                        style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                    const SizedBox(height: 2),
                    Text('${formatDuration(a.movingSeconds)} · ${activityPerf(a)}$hr',
                        style: const TextStyle(fontSize: 13, color: AppColors.soft)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ikon status sinkron di pojok Beranda; membuka layar Akun & Sinkron.
class _CloudButton extends StatelessWidget {
  const _CloudButton();

  @override
  Widget build(BuildContext context) {
    final cloud = context.watch<CloudService>();
    final IconData icon;
    final Color color;
    final String tip;
    if (!cloud.loggedIn) {
      icon = Icons.cloud_off_outlined;
      color = AppColors.muted;
      tip = 'Belum masuk akun';
    } else if (cloud.syncing) {
      icon = Icons.cloud_sync_outlined;
      color = AppColors.lime;
      tip = 'Menyinkronkan';
    } else if (cloud.lastError != null) {
      icon = Icons.cloud_off_outlined;
      color = AppColors.amber;
      tip = 'Sinkron bermasalah';
    } else if (cloud.pending > 0) {
      icon = Icons.cloud_upload_outlined;
      color = AppColors.amber;
      tip = '${cloud.pending} menunggu sinkron';
    } else {
      icon = Icons.cloud_done_outlined;
      color = AppColors.lime;
      tip = 'Tersinkron';
    }
    return IconButton(
      tooltip: tip,
      icon: Icon(icon, color: color),
      onPressed: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const AccountScreen())),
    );
  }
}
