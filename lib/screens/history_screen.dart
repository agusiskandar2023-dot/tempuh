import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../data/activity_store.dart';
import '../models/activity.dart';
import 'home_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  SportType? _filter;

  static const _labels = {
    SportType.running: 'Lari',
    SportType.jogging: 'Jogging',
    SportType.walking: 'Jalan',
    SportType.cycling: 'Sepeda',
  };

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ActivityStore>();
    final items = _filter == null
        ? store.items
        : store.items.where((a) => a.sport == _filter).toList();
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: store.reload,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
            children: [
              const Text('Riwayat',
                  style: TextStyle(
                      fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _chip('Semua', null),
                  for (final s in SportType.values) _chip(_labels[s]!, s),
                ],
              ),
              const SizedBox(height: 16),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(
                    child: Text('Belum ada aktivitas untuk jenis ini.',
                        style: TextStyle(color: AppColors.muted)),
                  ),
                )
              else
                for (final a in items) ...[
                  ActivityCard(activity: a),
                  const SizedBox(height: 10),
                ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, SportType? s) {
    final on = _filter == s;
    return Material(
      color: on ? AppColors.lime : AppColors.charcoal,
      shape: StadiumBorder(
          side: BorderSide(color: on ? AppColors.lime : AppColors.raised)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => setState(() => _filter = s),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: on ? AppColors.navy : AppColors.soft)),
        ),
      ),
    );
  }
}
