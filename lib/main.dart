import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
import 'services/cloud_service.dart';
import 'services/health_service.dart';
import 'services/tracking_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Font diambil sekali lalu disimpan di HP; tanpa internet memakai font bawaan.
  GoogleFonts.config.allowRuntimeFetching = true;
  await initializeDateFormatting('id_ID');
  runApp(const TempuhApp());
}

class TempuhApp extends StatelessWidget {
  const TempuhApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => TrackingService()),
        ChangeNotifierProvider(create: (_) => CloudService()..init()),
        ChangeNotifierProvider(create: (ctx) {
          final cloud = ctx.read<CloudService>();
          final store = ActivityStore();
          store.onChanged = cloud.requestSync;
          cloud.onLocalChanged = store.reload;
          return store..reload();
        }),
        Provider(create: (_) => HealthService()),
      ],
      child: MaterialApp(
        title: appName,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const AppShell(),
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  static AppShellState? of(BuildContext context) =>
      context.findAncestorStateOfType<AppShellState>();

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
        backgroundColor: AppColors.charcoal,
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
      bottomNavigationBar: _BottomNav(
        index: _index,
        recording: recording,
        onTap: goTo,
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int index;
  final bool recording;
  final ValueChanged<int> onTap;
  const _BottomNav(
      {required this.index, required this.recording, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.home_outlined, Icons.home_rounded, 'Beranda'),
      (
        recording ? Icons.fiber_manual_record : Icons.play_circle_outline,
        Icons.play_circle_rounded,
        recording ? 'Merekam' : 'Rekam'
      ),
      (Icons.history_rounded, Icons.history_rounded, 'Riwayat'),
      (Icons.watch_outlined, Icons.watch_rounded, 'Garmin'),
    ];
    return Container(
      color: AppColors.charcoal,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: InkWell(
                    onTap: () => onTap(i),
                    child: Semantics(
                      selected: i == index,
                      button: true,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            i == index ? items[i].$2 : items[i].$1,
                            color: i == 1 && recording && i != index
                                ? AppColors.danger
                                : (i == index ? AppColors.lime : AppColors.muted),
                          ),
                          const SizedBox(height: 4),
                          Text(items[i].$3,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight:
                                    i == index ? FontWeight.w700 : FontWeight.w600,
                                color: i == index ? AppColors.lime : AppColors.muted,
                              )),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
