import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/sync_actions.dart';
import '../../core/theme.dart';
import '../../data/local/database.dart';
import '../common/widgets.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final auth = ref.watch(authControllerProvider);
    final pending = ref.watch(pendingSyncCountProvider).valueOrNull ?? 0;
    final workspaces = ref.watch(workspacesProvider).valueOrNull ?? const <Workspace>[];
    final active = ref.watch(currentWorkspaceProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _showUserProfileModal(context, ref),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  _buildUserAvatar(auth.userPhoto, auth.name, theme, radius: 24),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          auth.name ?? 'Pengguna',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                        Text(
                          auth.email ?? '',
                          style: TextStyle(fontSize: 11.5, color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 20, color: theme.colorScheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),

        const SectionHeader(title: 'Sinkronisasi', padding: EdgeInsets.fromLTRB(4, 20, 4, 8)),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: Icon(
                  pending == 0 ? Icons.cloud_done_outlined : Icons.cloud_upload_outlined,
                  color: pending == 0 ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                ),
                title: Text(
                  pending == 0 ? 'Semua tersinkron' : '$pending perubahan menunggu',
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Data tersimpan di perangkat dan dikirim otomatis saat online.',
                  style: TextStyle(fontSize: 11),
                ),
                trailing: FilledButton.tonal(
                  onPressed: () => runSync(context, ref),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: const Text('Sync', style: TextStyle(fontSize: 12)),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.dns_outlined, size: 20),
                title: const Text('Alamat server', style: TextStyle(fontSize: 13.5)),
                subtitle: FutureBuilder<String>(
                  future: ref.read(sessionStoreProvider).baseUrl(),
                  builder: (context, snapshot) => Text(
                    snapshot.data ?? '…',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => _editServerUrl(context, ref),
              ),
            ],
          ),
        ),

        const SectionHeader(title: 'Kelola', padding: EdgeInsets.fromLTRB(4, 20, 4, 8)),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.notifications_none_rounded, size: 20),
                title: const Text('Pengingat', style: TextStyle(fontSize: 13.5)),
                subtitle: const Text(
                  'Alarm kegiatan, tenggat, dan agenda',
                  style: TextStyle(fontSize: 11),
                ),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => context.push('/reminders'),
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.calendar_month_outlined, size: 20),
                title: const Text('Kalender', style: TextStyle(fontSize: 13.5)),
                subtitle: const Text('Agenda dan tenggat per tanggal', style: TextStyle(fontSize: 11)),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => context.push('/calendar'),
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.account_balance_wallet_outlined, size: 20),
                title: const Text('Dompet', style: TextStyle(fontSize: 13.5)),
                subtitle: const Text('Tunai, bank, dan e-wallet', style: TextStyle(fontSize: 11)),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => context.push('/wallets'),
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.folder_shared_outlined, size: 20),
                title: const Text('Brankas Dokumen', style: TextStyle(fontSize: 13.5)),
                subtitle: const Text('KTP, KK, Buku Nikah, Akta Notaris, NPWP', style: TextStyle(fontSize: 11)),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => context.push('/documents'),
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.savings_outlined, size: 20),
                title: const Text('Anggaran & Utang', style: TextStyle(fontSize: 13.5)),
                subtitle: const Text(
                  'Batas belanja bulanan dan pinjaman',
                  style: TextStyle(fontSize: 11),
                ),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => context.push('/planning'),
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.bar_chart_rounded, size: 20),
                title: const Text('Laporan Keuangan', style: TextStyle(fontSize: 13.5)),
                subtitle: const Text('Analisis arus kas, kategori, anggaran, utang', style: TextStyle(fontSize: 11)),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => context.push('/reports'),
              ),
            ],
          ),
        ),

        const SectionHeader(title: 'Cadangan & Pemulihan (Offline-First)', padding: EdgeInsets.fromLTRB(4, 20, 4, 8)),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.download_for_offline_outlined, size: 20, color: Color(0xFF10B981)),
                title: const Text('Ekspor Cadangan Data (JSON)', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                subtitle: const Text('Salin seluruh data lokal (Tugas, Keuangan, Aset, Dokumen) ke Clipboard', style: TextStyle(fontSize: 11)),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => _exportBackup(context, ref),
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.upload_file_outlined, size: 20, color: Color(0xFF2563EB)),
                title: const Text('Impor / Pulihkan Cadangan Data', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                subtitle: const Text('Pulihkan data dari teks cadangan JSON lokal', style: TextStyle(fontSize: 11)),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => _importBackup(context, ref),
              ),
            ],
          ),
        ),

        const SectionHeader(title: 'Ruang kerja', padding: EdgeInsets.fromLTRB(4, 20, 4, 8)),
        Card(
          child: Column(
            children: [
              for (var i = 0; i < workspaces.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 56),
                ListTile(
                  leading: CircleAvatar(
                    radius: 17,
                    backgroundColor: workspaceColor(workspaces[i].type).withValues(alpha: 0.12),
                    child: Icon(
                      workspaces[i].type == 'COMPANY' ? Icons.business : Icons.person,
                      size: 16,
                      color: workspaceColor(workspaces[i].type),
                    ),
                  ),
                  title: Text(
                    workspaces[i].name,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    workspaces[i].type == 'COMPANY' ? 'Perusahaan · data terpisah' : 'Pribadi · data terpisah',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: workspaces[i].id == active?.id
                      ? Icon(Icons.check_circle, size: 18, color: theme.colorScheme.primary)
                      : null,
                  onTap: () => ref.read(activeWorkspaceIdProvider.notifier).select(workspaces[i].id),
                ),
              ],
            ],
          ),
        ),

        const SectionHeader(title: 'Tentang', padding: EdgeInsets.fromLTRB(4, 20, 4, 8)),
        Card(
          child: Column(
            children: [
              const ListTile(
                leading: Icon(Icons.offline_bolt_outlined, size: 20),
                title: Text('Mode offline', style: TextStyle(fontSize: 13.5)),
                subtitle: Text(
                  'Semua fitur berjalan tanpa internet. Perubahan dikirim saat online.',
                  style: TextStyle(fontSize: 11),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.info_outline, size: 20),
                title: const Text('Versi', style: TextStyle(fontSize: 13.5)),
                subtitle: const Text('Axon Dayli 1.0.0 (build 1)', style: TextStyle(fontSize: 11)),
                trailing: Text('Flutter', style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: () => _confirmLogout(context, ref),
          icon: const Icon(Icons.logout, size: 18),
          label: const Text('Keluar'),
          style: OutlinedButton.styleFrom(foregroundColor: kDanger),
        ),
        const SizedBox(height: 12),
        Text(
          'Keluar akan menghapus data lokal di perangkat ini. Data di server tetap aman dan bisa diambil lagi setelah masuk.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 10.5,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Future<void> _showUserProfileModal(BuildContext context, WidgetRef ref) async {
    final auth = ref.read(authControllerProvider);
    final theme = Theme.of(context);
    final workspaces = ref.read(workspacesProvider).valueOrNull ?? const [];
    final docs = ref.read(documentsProvider).valueOrNull ?? const [];
    final assets = ref.read(assetsProvider).valueOrNull ?? const [];
    final txns = ref.read(transactionsProvider).valueOrNull ?? const [];

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.88,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Card Profil
              Center(
                child: Column(
                  children: [
                    Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        _buildUserAvatar(auth.userPhoto, auth.name, theme, radius: 36),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => _pickProfilePhoto(ctx, ref),
                            borderRadius: BorderRadius.circular(99),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary,
                                shape: BoxShape.circle,
                                border: Border.all(color: theme.colorScheme.surface, width: 2),
                              ),
                              child: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          auth.name ?? 'Pengguna',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          tooltip: 'Ubah Nama',
                          onPressed: () => _editProfileName(ctx, ref, auth.name ?? ''),
                        ),
                      ],
                    ),
                    Text(
                      auth.email ?? '',
                      style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF059669).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified_user_rounded, size: 14, color: Color(0xFF059669)),
                          SizedBox(width: 4),
                          Text(
                            'Akun Terverifikasi · Cloud VPS Active',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF059669)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const Divider(height: 1),
              const SizedBox(height: 14),

              // Rincian Statistik Penggunaan
              const Text('Ringkasan Aktivitas Akun', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _ProfileStatTile(
                      icon: Icons.business_center_outlined,
                      label: 'Ruang Kerja',
                      value: '${workspaces.length}',
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ProfileStatTile(
                      icon: Icons.folder_shared_outlined,
                      label: 'Dokumen',
                      value: '${docs.length}',
                      color: const Color(0xFF7C3AED),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ProfileStatTile(
                      icon: Icons.inventory_2_outlined,
                      label: 'Aset',
                      value: '${assets.length}',
                      color: const Color(0xFFD97706),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ProfileStatTile(
                      icon: Icons.receipt_long_outlined,
                      label: 'Transaksi',
                      value: '${txns.length}',
                      color: const Color(0xFF059669),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Preferensi Akun
              const Text('Preferensi & Regional', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    const ListTile(
                      leading: Icon(Icons.attach_money_rounded, size: 20),
                      title: Text('Mata Uang Utama', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Text('IDR — Indonesia Rupiah (Rp)', style: TextStyle(fontSize: 11)),
                    ),
                    const Divider(height: 1),
                    const ListTile(
                      leading: Icon(Icons.schedule_rounded, size: 20),
                      title: Text('Zona Waktu', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Text('WIB — Asia/Jakarta (UTC+07:00)', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Informasi Perangkat & Keamanan
              const Text('Informasi Perangkat & Server', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    FutureBuilder<String?>(
                      future: ref.read(sessionStoreProvider).deviceId(),
                      builder: (context, snapshot) => ListTile(
                        leading: const Icon(Icons.smartphone_rounded, size: 20),
                        title: const Text('ID Perangkat Terdaftar', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        subtitle: Text(snapshot.data ?? 'Menghubungkan…', style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace')),
                      ),
                    ),
                    const Divider(height: 1),
                    FutureBuilder<String>(
                      future: ref.read(sessionStoreProvider).baseUrl(),
                      builder: (context, snapshot) => ListTile(
                        leading: const Icon(Icons.cloud_done_rounded, size: 20, color: Color(0xFF10B981)),
                        title: const Text('Server Cloud VPS', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        subtitle: Text(snapshot.data ?? 'https://dailypilot.solusiit.id', style: const TextStyle(fontSize: 11)),
                      ),
                    ),
                    const Divider(height: 1),
                    const ListTile(
                      leading: Icon(Icons.storage_rounded, size: 20),
                      title: Text('Database Engine Lokal', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Text('Drift SQLite v7 (Native Performance)', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Tutup Profil'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editProfileName(BuildContext context, WidgetRef ref, String currentName) async {
    final controller = TextEditingController(text: currentName);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ubah Nama Pengguna'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Nama Lengkap'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isEmpty) return;

              await ref.read(authControllerProvider.notifier).updateProfileName(newName);
              if (ctx.mounted) {
                Navigator.pop(ctx);
                showAppSnack(context, 'Nama profil berhasil diperbarui');
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportBackup(BuildContext context, WidgetRef ref) async {
    try {
      final db = ref.read(databaseProvider);
      final jsonStr = await db.exportBackupJson();

      await Clipboard.setData(ClipboardData(text: jsonStr));

      if (context.mounted) {
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Cadangan Berhasil Dibuat'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Seluruh data lokal Anda telah disalin ke Clipboard!'),
                const SizedBox(height: 12),
                const Text('Gunakan tombol di bawah untuk menyalin kembali teks berikut:'),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  height: 100,
                  child: SingleChildScrollView(
                    child: Text(jsonStr, style: const TextStyle(fontSize: 10, fontFamily: 'monospace')),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: jsonStr));
                  showAppSnack(ctx, 'Teks cadangan disalin ke clipboard');
                },
                child: const Text('Salin Teks'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Selesai'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (context.mounted) showAppSnack(context, 'Gagal membuat cadangan: $e', error: true);
    }
  }

  Future<void> _importBackup(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pulihkan Data Cadangan'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Tempelkan teks JSON cadangan data Anda di bawah ini:'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 6,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              decoration: const InputDecoration(
                hintText: 'Tempel teks {"version":1, "workspaces":[...]} di sini...',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
            onPressed: () async {
              final text = controller.text.trim();
              if (text.isEmpty) return;

              try {
                final db = ref.read(databaseProvider);
                final restoredCount = await db.importBackupJson(text);
                ref.read(syncSchedulerProvider).schedule();

                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  showAppSnack(context, 'Berhasil memulihkan $restoredCount baris data!');
                }
              } catch (e) {
                if (ctx.mounted) showAppSnack(ctx, 'Gagal memulihkan data: $e', error: true);
              }
            },
            child: const Text('Pulihkan Data'),
          ),
        ],
      ),
    );
  }

  Future<void> _editServerUrl(BuildContext context, WidgetRef ref) async {
    final store = ref.read(sessionStoreProvider);
    final controller = TextEditingController(text: await store.baseUrl());

    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Alamat server'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'http://192.168.1.10:4000',
            helperText: 'Emulator Android: http://10.0.2.2:4000',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          FilledButton(
            onPressed: () async {
              await store.setBaseUrl(controller.text.trim());
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Keluar dari akun?'),
        content: const Text(
          'Data lokal akan dihapus dari perangkat ini. Pastikan semua perubahan sudah tersinkron.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: kDanger),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await ref.read(authControllerProvider.notifier).logout();
    }
  }
}

class _ProfileStatTile extends StatelessWidget {
  const _ProfileStatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 9.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

Widget _buildUserAvatar(String? photo, String? name, ThemeData theme, {required double radius}) {
  ImageProvider? provider;
  if (photo != null && photo.isNotEmpty) {
    if (photo.startsWith('data:image')) {
      final base64Part = photo.split(',').last;
      provider = MemoryImage(base64Decode(base64Part));
    } else if (photo.startsWith('http')) {
      provider = NetworkImage(photo);
    }
  }

  return CircleAvatar(
    radius: radius,
    backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
    backgroundImage: provider,
    child: provider == null
        ? Text(
            (name?.isNotEmpty == true ? name! : 'U').characters.first.toUpperCase(),
            style: TextStyle(
              fontSize: radius * 0.75,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
            ),
          )
        : null,
  );
}

Future<void> _pickProfilePhoto(BuildContext context, WidgetRef ref) async {
  try {
    final choice = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined, color: Color(0xFF4F46E5)),
              title: const Text('Ambil Foto Kamera', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Foto profil langsung dari kamera HP'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: Color(0xFF2563EB)),
              title: const Text('Pilih dari Galeri Foto', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Pilih foto profil dari galeri HP Anda'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (choice == null) return;

    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(source: choice, maxWidth: 512, maxHeight: 512, imageQuality: 80);
    if (file == null) return;

    final bytes = await file.readAsBytes();
    final base64Str = base64Encode(bytes);
    final mimeType = file.mimeType ?? 'image/jpeg';
    final dataUrl = 'data:$mimeType;base64,$base64Str';

    await ref.read(authControllerProvider.notifier).updateProfilePhoto(dataUrl);

    if (context.mounted) {
      showAppSnack(context, 'Foto profil berhasil diperbarui!');
    }
  } catch (e) {
    if (context.mounted) showAppSnack(context, 'Gagal mengunggah foto profil: $e', error: true);
  }
}
