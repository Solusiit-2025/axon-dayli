import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/dates.dart';
import '../../data/local/database.dart';
import '../common/widgets.dart';
import 'reminder_editor.dart';

class RemindersScreen extends ConsumerWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final reminders = ref.watch(remindersProvider).valueOrNull ?? const <Reminder>[];

    final now = DateTime.now();
    final upcoming = reminders
        .where((r) => r.isActive && !r.triggerAt.isBefore(now))
        .toList()
      ..sort((a, b) => a.triggerAt.compareTo(b.triggerAt));
    final past = reminders
        .where((r) => r.isActive && r.triggerAt.isBefore(now))
        .toList()
      ..sort((a, b) => b.triggerAt.compareTo(a.triggerAt));
    final inactive = reminders.where((r) => !r.isActive).toList();

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Pengingat'),
        actions: [
          IconButton(
            onPressed: () => showReminderEditor(context, ref),
            icon: const Icon(Icons.add),
            tooltip: 'Pengingat baru',
          ),
          IconButton(
            tooltip: 'Tes notifikasi (10 detik)',
            icon: const Icon(Icons.notification_add_outlined),
            onPressed: () async {
              final notif = ref.read(notificationsProvider);
              final messenger = ScaffoldMessenger.of(context);
              final granted = await notif.ensurePermission();
              if (!granted) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Izin notifikasi belum diberikan. Aktifkan di pengaturan Android.')),
                );
                return;
              }
              try {
                await notif.schedule(
                  reminderId: 'test-notification',
                  title: 'Tes pengingat Axon Dayli',
                  body: 'Notifikasi berbunyi. Pengingat sudah berfungsi.',
                  triggerAt: DateTime.now().add(const Duration(seconds: 10)),
                );
                messenger.showSnackBar(
                  const SnackBar(content: Text('Notifikasi tes akan berbunyi ±10 detik lagi.')),
                );
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(content: Text('Gagal menjadwalkan notifikasi tes: $e')),
                );
              }
            },
          ),
        ],
      ),
      body: reminders.isEmpty
          ? EmptyState(
              icon: Icons.notifications_none_rounded,
              title: 'Belum ada pengingat',
              message: 'Pasang pengingat agar kegiatan dan tenggat tidak terlewat.',
              action: FilledButton.tonal(
                onPressed: () => showReminderEditor(context, ref),
                child: const Text('Buat pengingat'),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                const _ExactAlarmNotice(),
                Text(
                  'Pengingat berbunyi dari perangkat ini, jadi tetap jalan tanpa internet.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                if (upcoming.isNotEmpty) ...[
                  const SectionHeader(title: 'Akan datang', padding: EdgeInsets.fromLTRB(4, 16, 4, 8)),
                  _ReminderGroup(reminders: upcoming, ref: ref),
                ],
                if (past.isNotEmpty) ...[
                  const SectionHeader(title: 'Waktu sudah lewat', padding: EdgeInsets.fromLTRB(4, 16, 4, 8)),
                  _ReminderGroup(reminders: past, ref: ref, dimmed: true),
                ],
                if (inactive.isNotEmpty) ...[
                  const SectionHeader(title: 'Nonaktif', padding: EdgeInsets.fromLTRB(4, 16, 4, 8)),
                  _ReminderGroup(reminders: inactive, ref: ref, dimmed: true),
                ],
              ],
            ),
    );
  }
}

/// Peringatan bila sistem belum mengizinkan alarm tepat waktu (Android 12+).
/// Tanpa izin ini pengingat tetap dijadwalkan, tapi bisa terlambat saat HP
/// sedang idle / hemat baterai.
class _ExactAlarmNotice extends ConsumerStatefulWidget {
  const _ExactAlarmNotice();

  @override
  ConsumerState<_ExactAlarmNotice> createState() => _ExactAlarmNoticeState();
}

class _ExactAlarmNoticeState extends ConsumerState<_ExactAlarmNotice> {
  bool? _allowed;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final allowed = await ref.read(notificationsProvider).exactAlarmsAllowed();
    if (mounted) setState(() => _allowed = allowed);
  }

  Future<void> _request() async {
    setState(() => _busy = true);
    try {
      final notifications = ref.read(notificationsProvider);
      final allowed = await notifications.requestExactAlarmsPermission();
      if (allowed) {
        // Jadwal lama memakai mode inexact — jadwalkan ulang secara exact.
        await rescheduleAllReminders(ref);
      }
      if (mounted) setState(() => _allowed = allowed);
      if (mounted && allowed) {
        showAppSnack(context, 'Alarm tepat waktu aktif. Pengingat akan berbunyi pas waktunya.');
      }
    } catch (_) {
      if (mounted) setState(() => _allowed = false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_allowed == null || _allowed == true) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.alarm_off_rounded, size: 18, color: theme.colorScheme.error),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Alarm tepat waktu belum diizinkan',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Pengingat masih dijadwalkan, tapi Android bisa menundanya saat HP idle. '
                'Izinkan "Alarm & pengingat" agar bunyi tepat waktu.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: _busy ? null : _request,
                  child: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Izinkan alarm tepat waktu'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReminderGroup extends StatelessWidget {
  const _ReminderGroup({required this.reminders, required this.ref, this.dimmed = false});

  final List<Reminder> reminders;
  final WidgetRef ref;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Column(
        children: [
          for (var i = 0; i < reminders.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 56),
            ListTile(
              contentPadding: const EdgeInsets.only(left: 12, right: 4),
              leading: CircleAvatar(
                radius: 17,
                backgroundColor: (reminders[i].isActive && !dimmed
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline)
                    .withValues(alpha: 0.12),
                child: Icon(
                  reminders[i].recurrenceRule == null
                      ? Icons.alarm
                      : Icons.repeat,
                  size: 16,
                  color: dimmed ? theme.colorScheme.outline : theme.colorScheme.primary,
                ),
              ),
              title: Text(
                reminders[i].title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: dimmed ? theme.colorScheme.onSurfaceVariant : null,
                ),
              ),
              subtitle: Text(
                _subtitle(reminders[i]),
                style: const TextStyle(fontSize: 11),
              ),
              trailing: Switch(
                value: reminders[i].isActive,
                onChanged: (value) async {
                  final notif = ref.read(notificationsProvider);
                  final reminder = reminders[i];
                  await ref.read(databaseProvider).setReminderActive(reminder, value);
                  ref.read(syncSchedulerProvider).schedule();

                  try {
                    if (value) {
                      await notif.ensurePermission();
                      await notif.schedule(
                        reminderId: reminder.id,
                        title: reminder.title,
                        body: reminder.message,
                        triggerAt: reminder.triggerAt,
                        recurrenceRule: reminder.recurrenceRule,
                        payload: reminder.entityId,
                      );
                    } else {
                      await notif.cancel(reminder.id);
                    }
                  } catch (e) {
                    debugPrint('Gagal menjadwalkan pengingat: $e');
                  }
                },
              ),
              onTap: () => showReminderEditor(context, ref, existing: reminders[i]),
            ),
          ],
        ],
      ),
    );
  }

  String _subtitle(Reminder reminder) {
    final when = '${formatDate(reminder.triggerAt)} · ${formatTime(reminder.triggerAt)}';
    final repeat = switch (reminder.recurrenceRule) {
      'DAILY' => ' · tiap hari',
      'WEEKLY' => ' · tiap minggu',
      _ => '',
    };
    final overdue = reminder.isActive && reminder.triggerAt.isBefore(DateTime.now());
    return overdue ? '$when$repeat · terlewat' : '$when$repeat';
  }
}

/// Navigasi ke tugas terkait (dipakai saat notifikasi diketuk).
void openReminderTarget(BuildContext context, String entityId) {
  context.push('/task/$entityId');
}
