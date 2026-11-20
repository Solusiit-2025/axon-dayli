import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/dates.dart';
import '../../core/theme.dart';
import '../../data/local/database.dart';
import '../common/widgets.dart';
import '../reminders/reminder_editor.dart';
import 'task_editor.dart';

class TaskDetailScreen extends ConsumerWidget {
  const TaskDetailScreen({super.key, required this.taskId});

  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final task = ref.watch(taskDetailProvider(taskId)).valueOrNull;
    final checklist = ref.watch(checklistProvider(taskId)).valueOrNull ?? const <ChecklistEntry>[];
    final logs = ref.watch(progressLogsProvider(taskId)).valueOrNull ?? const <ProgressLog>[];

    if (task == null) {
      return Scaffold(
        appBar: AppBar(leading: const BackButton()),
        body: const Center(child: Text('Tugas tidak ditemukan')),
      );
    }

    final db = ref.read(databaseProvider);
    final taskReminders = (ref.watch(remindersProvider).valueOrNull ?? const <Reminder>[])
        .where((r) => r.entityId == task.id)
        .toList();
    final overdue = isOverdue(task.dueAt, status: task.status);
    final doneChecklist = checklist.where((c) => c.isDone).length;

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Detail tugas'),
        actions: [
          IconButton(
            tooltip: 'Pasang pengingat',
            onPressed: () => showReminderEditor(context, ref, task: task),
            icon: const Icon(Icons.notifications_none_rounded),
          ),
          IconButton(
            tooltip: 'Ubah',
            onPressed: () => showTaskEditor(context, ref, existing: task),
            icon: const Icon(Icons.edit_outlined),
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'gcal') {
                final title = Uri.encodeComponent(task.title);
                final details = Uri.encodeComponent(task.description ?? 'Kegiatan dari Axon Dayli');
                final startTime = task.dueAt ?? DateTime.now();
                final endTime = startTime.add(const Duration(hours: 1));

                String formatGCalDate(DateTime dt) {
                  final utc = dt.toUtc();
                  return '${utc.year}${utc.month.toString().padLeft(2, '0')}${utc.day.toString().padLeft(2, '0')}T${utc.hour.toString().padLeft(2, '0')}${utc.minute.toString().padLeft(2, '0')}${utc.second.toString().padLeft(2, '0')}Z';
                }

                final dates = '${formatGCalDate(startTime)}/${formatGCalDate(endTime)}';
                final url = 'https://calendar.google.com/calendar/render?action=TEMPLATE&text=$title&details=$details&dates=$dates';

                await Clipboard.setData(ClipboardData(text: url));
                if (context.mounted) {
                  showAppSnack(context, 'Link Google Calendar disalin ke Clipboard!');
                }
              } else if (value == 'delete') {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Hapus tugas?'),
                    content: const Text('Tindakan ini akan menghapus tugas dari semua perangkat.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
                      FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Hapus')),
                    ],
                  ),
                );
                if (ok == true) {
                  await db.deleteTask(task.id);
                  ref.read(syncSchedulerProvider).schedule();
                  if (context.mounted) context.pop();
                }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'gcal',
                child: Row(
                  children: [
                    Icon(Icons.calendar_month_outlined, size: 18, color: Color(0xFF4F46E5)),
                    SizedBox(width: 8),
                    Text('Simpan ke Google Calendar'),
                  ],
                ),
              ),
              PopupMenuItem(value: 'delete', child: Text('Hapus tugas')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Text(
            task.title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              decoration: task.status == 'DONE' ? TextDecoration.lineThrough : null,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Pill(text: statusLabel(task.status), color: statusColor(task.status)),
              _Pill(text: priorityLabel(task.priority), color: priorityColor(task.priority)),
              if (task.dueAt != null)
                _Pill(
                  text: overdue ? relativeDue(task.dueAt!) : 'Tenggat ${formatDate(task.dueAt!)}',
                  color: overdue ? kDanger : theme.colorScheme.onSurfaceVariant,
                ),
            ],
          ),

          const SizedBox(height: 14),
          Card(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      onPressed: () => _showQuickRescheduleModal(context, ref, db, task),
                      icon: const Icon(Icons.edit_calendar_rounded, size: 16),
                      label: const Text('Re-Schedule', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      onPressed: () => _showQuickReReminderModal(context, ref, db, task),
                      icon: const Icon(Icons.notifications_active_outlined, size: 16),
                      label: const Text('Re-Pengingat', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Progres',
                        style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      Text(
                        '${task.progress}%',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.8),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: task.progress / 100,
                      minHeight: 10,
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation(
                        task.progress == 100 ? const Color(0xFF059669) : theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (final p in [0, 25, 50, 75, 100])
                        TextButton(
                          onPressed: () async {
                            await db.updateProgress(task, p);
                            ref.read(syncSchedulerProvider).schedule();
                          },
                          child: Text('$p%', style: const TextStyle(fontSize: 12)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  FilledButton.tonalIcon(
                    onPressed: () => _showProgressDialog(context, ref, db, task),
                    icon: const Icon(Icons.add_task, size: 18),
                    label: const Text('Catat progres + catatan'),
                  ),
                ],
              ),
            ),
          ),

          if (taskReminders.isNotEmpty) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                Text(
                  'Pengingat',
                  style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => showReminderEditor(context, ref, task: task),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Tambah'),
                ),
              ],
            ),
            Card(
              child: Column(
                children: [
                  for (var i = 0; i < taskReminders.length; i++) ...[
                    if (i > 0) const Divider(height: 1, indent: 52),
                    ListTile(
                      dense: true,
                      leading: Icon(
                        taskReminders[i].isActive
                            ? Icons.notifications_active_outlined
                            : Icons.notifications_off_outlined,
                        size: 18,
                        color: taskReminders[i].isActive
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outline,
                      ),
                      title: Text(
                        '${formatDate(taskReminders[i].triggerAt)} · ${formatTime(taskReminders[i].triggerAt)}',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        taskReminders[i].isActive ? 'Aktif' : 'Nonaktif',
                        style: const TextStyle(fontSize: 11),
                      ),
                      onTap: () => showReminderEditor(context, ref, existing: taskReminders[i]),
                    ),
                  ],
                ],
              ),
            ),
          ],

          if (task.description?.isNotEmpty == true) ...[
            const SizedBox(height: 20),
            Text(
              'Catatan',
              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(task.description!, style: const TextStyle(fontSize: 14, height: 1.5)),
          ],

          const SizedBox(height: 24),
          Row(
            children: [
              Text(
                'Checklist',
                style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 6),
              if (checklist.isNotEmpty)
                Text(
                  '$doneChecklist/${checklist.length}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _addChecklistItem(context, ref, db, task),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Item'),
              ),
            ],
          ),

          if (checklist.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Pecah tugas jadi langkah kecil supaya progres lebih terukur.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            )
          else
            Card(
              child: Column(
                children: [
                  for (var i = 0; i < checklist.length; i++) ...[
                    if (i > 0) const Divider(height: 1, indent: 52),
                    CheckboxListTile(
                      value: checklist[i].isDone,
                      onChanged: (_) async {
                        await db.toggleChecklistItem(checklist[i]);
                        ref.read(syncSchedulerProvider).schedule();
                      },
                      title: Text(
                        checklist[i].title,
                        style: TextStyle(
                          fontSize: 13.5,
                          decoration: checklist[i].isDone ? TextDecoration.lineThrough : null,
                          color: checklist[i].isDone ? theme.colorScheme.onSurfaceVariant : null,
                        ),
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                      secondary: IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () async {
                          await db.deleteChecklistItem(checklist[i].id);
                          ref.read(syncSchedulerProvider).schedule();
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),

          const SizedBox(height: 24),
          Text(
            'Riwayat progres',
            style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          if (logs.isEmpty)
            Text(
              'Belum ada catatan progres.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            )
          else
            Card(
              child: Column(
                children: [
                  for (var i = 0; i < logs.length; i++) ...[
                    if (i > 0) const Divider(height: 1, indent: 28),
                    ListTile(
                      dense: true,
                      leading: Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(top: 6),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      title: Text(
                        '${logs[i].progressBefore}% → ${logs[i].progressAfter}%',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${formatDateShort(logs[i].occurredAt)} · ${formatTime(logs[i].occurredAt)}'
                        '${logs[i].note?.isNotEmpty == true ? '\n${logs[i].note}' : ''}',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      isThreeLine: logs[i].note?.isNotEmpty == true,
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _addChecklistItem(
    BuildContext context,
    WidgetRef ref,
    AppDatabase db,
    Task task,
  ) async {
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Item checklist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'mis. Kirim draft ke klien'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Tambah'),
          ),
        ],
      ),
    );

    if (title != null && title.trim().isNotEmpty) {
      await db.addChecklistItem(task.workspaceId, task.id, title.trim());
      ref.read(syncSchedulerProvider).schedule();
    }
  }

  Future<void> _showProgressDialog(
    BuildContext context,
    WidgetRef ref,
    AppDatabase db,
    Task task,
  ) async {
    var value = task.progress.toDouble();
    final note = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Catat progres'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${value.round()}%', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              Slider(
                value: value,
                max: 100,
                divisions: 20,
                label: '${value.round()}%',
                onChanged: (v) => setState(() => value = v),
              ),
              TextField(
                controller: note,
                maxLines: 3,
                minLines: 1,
                decoration: const InputDecoration(labelText: 'Apa yang sudah selesai?'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
            FilledButton(
              onPressed: () async {
                await db.updateProgress(task, value.round(), note: note.text.trim().isEmpty ? null : note.text.trim());
                ref.read(syncSchedulerProvider).schedule();
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showQuickRescheduleModal(
    BuildContext context,
    WidgetRef ref,
    AppDatabase db,
    Task task,
  ) async {
    final now = DateTime.now();

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '📅 Re-Schedule (Jadwal Ulang Kegiatan)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'Pilih tanggal tenggat baru untuk "${task.title}"',
                style: const TextStyle(fontSize: 11.5, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.wb_sunny_outlined, color: Color(0xFFD97706)),
                title: const Text('Besok Pagi (09:00 WIB)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                subtitle: const Text('Tunda ke esok hari pukul sembilan pagi'),
                onTap: () async {
                  final tomorrow9AM = DateTime(now.year, now.month, now.day + 1, 9, 0);
                  await _applyReschedule(ctx, ref, db, task, tomorrow9AM);
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.wb_twilight_outlined, color: Color(0xFF2563EB)),
                title: const Text('Besok Sore (16:00 WIB)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                subtitle: const Text('Tunda ke esok hari jam empat sore'),
                onTap: () async {
                  final tomorrow4PM = DateTime(now.year, now.month, now.day + 1, 16, 0);
                  await _applyReschedule(ctx, ref, db, task, tomorrow4PM);
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.date_range_outlined, color: Color(0xFF059669)),
                title: const Text('Lusa (+2 Hari)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                subtitle: const Text('Geser jadwal kegiatan dua hari ke depan'),
                onTap: () async {
                  final in2Days = DateTime(now.year, now.month, now.day + 2, task.dueAt?.hour ?? 9, task.dueAt?.minute ?? 0);
                  await _applyReschedule(ctx, ref, db, task, in2Days);
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.next_week_outlined, color: Color(0xFF7C3AED)),
                title: const Text('Minggu Depan (+7 Hari)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                subtitle: const Text('Tunda kegiatan hingga minggu depan'),
                onTap: () async {
                  final nextWeek = DateTime(now.year, now.month, now.day + 7, task.dueAt?.hour ?? 9, task.dueAt?.minute ?? 0);
                  await _applyReschedule(ctx, ref, db, task, nextWeek);
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.edit_calendar_rounded, color: Color(0xFFDC2626)),
                title: const Text('Pilih Tanggal & Jam Kustom...', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                subtitle: const Text('Tentukan tanggal & jam tenggat secara bebas'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await showTaskEditor(context, ref, existing: task);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _applyReschedule(
    BuildContext ctx,
    WidgetRef ref,
    AppDatabase db,
    Task task,
    DateTime newDueAt,
  ) async {
    await db.saveTask(
      TasksCompanion(
        id: Value(task.id),
        dueAt: Value(newDueAt),
      ),
    );
    ref.read(syncSchedulerProvider).schedule();

    try {
      final notifications = ref.read(notificationsProvider);
      await notifications.schedule(
        reminderId: 'task_due_${task.id}',
        title: '📌 Kegiatan: ${task.title}',
        body: 'Tenggat kegiatan ini dijadwalkan pada ${formatDate(newDueAt)} · ${formatTime(newDueAt)}.',
        triggerAt: newDueAt,
        payload: task.id,
      );
    } catch (_) {}

    if (ctx.mounted) {
      Navigator.pop(ctx);
      showAppSnack(ctx, 'Kegiatan berhasil di-Reschedule ke ${formatDate(newDueAt)} ${formatTime(newDueAt)}');
    }
  }

  Future<void> _showQuickReReminderModal(
    BuildContext context,
    WidgetRef ref,
    AppDatabase db,
    Task task,
  ) async {
    final dueAt = task.dueAt ?? DateTime.now().add(const Duration(hours: 1));

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '🔔 Re-Pengingat Notifikasi',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'Atur alarm notifikasi pengingat untuk "${task.title}"',
                style: const TextStyle(fontSize: 11.5, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.alarm_on_outlined, color: Color(0xFF059669)),
                title: const Text('Saat Tenggat Tiba (Tepat Waktu)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                subtitle: Text('Notifikasi berbunyi pada ${formatDate(dueAt)} · ${formatTime(dueAt)}'),
                onTap: () async {
                  await _applyReReminder(ctx, ref, db, task, dueAt, 'Tenggat Tiba');
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.timer_outlined, color: Color(0xFF2563EB)),
                title: const Text('15 Menit Sebelum Tenggat', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                subtitle: const Text('Pengingat 15 menit sebelum jam kegiatan'),
                onTap: () async {
                  await _applyReReminder(ctx, ref, db, task, dueAt.subtract(const Duration(minutes: 15)), '15 Menit Sebelum Tenggat');
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.history_toggle_off_outlined, color: Color(0xFF7C3AED)),
                title: const Text('1 Jam Sebelum Tenggat', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                subtitle: const Text('Pengingat 1 jam sebelum jam kegiatan'),
                onTap: () async {
                  await _applyReReminder(ctx, ref, db, task, dueAt.subtract(const Duration(hours: 1)), '1 Jam Sebelum Tenggat');
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.notification_add_outlined, color: Color(0xFFD97706)),
                title: const Text('1 Hari Sebelum Tenggat', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                subtitle: const Text('Pengingat H-1 hari sebelum jam kegiatan'),
                onTap: () async {
                  await _applyReReminder(ctx, ref, db, task, dueAt.subtract(const Duration(days: 1)), '1 Hari Sebelum Tenggat');
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.edit_notifications_outlined, color: Color(0xFFDC2626)),
                title: const Text('Atur Pengingat Kustom & Ulangi...', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                subtitle: const Text('Atur jadwal harian, mingguan, atau pesan kustom'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await showReminderEditor(context, ref, task: task);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _applyReReminder(
    BuildContext ctx,
    WidgetRef ref,
    AppDatabase db,
    Task task,
    DateTime triggerAt,
    String label,
  ) async {
    final ws = ref.read(currentWorkspaceProvider);
    if (ws == null) return;

    final reminder = await db.saveReminder(
      RemindersCompanion.insert(
        id: newId(),
        workspaceId: ws.id,
        entityType: const Value('TASK'),
        entityId: Value(task.id),
        title: '📌 Kegiatan: ${task.title}',
        message: Value('Pengingat ($label) untuk kegiatan "${task.title}"'),
        triggerAt: triggerAt,
        isActive: const Value(true),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        deviceId: '',
      ),
    );

    ref.read(syncSchedulerProvider).schedule();

    try {
      final notifications = ref.read(notificationsProvider);
      await notifications.ensurePermission();
      await notifications.schedule(
        reminderId: reminder.id,
        title: reminder.title,
        body: reminder.message,
        triggerAt: triggerAt,
        payload: task.id,
      );
    } catch (_) {}

    if (ctx.mounted) {
      Navigator.pop(ctx);
      showAppSnack(ctx, 'Re-Pengingat ($label) berhasil dipasang!');
    }
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}
