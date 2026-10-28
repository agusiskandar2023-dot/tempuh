import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'data/activity_store.dart';
import 'data/database.dart';
import 'models/activity.dart';
import 'screens/activity_detail_screen.dart';
import 'screens/garmin_screen.dart';
import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
import 'screens/track_screen.dart';
import 'services/health_service.dart';
import 'services/tracking_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID');
  runApp(const MoveTrackApp());
}

class MoveTrackApp extends StatelessWidget {
  const MoveTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => TrackingService()),
        ChangeNotifierProvider(create: (_) => ActivityStore()..reload()),
        Provider(create: (_) => HealthService()),
      ],
      child: MaterialApp(
        title: 'MoveTrack AI',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const AppShell(),
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  int _index = 0;

  void goTo(int i) => setState(() => _index = i);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkUnfinished());
  }

  /// Bila aplikasi sempat dihentikan sistem saat merekam, tawarkan pemulihan.
  Future<void> _checkUnfinished() async {
    final tracking = context.read<TrackingService>();
    if (tracking.isActive) return;
    final a = await AppDatabase.instance.unfinishedActivity();
    if (a == null || !mounted) return;
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Sesi belum selesai'),
        content: Text(
            'Ditemukan sesi ${a.sport.label} yang terputus. Data yang sudah terekam aman. Lanjutkan atau simpan sekarang?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'discard'),
              child: const Text('Buang')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'finish'),
              child: const Text('Simpan')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, 'resume'),
              child: const Text('Lanjutkan')),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'discard') {
      await AppDatabase.instance.deleteActivity(a.id);
      return;
    }
    final err = await tracking.recover(a, startGps: choice == 'resume');
    if (err != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    if (choice == 'resume') {
      goTo(1);
    } else if (choice == 'finish') {
      final id = await tracking.finish();
      await context.read<ActivityStore>().reload();
      if (id != null && mounted) {
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ActivityDetailScreen(activityId: id)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final recording = context.select<TrackingService, bool>((t) => t.isActive);
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          HomeScreen(onStart: () => goTo(1)),
          const TrackScreen(),
          const HistoryScreen(),
          const GarminScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: goTo,
        destinations: [
          const NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Beranda'),
          NavigationDestination(
              icon: Icon(recording ? Icons.fiber_manual_record : Icons.play_circle_outline,
                  color: recording ? Colors.redAccent : null),
              selectedIcon: const Icon(Icons.play_circle),
              label: recording ? 'Merekam' : 'Rekam'),
          const NavigationDestination(
              icon: Icon(Icons.history), label: 'Riwayat'),
          const NavigationDestination(
              icon: Icon(Icons.watch_outlined),
              selectedIcon: Icon(Icons.watch),
              label: 'Garmin'),
        ],
      ),
    );
  }
}
