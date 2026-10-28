import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../data/activity_store.dart';
import '../data/database.dart';
import '../services/cloud_service.dart';

/// Akun Neon + status sinkron. Akun yang sama dipakai di web Tempuh.
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cloud = context.watch<CloudService>();
    return Scaffold(
      appBar: AppBar(title: const Text('Akun & Sinkron')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            if (cloud.loggedIn) _SyncPanel(cloud: cloud) else const _LoginForm(),
            const SizedBox(height: 24),
            const _BackupCard(),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: AppColors.charcoal, borderRadius: BorderRadius.circular(18)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Web Tempuh',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  const Text(
                      'Dashboard, riwayat, dan upload file .FIT Garmin dari komputer. Login dengan akun yang sama.',
                      style: TextStyle(fontSize: 13, color: AppColors.muted, height: 1.5)),
                  const SizedBox(height: 10),
                  Row(children: [
                    const Expanded(
                      child: SelectableText(CloudConfig.webUrl,
                          style: TextStyle(color: AppColors.lime, fontSize: 13)),
                    ),
                    IconButton(
                      tooltip: 'Salin alamat',
                      icon: const Icon(Icons.copy, size: 20),
                      onPressed: () {
                        Clipboard.setData(const ClipboardData(text: CloudConfig.webUrl));
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Alamat web disalin.')));
                      },
                    ),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Center(
              child: Text('$appName · $appCredit',
                  style: TextStyle(fontSize: 12, color: AppColors.muted)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncPanel extends StatelessWidget {
  final CloudService cloud;
  const _SyncPanel({required this.cloud});

  @override
  Widget build(BuildContext context) {
    final last = cloud.lastSync == null
        ? 'Belum pernah'
        : DateFormat('d MMM yyyy · HH:mm', 'id_ID').format(cloud.lastSync!);
    final ok = cloud.lastError == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: AppColors.charcoal, borderRadius: BorderRadius.circular(20)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                      color: AppColors.raised, borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.person, color: AppColors.lime),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(cloud.name ?? cloud.email ?? '-',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      Text(cloud.email ?? '',
                          style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                    ],
                  ),
                ),
              ]),
              const Divider(height: 28, color: AppColors.raised),
              _row(Icons.cloud_done_outlined, 'Sinkron terakhir', last),
              _row(Icons.cloud_upload_outlined, 'Menunggu dikirim',
                  '${cloud.pending} aktivitas'),
              if (!ok)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(cloud.lastError!,
                      style: const TextStyle(color: AppColors.amber, fontSize: 13)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            onPressed: cloud.syncing
                ? null
                : () async {
                    final r = await cloud.sync();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(r == null
                            ? (cloud.lastError ?? 'Sinkron gagal.')
                            : 'Sinkron selesai: ${r.pushed} terkirim, ${r.pulled} diterima${r.deleted > 0 ? ', ${r.deleted} dihapus' : ''}.')));
                  },
            icon: cloud.syncing
                ? const SizedBox(
                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync),
            label: Text(cloud.syncing ? 'Menyinkronkan…' : 'Sinkron sekarang',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
            'Sinkron berjalan otomatis setelah aktivitas selesai dan saat aplikasi dibuka. Data di HP tetap disimpan.',
            style: TextStyle(fontSize: 12, color: AppColors.muted, height: 1.5)),
        const SizedBox(height: 14),
        OutlinedButton(
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: AppColors.charcoal,
                title: const Text('Keluar dari akun?'),
                content: const Text(
                    'Data di HP tetap ada. Aktivitas baru tidak tersinkron sampai Anda masuk lagi.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Batal')),
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Keluar')),
                ],
              ),
            );
            if (ok == true) await cloud.signOut();
          },
          child: const Text('Keluar'),
        ),
      ],
    );
  }

  Widget _row(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Icon(icon, size: 18, color: AppColors.muted),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(color: AppColors.soft, fontSize: 14)),
          const Spacer(),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        ]),
      );
}

class _LoginForm extends StatefulWidget {
  const _LoginForm();

  @override
  State<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<_LoginForm> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _register = false;
  bool _busy = false;
  bool _hide = true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final pass = _pass.text;
    if (email.isEmpty || pass.length < 8) {
      setState(() => _error = 'Isi email dan kata sandi (minimal 8 karakter).');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final cloud = context.read<CloudService>();
    try {
      if (_register) {
        final name = _name.text.trim().isEmpty ? email.split('@').first : _name.text.trim();
        await cloud.signUp(name, email, pass);
      } else {
        await cloud.signIn(email, pass);
      }
    } on CloudException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Tidak bisa terhubung ke server. Periksa internet. ($e)');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        filled: true,
        fillColor: AppColors.navy,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.raised)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.raised)),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration:
          BoxDecoration(color: AppColors.charcoal, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const TempuhLogo(size: 40, background: AppColors.navy),
            const SizedBox(width: 12),
            Text(_register ? 'Buat akun' : 'Masuk',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 8),
          const Text(
              'Masuk agar aktivitas di HP tersimpan di cloud (Neon) dan muncul di web Tempuh.',
              style: TextStyle(fontSize: 13, color: AppColors.muted, height: 1.5)),
          const SizedBox(height: 16),
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: const Color(0x1FEF4444), borderRadius: BorderRadius.circular(12)),
              child: Text(_error!, style: const TextStyle(color: Color(0xFFFECACA))),
            ),
            const SizedBox(height: 12),
          ],
          if (_register) ...[
            TextField(
                controller: _name,
                decoration: _dec('Nama'),
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name]),
            const SizedBox(height: 12),
          ],
          TextField(
              controller: _email,
              decoration: _dec('Email'),
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email]),
          const SizedBox(height: 12),
          TextField(
            controller: _pass,
            obscureText: _hide,
            decoration: _dec('Kata sandi').copyWith(
              suffixIcon: IconButton(
                tooltip: _hide ? 'Tampilkan' : 'Sembunyikan',
                icon: Icon(_hide ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _hide = !_hide),
              ),
            ),
            onSubmitted: (_) => _submit(),
            autofillHints: const [AutofillHints.password],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: FilledButton(
              style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_register ? 'Daftar' : 'Masuk',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ),
          TextButton(
            onPressed: () => setState(() {
              _register = !_register;
              _error = null;
            }),
            child: Text(_register ? 'Sudah punya akun? Masuk' : 'Belum punya akun? Daftar'),
          ),
        ],
      ),
    );
  }
}

/// Backup semua aktivitas + rute ke file JSON, dan pulihkan dari file itu.
/// Pemulihan hanya menambah aktivitas yang belum ada; tidak menimpa data.
class _BackupCard extends StatefulWidget {
  const _BackupCard();

  @override
  State<_BackupCard> createState() => _BackupCardState();
}

class _BackupCardState extends State<_BackupCard> {
  bool _busy = false;

  Future<void> _backup() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final json = await AppDatabase.instance.exportJson();
      final name =
          'tempuh-backup-${DateFormat('yyyyMMdd-HHmm').format(DateTime.now())}.json';
      final saved = await FilePicker.platform.saveFile(
        dialogTitle: 'Simpan backup Tempuh',
        fileName: name,
        bytes: Uint8List.fromList(utf8.encode(json)),
      );
      messenger.showSnackBar(SnackBar(
          content: Text(saved == null ? 'Backup dibatalkan.' : 'Backup tersimpan: $name')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Backup gagal: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final messenger = ScaffoldMessenger.of(context);
    final store = context.read<ActivityStore>();
    final res = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
    final bytes = res?.files.single.bytes;
    if (bytes == null) return;
    setState(() => _busy = true);
    try {
      final added = await AppDatabase.instance.importJson(utf8.decode(bytes));
      await store.reload();
      messenger.showSnackBar(SnackBar(
          content: Text(added == 0
              ? 'Semua aktivitas di backup sudah ada di HP.'
              : '$added aktivitas dipulihkan.')));
    } on FormatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Gagal memulihkan: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration:
          BoxDecoration(color: AppColors.charcoal, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(children: [
            Icon(Icons.save_alt, color: AppColors.lime),
            SizedBox(width: 10),
            Text('Backup data', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 6),
          const Text(
              'Simpan salinan semua aktivitas dan rute ke file, misalnya sebelum ganti HP. Memulihkan hanya menambah aktivitas yang belum ada.',
              style: TextStyle(fontSize: 13, color: AppColors.muted, height: 1.5)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: _busy ? null : _backup,
                icon: const Icon(Icons.download),
                label: const Text('Backup ke file'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _restore,
                icon: const Icon(Icons.upload),
                label: const Text('Pulihkan'),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
