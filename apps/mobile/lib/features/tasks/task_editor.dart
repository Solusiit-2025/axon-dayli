import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../app/providers.dart';
import '../../core/dates.dart';
import '../../core/theme.dart';
import '../../data/local/database.dart';

Future<void> showTaskEditor(BuildContext context, WidgetRef ref, {Task? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => SizedBox(
      height: MediaQuery.of(ctx).size.height * 0.88,
      child: _TaskEditorSheet(existing: existing),
    ),
  );
}

class _TaskEditorSheet extends ConsumerStatefulWidget {
  const _TaskEditorSheet({this.existing});

  final Task? existing;

  @override
  ConsumerState<_TaskEditorSheet> createState() => _TaskEditorSheetState();
}

class _TaskEditorSheetState extends ConsumerState<_TaskEditorSheet> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _estimate;

  DateTime? _dueAt;
  int _priority = 2;
  String _status = 'TODO';
  String? _recurrenceRule;
  bool _saving = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    final t = widget.existing;
    _title = TextEditingController(text: t?.title ?? '');
    _description = TextEditingController(text: t?.description ?? '');
    _estimate = TextEditingController(text: t?.estimatedMinutes?.toString() ?? '');
    _dueAt = t?.dueAt;
    _priority = t?.priority ?? 2;
    _status = t?.status ?? 'TODO';
    _recurrenceRule = t?.recurrenceRule;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _estimate.dispose();
    super.dispose();
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year - 1);
    final lastDate = DateTime(now.year + 5);
    var initial = _dueAt ?? now;
    if (initial.isBefore(firstDate)) initial = firstDate;
    if (initial.isAfter(lastDate)) initial = lastDate;

    DateTime? date;
    try {
      date = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: firstDate,
        lastDate: lastDate,
        helpText: 'Pilih Tenggat Tugas',
        useRootNavigator: true,
      );
    } catch (e) {
      debugPrint('showDatePicker gagal: $e');
      return;
    }
    if (date == null || !mounted) return;

    final initialTime = TimeOfDay.fromDateTime(_dueAt ?? DateTime(now.year, now.month, now.day, 9));
    TimeOfDay? time;
    try {
      time = await showTimePicker(
        context: context,
        initialTime: initialTime,
        helpText: 'Pilih Jam Tenggat',
        useRootNavigator: true,
      );
    } catch (e) {
      debugPrint('showTimePicker gagal: $e');
    }

    if (!mounted) return;
    setState(() {
      _dueAt = DateTime(date!.year, date.month, date.day, time?.hour ?? 9, time?.minute ?? 0);
    });
  }

  Future<void> _deleteTask() async {
    if (_saving || _deleting) return;
    final t = widget.existing;
    if (t == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Tugas?'),
        content: Text('Apakah Anda yakin ingin menghapus tugas "${t.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _deleting = true);

    try {
      final db = ref.read(databaseProvider);
      await db.deleteTask(t.id);
      ref.read(syncSchedulerProvider).schedule();

      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context, rootNavigator: true).pop(); // TUTUP MODAL INSTAN!
        messenger.showSnackBar(
          SnackBar(
            content: Text('Tugas "${t.title}" berhasil dihapus'),
            backgroundColor: Colors.orange.shade800,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menghapus tugas: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _save() async {
    if (_saving || _deleting) return;
    final titleText = _title.text.trim();
    if (titleText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Judul tugas wajib diisi')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final db = ref.read(databaseProvider);
      var ws = ref.read(currentWorkspaceProvider);

      if (ws == null) {
        final list = await db.listWorkspaces();
        if (list.isNotEmpty) {
          ws = list.first;
        } else {
          final defaultWsId = newId();
          await db.upsertWorkspaceFromServer({
            'id': defaultWsId,
            'type': 'PERSONAL',
            'name': 'Pribadi',
            'color': '#10B981',
            'icon': 'person',
          });
          await db.ensureWorkspaceDefaults(defaultWsId, 'PERSONAL');
          ws = (await db.listWorkspaces()).first;
        }
      }

      final now = DateTime.now();
      final estimate = int.tryParse(_estimate.text.trim());
      final descText = _description.text.trim();

      if (widget.existing == null) {
        await db.saveTask(TasksCompanion.insert(
          id: newId(),
          workspaceId: ws.id,
          title: titleText,
          description: Value(descText.isEmpty ? null : descText),
          dueAt: Value(_dueAt),
          priority: Value(_priority),
          status: Value(_status),
          estimatedMinutes: Value(estimate),
          recurrenceRule: Value(_recurrenceRule),
          createdAt: now,
          updatedAt: now,
          deviceId: '',
        ));
      } else {
        await db.saveTask(TasksCompanion(
          id: Value(widget.existing!.id),
          workspaceId: Value(widget.existing!.workspaceId),
          title: Value(titleText),
          description: Value(descText.isEmpty ? null : descText),
          dueAt: Value(_dueAt),
          priority: Value(_priority),
          status: Value(_status),
          estimatedMinutes: Value(estimate),
          recurrenceRule: Value(_recurrenceRule),
          completedAt: Value(_status == 'DONE' ? (widget.existing!.completedAt ?? now) : null),
        ));
      }

      ref.read(syncSchedulerProvider).schedule();

      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context, rootNavigator: true).pop(); // TUTUP MODAL BOTTOM SHEET INSTAN!

        messenger.showSnackBar(
          SnackBar(
            content: Text(widget.existing == null ? 'Tugas berhasil ditambahkan!' : 'Perubahan tugas disimpan!'),
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan tugas: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Column(
        children: [
          // Header Sticky Modal Sheet
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.existing == null ? 'Tambah Tugas Baru' : 'Edit Tugas',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.4),
                ),
                if (widget.existing != null)
                  ShadButton.destructive(
                    onPressed: (_saving || _deleting) ? null : _deleteTask,
                    child: _deleting
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Row(
                            children: [
                              Icon(Icons.delete_outline, size: 14),
                              SizedBox(width: 4),
                              Text('Hapus Tugas'),
                            ],
                          ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Scrollable Form Fields
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Apa yang mau dikerjakan? *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  ShadInput(
                    controller: _title,
                    autofocus: widget.existing == null,
                    placeholder: const Text('Judul kegiatan atau tugas...'),
                  ),
                  const SizedBox(height: 14),

                  const Text('Catatan Tambahan (opsional)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  ShadInput(
                    controller: _description,
                    placeholder: const Text('Detail atau petunjuk tugas...'),
                  ),
                  const SizedBox(height: 16),

                  Text('Tenggat / Waktu', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickDue,
                          icon: const Icon(Icons.event_outlined, size: 16),
                          label: Text(
                            _dueAt == null ? 'Set Tanggal & Jam' : '${formatDate(_dueAt!)} · ${formatTime(_dueAt!)}',
                          ),
                        ),
                      ),
                      if (_dueAt != null)
                        IconButton(
                          onPressed: () => setState(() => _dueAt = null),
                          icon: const Icon(Icons.close, size: 18),
                          tooltip: 'Hapus tenggat',
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  Text('Prioritas', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (var p = 1; p <= 4; p++)
                        ChoiceChip(
                          selected: _priority == p,
                          onSelected: (_) => setState(() => _priority = p),
                          avatar: CircleAvatar(radius: 4, backgroundColor: priorityColor(p)),
                          label: Text(priorityLabel(p)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  Text('Pengulangan Otomatis (Recurring Task)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        selected: _recurrenceRule == null,
                        onSelected: (_) => setState(() => _recurrenceRule = null),
                        label: const Text('Sekali Jalan'),
                      ),
                      ChoiceChip(
                        selected: _recurrenceRule == 'DAILY',
                        onSelected: (_) => setState(() => _recurrenceRule = 'DAILY'),
                        label: const Text('Harian'),
                      ),
                      ChoiceChip(
                        selected: _recurrenceRule == 'WEEKLY',
                        onSelected: (_) => setState(() => _recurrenceRule = 'WEEKLY'),
                        label: const Text('Mingguan'),
                      ),
                      ChoiceChip(
                        selected: _recurrenceRule == 'MONTHLY',
                        onSelected: (_) => setState(() => _recurrenceRule = 'MONTHLY'),
                        label: const Text('Bulanan'),
                      ),
                    ],
                  ),

                  if (widget.existing != null) ...[
                    const SizedBox(height: 16),
                    Text('Status Kegiatan', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final s in ['TODO', 'IN_PROGRESS', 'BLOCKED', 'DONE'])
                          ChoiceChip(
                            selected: _status == s,
                            onSelected: (_) => setState(() => _status = s),
                            label: Text(statusLabel(s)),
                          ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 16),
                  const Text('Estimasi Durasi (menit)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  ShadInput(
                    controller: _estimate,
                    keyboardType: TextInputType.number,
                    placeholder: const Text('Contoh: 30'),
                  ),
                ],
              ),
            ),
          ),

          // Sticky Footer Action Bar
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(top: BorderSide(color: theme.dividerColor)),
            ),
            child: SafeArea(
              top: false,
              child: ShadButton(
                onPressed: (_saving || _deleting) ? null : _save,
                child: _saving
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          ),
                          SizedBox(width: 8),
                          Text('Menyimpan Tugas...'),
                        ],
                      )
                    : Text(widget.existing == null ? 'Simpan Tugas' : 'Simpan Perubahan'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
