import 'package:collection/collection.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/dates.dart';
import '../../core/theme.dart';
import '../../data/local/database.dart';
import '../common/widgets.dart';

class TasksScreen extends ConsumerWidget {
  const TasksScreen({super.key});

  static const _filters = <String, String>{
    'ALL': 'Semua',
    'TODO': 'Belum mulai',
    'IN_PROGRESS': 'Dikerjakan',
    'DONE': 'Selesai',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tasks = ref.watch(tasksProvider).valueOrNull ?? const <Task>[];
    final filter = ref.watch(taskFilterProvider);
    final search = ref.watch(taskSearchProvider);

    final grouped = groupBy<Task, String>(
      tasks.where((t) => filter == 'ALL' || t.status == filter).toList(),
      (t) => t.status == 'DONE' ? 'Selesai' : (isOverdue(t.dueAt, status: t.status) ? 'Terlambat' : 'Aktif'),
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            onChanged: (v) => ref.read(taskSearchProvider.notifier).state = v,
            decoration: InputDecoration(
              hintText: 'Cari tugas…',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: search.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        ref.read(taskSearchProvider.notifier).state = '';
                        FocusScope.of(context).unfocus();
                      },
                    ),
            ),
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final entry in _filters.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    selected: filter == entry.key,
                    onSelected: (_) => ref.read(taskFilterProvider.notifier).state = entry.key,
                    label: Text(entry.value),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: tasks.isEmpty
              ? const EmptyState(
                  icon: Icons.task_alt,
                  title: 'Belum ada tugas',
                  message: 'Tambahkan kegiatan pertamamu lewat tombol + di bawah.',
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
                  children: [
                    for (final group in ['Terlambat', 'Aktif', 'Selesai'])
                      if (grouped[group]?.isNotEmpty == true) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
                          child: Row(
                            children: [
                              Text(
                                group,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.2),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${grouped[group]!.length}',
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                        ),
                        for (final task in grouped[group]!)
                          _TaskRow(task: task, onTap: () => context.push('/task/${task.id}')),
                      ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _TaskRow extends ConsumerWidget {
  const _TaskRow({required this.task, required this.onTap});

  final Task task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final overdue = isOverdue(task.dueAt, status: task.status);

    return Dismissible(
      key: ValueKey(task.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: kDanger.withValues(alpha: 0.15),
        child: const Icon(Icons.delete_outline, color: kDanger),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Hapus tugas?'),
                content: Text('"${task.title}" akan dihapus dari semua perangkat.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
                  FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Hapus')),
                ],
              ),
            ) ??
            false;
      },
      onDismissed: (_) {
        ref.read(databaseProvider).deleteTask(task.id);
        ref.read(syncSchedulerProvider).schedule();
        showAppSnack(context, 'Tugas dihapus');
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Card(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: () async {
                      final db = ref.read(databaseProvider);
                      if (task.status == 'DONE') {
                        await db.saveTask(
                          TasksCompanion(
                            id: Value(task.id),
                            status: const Value('IN_PROGRESS'),
                            completedAt: const Value(null),
                          ),
                        );
                      } else {
                        await db.updateProgress(task, 100);
                      }
                      ref.read(syncSchedulerProvider).schedule();
                    },
                    icon: Icon(
                      task.status == 'DONE' ? Icons.check_circle : Icons.radio_button_unchecked,
                      size: 20,
                      color: task.status == 'DONE' ? const Color(0xFF059669) : theme.colorScheme.outline,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            decoration: task.status == 'DONE' ? TextDecoration.lineThrough : null,
                            color: task.status == 'DONE' ? theme.colorScheme.onSurfaceVariant : null,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            if (task.dueAt != null) ...[
                              Icon(
                                Icons.schedule,
                                size: 12,
                                color: overdue ? kDanger : theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                overdue ? relativeDue(task.dueAt!) : formatDateShort(task.dueAt!),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: overdue ? kDanger : theme.colorScheme.onSurfaceVariant,
                                  fontWeight: overdue ? FontWeight.w600 : FontWeight.w400,
                                ),
                              ),
                              const SizedBox(width: 10),
                            ],
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: statusColor(task.status).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                statusLabel(task.status),
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w600,
                                  color: statusColor(task.status),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${task.progress}%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: task.progress == 100
                          ? const Color(0xFF059669)
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
