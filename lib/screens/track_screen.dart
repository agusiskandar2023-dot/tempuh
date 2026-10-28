import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../data/activity_store.dart';
import '../domain/metrics.dart';
import '../models/activity.dart';
import '../services/tracking_service.dart';
import '../widgets/route_map.dart';
import '../widgets/stat_tile.dart';
import 'activity_detail_screen.dart';

class TrackScreen extends StatelessWidget {
  const TrackScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.watch<TrackingService>();
    return t.isActive ? const _LiveView() : const _SetupView();
  }
}

class _SetupView extends StatefulWidget {
  const _SetupView();

  @override
  State<_SetupView> createState() => _SetupViewState();
}

class _SetupViewState extends State<_SetupView> {
  SportType _sport = SportType.running;
  LatLng? _here;
  bool _batteryOk = true;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final t = context.read<TrackingService>();
    final ok = await t.isIgnoringBatteryOptimizations();
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse) {
        final p = await Geolocator.getLastKnownPosition() ??
            await Geolocator.getCurrentPosition(
                locationSettings:
                    const LocationSettings(accuracy: LocationAccuracy.high));
        if (mounted) setState(() => _here = LatLng(p.latitude, p.longitude));
      }
    } catch (_) {}
    if (mounted) setState(() => _batteryOk = ok);
  }

  Future<void> _start() async {
    setState(() => _starting = true);
    final err = await context.read<TrackingService>().start(_sport);
    if (!mounted) return;
    setState(() => _starting = false);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rekam Aktivitas')),
      body: Column(
        children: [
          Expanded(
            child: RouteMap(route: const [], current: _here, follow: true),
          ),
          Container(
            color: AppColors.charcoal,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!_batteryOk)
                  Card(
                    color: const Color(0xFF3B2F0B),
                    child: ListTile(
                      leading: const Icon(Icons.battery_alert,
                          color: Colors.amber),
                      title: const Text('Izinkan berjalan di latar belakang'),
                      subtitle: const Text(
                          'Agar rekaman tidak dihentikan penghemat baterai saat HP sleep.'),
                      onTap: () async {
                        final ok = await context
                            .read<TrackingService>()
                            .requestIgnoreBatteryOptimizations();
                        setState(() => _batteryOk = ok);
                      },
                    ),
                  ),
                if (!_batteryOk) const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final s in SportType.values)
                      ChoiceChip(
                        avatar: Icon(s.icon, size: 18),
                        label: Text(s.label),
                        selected: _sport == s,
                        onSelected: (_) => setState(() => _sport = s),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 60,
                  child: FilledButton.icon(
                    onPressed: _starting ? null : _start,
                    icon: _starting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.play_arrow, size: 30),
                    label: Text('START ${_sport.label.toUpperCase()}',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveView extends StatelessWidget {
  const _LiveView();

  Future<void> _finish(BuildContext context) async {
    final t = context.read<TrackingService>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Selesaikan aktivitas?'),
        content: Text(
            'Jarak ${formatKm(t.distanceMeters)} km, waktu aktif ${formatDuration(t.movingSeconds)}.'),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx, false);
              final del = await showDialog<bool>(
                context: context,
                builder: (c2) => AlertDialog(
                  title: const Text('Buang aktivitas ini?'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c2, false),
                        child: const Text('Batal')),
                    TextButton(
                        onPressed: () => Navigator.pop(c2, true),
                        child: const Text('Buang')),
                  ],
                ),
              );
              if (del == true) await t.discard();
            },
            child: const Text('Buang'),
          ),
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Simpan')),
        ],
      ),
    );
    if (ok != true) return;
    final id = await t.finish();
    if (!context.mounted) return;
    await context.read<ActivityStore>().reload();
    if (id != null && context.mounted) {
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ActivityDetailScreen(activityId: id)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<TrackingService>();
    final a = t.activity!;
    final calc = t.calc!;
    final route =
        calc.points.map((p) => LatLng(p.latitude, p.longitude)).toList();
    final fix = t.lastFix;
    final paused = t.state == TrackingState.paused;
    final speed = calc.currentSpeedMps();
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Icon(a.sport.icon, color: AppColors.lime),
          const SizedBox(width: 8),
          Text(a.sport.label),
        ]),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(t.gpsQuality,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: RouteMap(
              route: route,
              current: fix == null ? null : LatLng(fix.latitude, fix.longitude),
              follow: true,
            ),
          ),
          Container(
            color: AppColors.charcoal,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              children: [
                if (paused)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text('DIJEDA',
                        style: TextStyle(
                            color: Colors.amber,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2)),
                  ),
                if (t.error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(t.error!,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    StatTile('Jarak', formatKm(t.distanceMeters),
                        unit: 'km', large: true),
                    StatTile('Waktu aktif', formatDuration(t.movingSeconds),
                        large: true),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    a.sport.showsSpeed
                        ? StatTile('Kecepatan',
                            speed == null ? '--' : (speed * 3.6).toStringAsFixed(1),
                            unit: 'km/j')
                        : StatTile('Pace', formatPace(calc.currentPaceSecondsPerKm()),
                            unit: '/km'),
                    StatTile('Total', formatDuration(t.elapsedSeconds)),
                    StatTile('Elevasi', calc.elevationGainMeters.round().toString(),
                        unit: 'm'),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 60,
                        child: paused
                            ? FilledButton.icon(
                                onPressed: t.resume,
                                icon: const Icon(Icons.play_arrow, size: 28),
                                label: const Text('LANJUT',
                                    style: TextStyle(
                                        fontSize: 17, fontWeight: FontWeight.w800)),
                              )
                            : FilledButton.tonalIcon(
                                onPressed: t.pause,
                                icon: const Icon(Icons.pause, size: 28),
                                label: const Text('PAUSE',
                                    style: TextStyle(
                                        fontSize: 17, fontWeight: FontWeight.w800)),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 60,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              foregroundColor: Colors.white),
                          onPressed: () => _finish(context),
                          icon: const Icon(Icons.stop, size: 28),
                          label: const Text('SELESAI',
                              style: TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
