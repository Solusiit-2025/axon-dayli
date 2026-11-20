import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/dates.dart';
import '../../core/theme.dart';
import '../../data/local/database.dart';
import '../common/widgets.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    _selected = startOfDay(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final month = ref.watch(calendarMonthProvider);
    final events = ref.watch(eventsProvider).valueOrNull ?? const <CalendarEvent>[];
    final tasks = ref.watch(tasksProvider).valueOrNull ?? const <Task>[];

    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final firstWeekday = DateTime(month.year, month.month, 1).weekday; // 1 = Senin

    final dayEvents = events.where((e) => isSameDay(e.startAt, _selected)).toList();
    final dayTasks = tasks
        .where((t) => t.dueAt != null && isSameDay(t.dueAt!, _selected))
        .toList();

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Kalender'),
        actions: [
          IconButton(
            onPressed: () => _addEvent(context, ref, _selected),
            icon: const Icon(Icons.add),
            tooltip: 'Tambah agenda',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => ref.read(calendarMonthProvider.notifier).state =
                    DateTime(month.year, month.month - 1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  formatMonthYear(month),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                onPressed: () => ref.read(calendarMonthProvider.notifier).state =
                    DateTime(month.year, month.month + 1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              for (final label in ['S', 'S', 'R', 'K', 'J', 'S', 'M'])
                Expanded(
                  child: Center(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1,
            ),
            itemCount: ((firstWeekday - 1) + daysInMonth),
            itemBuilder: (context, index) {
              final offset = firstWeekday - 1;
              if (index < offset) return const SizedBox.shrink();

              final day = index - offset + 1;
              final date = DateTime(month.year, month.month, day);
              final isSelected = isSameDay(date, _selected);
              final isToday = isSameDay(date, DateTime.now());

              final hasEvent = events.any((e) => isSameDay(e.startAt, date));
              final hasTask = tasks.any((t) => t.dueAt != null && isSameDay(t.dueAt!, date));
              final overdueTask =
                  tasks.any((t) => t.dueAt != null && isSameDay(t.dueAt!, date) && isOverdue(t.dueAt, status: t.status));

              return InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(() => _selected = date),
                child: Container(
                  margin: const EdgeInsets.all(1),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? theme.colorScheme.primary.withValues(alpha: 0.14)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: isToday && !isSelected
                        ? Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.35))
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$day',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                          color: isSelected ? theme.colorScheme.primary : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (hasEvent)
                            Container(
                              width: 4,
                              height: 4,
                              margin: const EdgeInsets.symmetric(horizontal: 1),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          if (hasTask)
                            Container(
                              width: 4,
                              height: 4,
                              margin: const EdgeInsets.symmetric(horizontal: 1),
                              decoration: BoxDecoration(
                                color: overdueTask ? kDanger : const Color(0xFFF59E0B),
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          Text(
            formatDateFull(_selected),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),

          if (dayEvents.isEmpty && dayTasks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Tidak ada agenda di tanggal ini.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),

          for (final e in dayEvents)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                dense: true,
                onTap: () => _addEvent(context, ref, _selected, existing: e),
                leading: Container(
                  width: 3,
                  height: 34,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                title: Text(e.title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                subtitle: Text(
                  '${formatTime(e.startAt)} – ${formatTime(e.endAt)}'
                  '${e.location?.isNotEmpty == true ? ' · ${e.location}' : ''}',
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: const Icon(Icons.edit_outlined, size: 16),
              ),
            ),

          for (final t in dayTasks)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                dense: true,
                leading: Icon(
                  Icons.check_circle_outline,
                  size: 18,
                  color: isOverdue(t.dueAt, status: t.status) ? kDanger : const Color(0xFFF59E0B),
                ),
                title: Text(t.title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                subtitle: Text(
                  '${t.dueAt == null ? '' : formatTime(t.dueAt!)} · ${statusLabel(t.status)}',
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => context.push('/task/${t.id}'),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _addEvent(BuildContext context, WidgetRef ref, DateTime date, {CalendarEvent? existing}) async {
    final title = TextEditingController(text: existing?.title ?? '');
    final location = TextEditingController(text: existing?.location ?? '');
    var start = existing?.startAt ?? DateTime(date.year, date.month, date.day, 9);
    var end = existing?.endAt ?? DateTime(date.year, date.month, date.day, 10);

    final workspace = ref.read(currentWorkspaceProvider);
    if (workspace == null) return;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(existing == null ? 'Agenda baru' : 'Edit Agenda'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Judul Agenda'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: location,
                  decoration: const InputDecoration(labelText: 'Lokasi (opsional)'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.fromDateTime(start),
                          );
                          if (picked != null) {
                            setState(() {
                              start = DateTime(date.year, date.month, date.day, picked.hour, picked.minute);
                              end = start.add(const Duration(hours: 1));
                            });
                          }
                        },
                        child: Text('Mulai ${formatTime(start)}'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.fromDateTime(end),
                          );
                          if (picked != null) {
                            setState(() {
                              end = DateTime(date.year, date.month, date.day, picked.hour, picked.minute);
                            });
                          }
                        },
                        child: Text('Selesai ${formatTime(end)}'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            if (existing != null)
              TextButton(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Hapus Agenda?'),
                      content: Text('Apakah Anda yakin ingin menghapus agenda "${existing.title}"?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: kDanger),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Hapus Agenda'),
                        ),
                      ],
                    ),
                  );

                  if (confirm == true) {
                    await ref.read(databaseProvider).deleteEvent(existing.id);
                    ref.read(syncSchedulerProvider).schedule();
                    if (context.mounted) {
                      Navigator.pop(context);
                      showAppSnack(context, 'Agenda "${existing.title}" berhasil dihapus');
                    }
                  }
                },
                child: const Text('Hapus', style: TextStyle(color: kDanger)),
              ),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
            FilledButton(
              onPressed: () async {
                if (title.text.trim().isEmpty) return;
                final db = ref.read(databaseProvider);
                if (existing == null) {
                  await db.saveEvent(CalendarEventsCompanion.insert(
                    id: newId(),
                    workspaceId: workspace.id,
                    title: title.text.trim(),
                    location: Value(location.text.trim().isEmpty ? null : location.text.trim()),
                    startAt: start,
                    endAt: end,
                    createdAt: DateTime.now(),
                    updatedAt: DateTime.now(),
                    deviceId: '',
                  ));
                } else {
                  await db.saveEvent(CalendarEventsCompanion(
                    id: Value(existing.id),
                    workspaceId: Value(workspace.id),
                    title: Value(title.text.trim()),
                    location: Value(location.text.trim().isEmpty ? null : location.text.trim()),
                    startAt: Value(start),
                    endAt: Value(end),
                  ));
                }
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
}
