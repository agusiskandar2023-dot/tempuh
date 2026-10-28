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

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ActivityStore>();
    final items = _filter == null
        ? store.items
        : store.items.where((a) => a.sport == _filter).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Riwayat')),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                _chip('Semua', null),
                for (final s in SportType.values) _chip(s.label, s),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: store.reload,
              child: items.isEmpty
                  ? ListView(children: const [
                      SizedBox(height: 120),
                      Center(
                          child: Text('Belum ada aktivitas.',
                              style: TextStyle(color: AppColors.muted))),
                    ])
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => ActivityCard(activity: items[i]),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, SportType? s) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: _filter == s,
          onSelected: (_) => setState(() => _filter = s),
        ),
      );
}
