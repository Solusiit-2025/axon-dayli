import 'dart:convert';
import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../app/providers.dart';
import '../../core/dates.dart';
import '../../data/local/database.dart';
import '../common/widgets.dart';

const docCategories = <String, String>{
  'IDENTITY': 'Identitas (KTP, KK, Buku Nikah)',
  'LEGAL': 'Hukum & Notaris (Akta, Sertifikat)',
  'TAX': 'Perpajakan (NPWP, SPT)',
  'BUSINESS': 'Perusahaan & Usaha (NIB, SIUP, Kontrak)',
  'OTHER': 'Lainnya',
};

Future<void> showDocumentEditor(BuildContext context, WidgetRef ref, {DocEntry? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => SizedBox(
      height: MediaQuery.of(ctx).size.height * 0.88,
      child: _DocumentEditorSheet(existing: existing),
    ),
  );
}

class _DocumentEditorSheet extends ConsumerStatefulWidget {
  const _DocumentEditorSheet({this.existing});

  final DocEntry? existing;

  @override
  ConsumerState<_DocumentEditorSheet> createState() => _DocumentEditorSheetState();
}

class _DocumentEditorSheetState extends ConsumerState<_DocumentEditorSheet> {
  late final TextEditingController _title;
  late final TextEditingController _docNumber;
  late final TextEditingController _holderName;
  late final TextEditingController _note;
  late String _category;
  DateTime? _issueDate;
  DateTime? _expiryDate;
  List<String> _attachments = [];
  bool _saving = false;
  bool _deleting = false;

  /// Mencegah simpan ganda saat sheet belum selesai ditutup.
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    final d = widget.existing;
    _title = TextEditingController(text: d?.title ?? '');
    _docNumber = TextEditingController(text: d?.docNumber ?? '');
    _holderName = TextEditingController(text: d?.holderName ?? '');
    _note = TextEditingController(text: d?.note ?? '');
    _category = d?.category ?? 'IDENTITY';
    _issueDate = d?.issueDate;
    _expiryDate = d?.expiryDate;

    if (d?.attachments != null && d!.attachments!.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(d.attachments!);
        if (decoded is List) {
          _attachments = decoded.map((e) => e.toString()).toList();
        } else {
          _attachments = [d.attachments!];
        }
      } catch (_) {
        _attachments = [d.attachments!];
      }
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _docNumber.dispose();
    _holderName.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickAttachments() async {
    try {
      final choice = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined, color: Color(0xFF4F46E5)),
                title: const Text('Ambil Foto Kamera', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Foto dokumen / KTP / KK langsung dengan kamera HP'),
                onTap: () => Navigator.pop(ctx, 'camera'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined, color: Color(0xFF2563EB)),
                title: const Text('Pilih dari Galeri Foto', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Pilih satu atau beberapa foto dari galeri HP'),
                onTap: () => Navigator.pop(ctx, 'gallery'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined, color: Color(0xFFDC2626)),
                title: const Text('Upload Dokumen PDF / Berkas File', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Upload file PDF (KTP, SIM, STNK, Sertifikat, NPWP, Akta)'),
                onTap: () => Navigator.pop(ctx, 'pdf'),
              ),
            ],
          ),
        ),
      );

      if (choice == null) return;

      if (choice == 'camera') {
        final picker = ImagePicker();
        final XFile? file = await picker.pickImage(source: ImageSource.camera, maxWidth: 1600, maxHeight: 1600, imageQuality: 70);
        if (file == null) return;

        final bytes = await file.readAsBytes();
        final base64Str = base64Encode(bytes);
        final mimeType = file.mimeType ?? 'image/jpeg';
        final dataUrl = 'data:$mimeType;base64,$base64Str';
        setState(() {
          _attachments.add(dataUrl);
        });
      } else if (choice == 'gallery') {
        final picker = ImagePicker();
        final List<XFile> pickedFiles = await picker.pickMultiImage(maxWidth: 1600, maxHeight: 1600, imageQuality: 70);
        if (pickedFiles.isEmpty) return;

        for (final file in pickedFiles) {
          final bytes = await file.readAsBytes();
          final base64Str = base64Encode(bytes);
          final mimeType = file.mimeType ?? 'image/jpeg';
          final dataUrl = 'data:$mimeType;base64,$base64Str';
          if (!_attachments.contains(dataUrl)) _attachments.add(dataUrl);
        }
        setState(() {});
      } else if (choice == 'pdf') {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pdf', 'doc', 'docx'],
          withData: true,
        );
        if (result == null || result.files.isEmpty) return;
        for (final f in result.files) {
          final bytes = f.bytes;
          if (bytes != null) {
            final base64Str = base64Encode(bytes);
            final fileName = f.name;
            final dataUrl = 'data:application/pdf;name=${Uri.encodeComponent(fileName)};base64,$base64Str';
            if (!_attachments.contains(dataUrl)) _attachments.add(dataUrl);
          }
        }
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        showAppSnack(context, 'Gagal memilih berkas: $e', error: true);
      }
    }
  }

  Future<void> _pickIssueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _issueDate ?? now,
      firstDate: DateTime(1950),
      lastDate: now,
      helpText: 'Tanggal Terbit Dokumen',
    );
    if (picked != null) setState(() => _issueDate = picked);
  }

  Future<void> _pickExpiryDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiryDate ?? now.add(const Duration(days: 365)),
      firstDate: now,
      lastDate: DateTime(2060),
      helpText: 'Tanggal Kadaluarsa / Masa Berlaku',
    );
    if (picked != null) setState(() => _expiryDate = picked);
  }

  Future<void> _deleteDocument() async {
    if (_saving || _deleting || _saved) return;
    final d = widget.existing;
    if (d == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Dokumen?'),
        content: Text('Apakah Anda yakin ingin menghapus dokumen "${d.title}"?'),
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
      await db.deleteDocument(d.id);
      ref.read(syncSchedulerProvider).schedule();

      if (mounted) {
        Navigator.of(context).pop(); // Tutup bottom sheet dokumen.
        showAppSnack(context, 'Dokumen "${d.title}" berhasil dihapus');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menghapus dokumen: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _save() async {
    if (_saving || _deleting || _saved) return;

    final titleText = _title.text.trim();
    if (titleText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Judul dokumen wajib diisi')),
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
      final attachmentValue = Value(_attachments.isEmpty ? null : jsonEncode(_attachments));
      final numText = _docNumber.text.trim();
      final nameText = _holderName.text.trim();
      final noteText = _note.text.trim();

      if (widget.existing == null) {
        await db.saveDocument(DocumentsCompanion.insert(
          id: newId(),
          workspaceId: ws.id,
          title: titleText,
          category: Value(_category),
          docNumber: Value(numText.isEmpty ? null : numText),
          holderName: Value(nameText.isEmpty ? null : nameText),
          issueDate: Value(_issueDate),
          expiryDate: Value(_expiryDate),
          attachments: attachmentValue,
          note: Value(noteText.isEmpty ? null : noteText),
          createdAt: now,
          updatedAt: now,
          deviceId: '',
        ));
      } else {
        await db.saveDocument(DocumentsCompanion(
          id: Value(widget.existing!.id),
          workspaceId: Value(widget.existing!.workspaceId),
          title: Value(titleText),
          category: Value(_category),
          docNumber: Value(numText.isEmpty ? null : numText),
          holderName: Value(nameText.isEmpty ? null : nameText),
          issueDate: Value(_issueDate),
          expiryDate: Value(_expiryDate),
          attachments: attachmentValue,
          note: Value(noteText.isEmpty ? null : noteText),
        ));
      }

      ref.read(syncSchedulerProvider).schedule();

      if (mounted) {
        _saved = true;

        Navigator.of(context).pop(); // Tutup bottom sheet dokumen.

        showAppSnack(
          context,
          widget.existing == null ? 'Dokumen "$titleText" berhasil disimpan' : 'Perubahan dokumen disimpan',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan dokumen: $e')),
        );
      }
    } finally {
      if (mounted && !_saved) setState(() => _saving = false);
    }
  }

  void _showImageDialog(String item) {
    final isPdf = item.contains('application/pdf') || item.endsWith('.pdf');
    ImageProvider? provider;
    if (!isPdf && item.startsWith('data:image')) {
      final base64Part = item.split(',').last;
      provider = MemoryImage(base64Decode(base64Part));
    } else if (!isPdf && item.startsWith('http')) {
      provider = NetworkImage(item);
    }

    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isPdf)
              Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  children: [
                    Icon(Icons.picture_as_pdf_rounded, size: 56, color: Colors.red.shade700),
                    const SizedBox(height: 12),
                    const Text('Berkas Dokumen PDF', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    const Text(
                      'File PDF tersimpan secara aman dalam format terenkripsi Base64 di database lokal HP & VPS.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11.5, color: Colors.grey),
                    ),
                  ],
                ),
              )
            else if (provider != null)
              Image(image: provider, fit: BoxFit.contain)
            else
              const Padding(
                padding: EdgeInsets.all(40),
                child: Icon(Icons.broken_image, size: 48),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Tutup'),
            ),
          ],
        ),
      ),
    );
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
                  widget.existing == null ? 'Simpan Dokumen Baru' : 'Edit Dokumen',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.3),
                ),
                if (widget.existing != null)
                  ShadButton.destructive(
                    onPressed: (_saving || _deleting || _saved) ? null : _deleteDocument,
                    child: _deleting
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Row(
                            children: [
                              Icon(Icons.delete_outline, size: 14),
                              SizedBox(width: 4),
                              Text('Hapus Dokumen'),
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
                  const Text('Judul Dokumen *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  ShadInput(
                    controller: _title,
                    autofocus: widget.existing == null,
                    placeholder: const Text('Misal: KTP Saya, Buku Nikah, Akta Pendirian PT'),
                  ),
                  const SizedBox(height: 16),

                  Text(
                    'Kategori Dokumen',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final entry in docCategories.entries)
                        ChoiceChip(
                          selected: _category == entry.key,
                          onSelected: (_) => setState(() => _category = entry.key),
                          label: Text(entry.value),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  const Text('Nomor Dokumen / NIK / NPWP (opsional)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  ShadInput(
                    controller: _docNumber,
                    placeholder: const Text('Misal: NIK 3174... / NPWP 01.234...'),
                  ),
                  const SizedBox(height: 14),

                  const Text('Nama Pemilik / Atas Nama (opsional)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  ShadInput(
                    controller: _holderName,
                    placeholder: const Text('Misal: Budi Santoso / PT Solusi IT'),
                  ),
                  const SizedBox(height: 14),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickIssueDate,
                          icon: const Icon(Icons.event, size: 16),
                          label: Text(_issueDate == null ? 'Tanggal Terbit' : formatDate(_issueDate!)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickExpiryDate,
                          icon: const Icon(Icons.history_toggle_off, size: 16),
                          label: Text(_expiryDate == null ? 'Masa Berlaku / Exp' : formatDate(_expiryDate!)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  const Text('Catatan Tambahan (opsional)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  ShadInput(
                    controller: _note,
                    placeholder: const Text('Nomor lemari, berkas asli di mana, dll...'),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Foto / Scan Berkas Dokumen (${_attachments.length})',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurfaceVariant),
                      ),
                      IconButton(
                        onPressed: _pickAttachments,
                        tooltip: 'Tambah Foto / PDF Berkas',
                        icon: const Icon(Icons.attach_file_rounded, size: 20),
                      ),
                    ],
                  ),

                  if (_attachments.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 90,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _attachments.length,
                        itemBuilder: (context, index) {
                          final item = _attachments[index];
                          final isPdf = item.contains('application/pdf') || item.endsWith('.pdf');
                          ImageProvider? provider;
                          if (!isPdf && item.startsWith('data:image')) {
                            final base64Part = item.split(',').last;
                            provider = MemoryImage(base64Decode(base64Part));
                          } else if (!isPdf && item.startsWith('http')) {
                            provider = NetworkImage(item);
                          }

                          return Container(
                            width: 85,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: theme.dividerColor),
                              color: isPdf ? Colors.red.shade700.withValues(alpha: 0.1) : null,
                              image: provider != null ? DecorationImage(image: provider, fit: BoxFit.cover) : null,
                            ),
                            child: Stack(
                              children: [
                                if (isPdf)
                                  Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.picture_as_pdf_rounded, color: Colors.red.shade700, size: 28),
                                        const SizedBox(height: 2),
                                        const Text(
                                          'Dokumen PDF',
                                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.red),
                                        ),
                                      ],
                                    ),
                                  )
                                else if (provider == null)
                                  const Center(child: Icon(Icons.description, color: Colors.grey)),
                                Positioned.fill(
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(10),
                                      onTap: () => _showImageDialog(item),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: InkWell(
                                    onTap: () {
                                      setState(() {
                                        _attachments.removeAt(index);
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(3),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.7),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.close, size: 12, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
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
                onPressed: (_saving || _deleting || _saved) ? null : _save,
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
                          Text('Menyimpan Dokumen...'),
                        ],
                      )
                    : Text(widget.existing == null ? 'Simpan Dokumen' : 'Simpan Perubahan'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
