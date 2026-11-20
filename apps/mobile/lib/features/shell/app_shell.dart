import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../assets/asset_editor.dart';
import '../common/widgets.dart';
import '../finance/transaction_editor.dart';
import '../tasks/task_editor.dart';
import '../../app/providers.dart';
import '../../app/sync_actions.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  static const _titles = ['Hari Ini', 'Kegiatan', 'Keuangan', 'Aset', 'Lainnya'];

  StatefulNavigationShell get navigationShell => widget.navigationShell;

  int get _index => navigationShell.currentIndex;

  @override
  void initState() {
    super.initState();
    // Pastikan pengingat tetap terjadwal setelah app ditutup/di-reinstall.
    Future.microtask(_rescheduleReminders);
  }

  Future<void> _rescheduleReminders() async {
    try {
      await rescheduleAllReminders(ref);
    } catch (_) {
      // Notifikasi bukan fitur kritis: jangan sampai menghalangi app.
    }
  }

  void _onDestinationSelected(int index) {
    navigationShell.goBranch(index, initialLocation: index == navigationShell.currentIndex);
  }

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(currentWorkspaceProvider);
    final accent = workspace == null ? Theme.of(context).colorScheme.primary : workspaceColor(workspace.type);

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 56,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: _WorkspaceAvatar(accent: accent, onTap: () => _showWorkspaceSwitcher(context, ref)),
        ),
        titleSpacing: 4,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_titles[_index], style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
            Text(
              workspace?.name ?? 'Memuat…',
              style: TextStyle(fontSize: 11.5, color: accent, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          if (_index == 0)
            IconButton(
              tooltip: 'Kalender',
              onPressed: () => context.push('/calendar'),
              icon: const Icon(Icons.calendar_month_outlined),
            ),
          IconButton(
            tooltip: 'Pengingat',
            onPressed: () => context.push('/reminders'),
            icon: const Icon(Icons.notifications_none_rounded),
          ),
          SyncBadge(onTap: () => runSync(context, ref)),
          const SizedBox(width: 4),
        ],
      ),
      body: navigationShell,
      floatingActionButton: _buildFab(context, ref),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _onDestinationSelected,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: 'Hari Ini'),
          NavigationDestination(icon: Icon(Icons.checklist_outlined), selectedIcon: Icon(Icons.checklist), label: 'Kegiatan'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet), label: 'Keuangan'),
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Aset'),
          NavigationDestination(icon: Icon(Icons.more_horiz), selectedIcon: Icon(Icons.more), label: 'Lainnya'),
        ],
      ),
    );
  }

  Widget? _buildFab(BuildContext context, WidgetRef ref) {
    switch (_index) {
      case 0:
      case 1:
        return FloatingActionButton.extended(
          onPressed: () => showTaskEditor(context, ref),
          icon: const Icon(Icons.add),
          label: const Text('Tugas'),
        );
      case 2:
        return FloatingActionButton.extended(
          onPressed: () => showTransactionEditor(context, ref),
          icon: const Icon(Icons.add),
          label: const Text('Transaksi'),
        );
      case 3:
        return FloatingActionButton.extended(
          onPressed: () => showAssetEditor(context, ref),
          icon: const Icon(Icons.add),
          label: const Text('Aset'),
        );
      default:
        return null;
    }
  }

  Future<void> _showWorkspaceSwitcher(BuildContext context, WidgetRef ref) async {
    final workspaces = ref.read(workspacesProvider).valueOrNull ?? const [];
    final activeId = ref.read(currentWorkspaceProvider)?.id;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text('Pilih Ruang Kerja', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  'Data Pribadi dan Perusahaan dipisah total — laporan tidak pernah tercampur.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              for (final ws in workspaces)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: workspaceColor(ws.type).withValues(alpha: 0.15),
                    child: Icon(
                      ws.type == 'COMPANY' ? Icons.business_rounded : Icons.person_rounded,
                      color: workspaceColor(ws.type),
                      size: 20,
                    ),
                  ),
                  title: Text(ws.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(ws.type == 'COMPANY' ? 'Perusahaan' : 'Pribadi'),
                  trailing: ws.id == activeId ? const Icon(Icons.check_circle, size: 20) : null,
                  onTap: () async {
                    await ref.read(activeWorkspaceIdProvider.notifier).select(ws.id);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }
}

class _WorkspaceAvatar extends ConsumerWidget {
  const _WorkspaceAvatar({required this.accent, required this.onTap});

  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final photo = auth.userPhoto;

    ImageProvider? imageProvider;
    if (photo != null && photo.isNotEmpty) {
      if (photo.startsWith('data:image')) {
        final base64Part = photo.split(',').last;
        imageProvider = MemoryImage(base64Decode(base64Part));
      } else if (photo.startsWith('http')) {
        imageProvider = NetworkImage(photo);
      }
    }

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(11),
          image: imageProvider != null
              ? DecorationImage(image: imageProvider, fit: BoxFit.cover)
              : null,
        ),
        child: imageProvider == null
            ? Icon(Icons.swap_horiz_rounded, color: accent, size: 20)
            : null,
      ),
    );
  }
}
