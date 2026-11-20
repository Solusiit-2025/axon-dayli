import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/dates.dart';
import '../../core/theme.dart';
import '../../data/local/database.dart';
import '../common/widgets.dart';

/// Membuka editor pengingat.
///
/// Jika [task] diisi, pengingat otomatis terhubung ke tugas tersebut dan
/// judulnya mengikuti judul tugas.
Future<void> showReminderEditor(
  BuildContext context,
  WidgetRef ref, {
  Reminder? existing,
  Task? task,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _ReminderEditorSheet(existing: existing, task: task),
  );
}

class _ReminderEditorSheet extends ConsumerStatefulWidget {
  const _ReminderEditorSheet({this.existing, this.task});

  final Reminder? existing;
  final Task? task;

  @override
  ConsumerState<_ReminderEditorSheet> createState() => _ReminderEditorSheetState();
}

class _ReminderEditorSheetState extends ConsumerState<_ReminderEditorSheet> {
  late final TextEditingController _title;
  late final TextEditingController _message;
  late DateTime _triggerAt;
  String? _recurrence;
  bool _saving = false;

  /// Mencegah simpan ganda saat sheet belum selesai ditutup.
  bool _saved = false;

  /// Diisi true saat pengguna menekan simpan tanpa judul.
  bool _titleTouched = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;

    _title = TextEditingController(
      text: existing?.title ??
          (widget.task != null ? 'Kerjakan: ${widget.task!.title}' : ''),
    );
    _message = TextEditingController(text: existing?.message ?? '');

    // Default: 30 menit sebelum tenggat, atau 1 jam dari sekarang.
    _triggerAt = existing?.triggerAt ??
        (widget.task?.dueAt?.subtract(const Duration(minutes: 30)) ??
            DateTime.now().add(const Duration(hours: 1)));

    _recurrence = existing?.recurrenceRule;
  }

  @override
  void dispose() {
    _title.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _triggerAt,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
      helpText: 'Tanggal pengingat',
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_triggerAt),
      helpText: 'Jam pengingat',
    );

    setState(() {
      _triggerAt = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? _triggerAt.hour,
        time?.minute ?? _triggerAt.minute,
      );
    });
  }

  Future<void> _save() async {
    if (_saving || _saved) return;

    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _titleTouched = true);
      showAppSnack(context, 'Judul pengingat wajib diisi', error: true);
      return;
    }

    final ws = ref.read(currentWorkspaceProvider);
    if (ws == null) return;

    setState(() => _saving = true);
    final db = ref.read(databaseProvider);
    final notifications = ref.read(notificationsProvider);

    late final Reminder saved;
    try {
      if (widget.existing == null) {
        saved = await db.saveReminder(RemindersCompanion.insert(
          id: newId(),
          workspaceId: ws.id,
          entityType: Value(widget.task == null ? 'CUSTOM' : 'TASK'),
          entityId: Value(widget.task?.id),
          title: title,
          message: Value(_message.text.trim().isEmpty ? null : _message.text.trim()),
          triggerAt: _triggerAt,
          recurrenceRule: Value(_recurrence),
          isActive: const Value(true),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          deviceId: '',
        ));
      } else {
        saved = await db.saveReminder(RemindersCompanion(
          id: Value(widget.existing!.id),
          workspaceId: Value(widget.existing!.workspaceId),
          title: Value(title),
          message: Value(_message.text.trim().isEmpty ? null : _message.text.trim()),
          triggerAt: Value(_triggerAt),
          recurrenceRule: Value(_recurrence),
          isActive: const Value(true),
          snoozeUntil: const Value(null),
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showAppSnack(context, 'Gagal menyimpan pengingat: $e', error: true);
      }
      return;
    }

    ref.read(syncSchedulerProvider).schedule();

    // Tutup form segera setelah data tersimpan — jadwal notifikasi bersifat
    // best-effort dan tidak boleh menahan penutupan form.
    final willFire = !saved.triggerAt.isBefore(DateTime.now()) ||
        (saved.recurrenceRule != null && saved.recurrenceRule!.isNotEmpty);
    // Jadwalkan notifikasi
    try {
      await notifications.cancel(saved.id);
      await notifications.ensurePermission();
      await notifications.schedule(
        reminderId: saved.id,
        title: saved.title,
        body: saved.message,
        triggerAt: saved.triggerAt,
        recurrenceRule: saved.recurrenceRule,
        payload: saved.entityId,
      );
    } catch (e) {
      debugPrint('Gagal menjadwalkan pengingat: $e');
    }

    if (mounted) {
      _saved = true;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      if (willFire) {
        showAppSnack(context, 'Pengingat & Notifikasi berhasil dijadwalkan!');
      } else {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Waktu sudah lewat — pengingat disimpan tapi tidak akan berbunyi.'),
            backgroundColor: Color(0xFFB45309),
          ),
        );
      }
    }

    if (mounted && !_saved) setState(() => _saving = false);
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus pengingat?'),
        content: const Text('Notifikasi untuk pengingat ini akan dibatalkan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Hapus')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    await ref.read(databaseProvider).deleteReminder(existing.id);
    await ref.read(notificationsProvider).cancel(existing.id);
    ref.read(syncSchedulerProvider).schedule();

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final isPast = _triggerAt.isBefore(DateTime.now()) &&
        (_recurrence == null || _recurrence!.isEmpty);

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.existing == null ? 'Pengingat baru' : 'Ubah pengingat',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.3),
            ),
            const SizedBox(height: 4),
            Text(
              widget.task != null
                  ? 'Terhubung ke tugas "${widget.task!.title}".'
                  : 'Berlaku untuk ruang kerja aktif.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _title,
              autofocus: widget.existing == null,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Judul pengingat',
                errorText: _title.text.trim().isEmpty && _titleTouched ? 'Judul wajib diisi' : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _message,
              maxLines: 2,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Pesan (opsional)'),
            ),

            const SizedBox(height: 18),
            Text(
              'Kapan',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _pickDateTime,
              icon: const Icon(Icons.notifications_active_outlined, size: 18),
              label: Text('${formatDate(_triggerAt)} · ${formatTime(_triggerAt)}'),
            ),
            if (isPast) ...[
              const SizedBox(height: 6),
              Text(
                'Waktu ini sudah lewat. Pilih waktu lain atau aktifkan pengulangan.',
                style: TextStyle(fontSize: 11.5, color: kDanger),
              ),
            ],

            const SizedBox(height: 18),
            Text(
              'Ulangi',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  selected: _recurrence == null,
                  onSelected: (_) => setState(() => _recurrence = null),
                  label: const Text('Sekali'),
                ),
                ChoiceChip(
                  selected: _recurrence == 'DAILY',
                  onSelected: (_) => setState(() => _recurrence = 'DAILY'),
                  label: const Text('Harian'),
                ),
                ChoiceChip(
                  selected: _recurrence == 'WEEKLY',
                  onSelected: (_) => setState(() => _recurrence = 'WEEKLY'),
                  label: const Text('Mingguan'),
                ),
              ],
            ),

            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.alarm_on, size: 18),
              label: Text(widget.existing == null ? 'Aktifkan pengingat' : 'Simpan perubahan'),
            ),
            if (widget.existing != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _saving ? null : _delete,
                icon: const Icon(Icons.delete_outline, size: 18, color: kDanger),
                label: const Text('Hapus pengingat', style: TextStyle(color: kDanger)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
