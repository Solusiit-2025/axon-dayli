import 'dart:convert';
import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/providers.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/local/database.dart';
import '../common/widgets.dart';

const assetCategories = <String, String>{
  'vehicle': 'Kendaraan',
  'property': 'Properti',
  'electronics': 'Elektronik',
  'investment': 'Investasi',
  'equipment': 'Peralatan',
  'other': 'Lainnya',
};

Future<void> showAssetEditor(BuildContext context, WidgetRef ref, {Asset? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => SizedBox(
      height: MediaQuery.of(ctx).size.height * 0.88,
      child: _AssetEditorSheet(existing: existing),
    ),
  );
}

class _AssetEditorSheet extends ConsumerStatefulWidget {
  const _AssetEditorSheet({this.existing});

  final Asset? existing;

  @override
  ConsumerState<_AssetEditorSheet> createState() => _AssetEditorSheetState();
}

class _AssetEditorSheetState extends ConsumerState<_AssetEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _price;
  late final TextEditingController _value;
  late final TextEditingController _salvageValue;
  late final TextEditingController _usefulLifeYears;
  late final TextEditingController _note;
  late String _category;
  late String _status;
  late String _depreciationMethod;
  String? _debtId;
  DateTime? _purchaseAt;
  List<String> _attachments = [];
  bool _saving = false;
  bool _deleting = false;

  /// Menandai data sudah tersimpan. Dipakai agar tombol tidak bisa ditekan
  /// dua kali (mencegah input ganda) selama sheet belum selesai ditutup.
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    final a = widget.existing;
    _name = TextEditingController(text: a?.name ?? '');
    _price = TextEditingController(text: a?.purchasePrice == null ? '' : formatNumber(a!.purchasePrice!));
    _value = TextEditingController(text: a == null ? '' : formatNumber(a.currentValue));
    _salvageValue = TextEditingController(text: a?.salvageValue == null ? '' : formatNumber(a!.salvageValue!));
    _category = a?.category ?? 'electronics';
    _status = a?.status ?? 'ACTIVE';

    if (a == null) {
      if (_category == 'property' || _category == 'investment') {
        _depreciationMethod = 'APPRECIATION';
        _usefulLifeYears = TextEditingController(text: '20');
      } else if (_category == 'vehicle') {
        _depreciationMethod = 'STRAIGHT_LINE';
        _usefulLifeYears = TextEditingController(text: '8');
      } else {
        _depreciationMethod = 'STRAIGHT_LINE';
        _usefulLifeYears = TextEditingController(text: '4');
      }
    } else {
      _depreciationMethod = a.depreciationMethod;
      _usefulLifeYears = TextEditingController(text: a.usefulLifeMonths == null ? '5' : (a.usefulLifeMonths! / 12).round().toString());
    }

    _note = TextEditingController(text: a?.note ?? '');
    _debtId = a?.debtId;
    _purchaseAt = a?.purchaseAt;

    if (a?.attachments != null && a!.attachments!.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(a.attachments!);
        if (decoded is List) {
          _attachments = decoded.map((e) => e.toString()).toList();
        } else {
          _attachments = [a.attachments!];
        }
      } catch (_) {
        _attachments = [a.attachments!];
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _value.dispose();
    _salvageValue.dispose();
    _usefulLifeYears.dispose();
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
                subtitle: const Text('Foto fisik aset/kendaraan/properti langsung'),
                onTap: () => Navigator.pop(ctx, 'camera'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined, color: Color(0xFF2563EB)),
                title: const Text('Pilih dari Galeri Foto', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Pilih foto fisik aset dari galeri HP'),
                onTap: () => Navigator.pop(ctx, 'gallery'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined, color: Color(0xFFDC2626)),
                title: const Text('Upload Surat & Berkas PDF Aset', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Upload file PDF (STNK, BPKB, Sertifikat, Faktur, Polis)'),
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
      if (mounted) showAppSnack(context, 'Gagal memilih berkas: $e', error: true);
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
                    const Text('Surat & Berkas PDF Aset', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _purchaseAt ?? now,
      firstDate: DateTime(now.year - 40),
      lastDate: now,
      helpText: 'Tanggal Pembelian',
    );
    if (picked != null) setState(() => _purchaseAt = picked);
  }

  Future<void> _deleteAsset() async {
    if (_saving || _deleting || _saved) return;

    final a = widget.existing;
    if (a == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Aset?'),
        content: Text('Apakah Anda yakin ingin menghapus aset "${a.name}"? Data riwayat nilai dan perawatan akan dihapus.'),
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
      await db.deleteAsset(a.id);
      ref.read(syncSchedulerProvider).schedule();

      if (mounted) {
        Navigator.of(context).pop(); // Tutup bottom sheet aset.
        showAppSnack(context, 'Aset "${a.name}" berhasil dihapus');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menghapus aset: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _save() async {
    if (_saving || _deleting || _saved) return;

    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nama aset wajib diisi')),
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
      final price = parseMoney(_price.text);
      final value = _value.text.trim().isEmpty ? price : parseMoney(_value.text);
      final salvagePrice = parseMoney(_salvageValue.text);
      final years = int.tryParse(_usefulLifeYears.text.trim()) ?? 5;
      final usefulMonths = years * 12;
      final attachmentValue = Value(_attachments.isEmpty ? null : jsonEncode(_attachments));

      if (widget.existing == null) {
        final saved = await db.saveAsset(AssetsCompanion.insert(
          id: newId(),
          workspaceId: ws.id,
          name: name,
          category: Value(_category),
          purchaseAt: Value(_purchaseAt),
          purchasePrice: Value(price == 0 ? null : price),
          currentValue: Value(value),
          salvageValue: Value(salvagePrice > 0 ? salvagePrice : null),
          usefulLifeMonths: Value(usefulMonths),
          depreciationMethod: Value(_depreciationMethod),
          status: Value(_status),
          debtId: Value(_debtId),
          attachments: attachmentValue,
          note: Value(_note.text.trim().isEmpty ? null : _note.text.trim()),
          createdAt: now,
          updatedAt: now,
          deviceId: '',
        ));
        if (price > 0) {
          try {
            await db.addValuation(
              workspaceId: ws.id,
              assetId: saved.id,
              value: price,
              valuedAt: _purchaseAt ?? now,
              source: 'PURCHASE',
              note: 'Harga Perolehan / Beli',
            );
          } catch (_) {}
        }
        if (value > 0 && value != price) {
          try {
            await db.addValuation(
              workspaceId: ws.id,
              assetId: saved.id,
              value: value,
              valuedAt: now,
              source: 'MANUAL',
              note: 'Valuasi Pasar Terkini',
            );
          } catch (_) {}
        }
      } else {
        await db.saveAsset(AssetsCompanion(
          id: Value(widget.existing!.id),
          workspaceId: Value(widget.existing!.workspaceId),
          name: Value(name),
          category: Value(_category),
          purchaseAt: Value(_purchaseAt),
          purchasePrice: Value(price == 0 ? null : price),
          currentValue: Value(value),
          salvageValue: Value(salvagePrice > 0 ? salvagePrice : null),
          usefulLifeMonths: Value(usefulMonths),
          depreciationMethod: Value(_depreciationMethod),
          status: Value(_status),
          debtId: Value(_debtId),
          attachments: attachmentValue,
          note: Value(_note.text.trim().isEmpty ? null : _note.text.trim()),
        ));
      }

      ref.read(syncSchedulerProvider).schedule();

      if (mounted) {
        _saved = true;
        Navigator.of(context).pop();
        showAppSnack(
          context,
          widget.existing == null ? 'Aset berhasil ditambahkan' : 'Perubahan aset disimpan',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan aset: $e')),
        );
      }
    } finally {
      if (mounted && !_saved) setState(() => _saving = false);
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
                  widget.existing == null ? 'Tambah Aset Baru' : 'Edit Data Aset',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.3),
                ),
                if (widget.existing != null)
                  OutlinedButton.icon(
                    onPressed: (_saving || _deleting || _saved) ? null : _deleteAsset,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kDanger,
                      side: BorderSide(color: kDanger.withValues(alpha: 0.4)),
                      minimumSize: const Size(0, 38),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    icon: _deleting
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: kDanger))
                        : const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Hapus', style: TextStyle(fontSize: 12.5)),
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
                  const Text('Nama Aset *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _name,
                    autofocus: widget.existing == null,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(hintText: 'Misal: Laptop MacBook / Toyota Avanza'),
                  ),
                  const SizedBox(height: 16),

                  Text(
                    'Kategori',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final entry in assetCategories.entries)
                        ChoiceChip(
                          selected: _category == entry.key,
                          onSelected: (_) => setState(() => _category = entry.key),
                          label: Text(entry.value),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  Text(
                    'Relasi Angsuran / Catatan Utang (opsional)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 6),
                  () {
                    final debtsList = ref.watch(debtsProvider).valueOrNull ?? const <Debt>[];
                    final openDebts = debtsList.where((d) => d.remaining > 0 && d.direction == 'PAYABLE').toList();

                    if (openDebts.isEmpty) {
                      return Text(
                        'Belum ada catatan angsuran aktif di menu Perencanaan.',
                        style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                      );
                    }

                    return DropdownButtonFormField<String?>(
                      initialValue: _debtId,
                      decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('Tanpa Angsuran (Lunas / Bebas Utang)', style: TextStyle(fontSize: 13))),
                        for (final d in openDebts)
                          DropdownMenuItem<String?>(
                            value: d.id,
                            child: Text('${d.counterparty} (Sisa ${formatMoney(d.remaining)})', style: const TextStyle(fontSize: 13)),
                          ),
                      ],
                      onChanged: (val) => setState(() => _debtId = val),
                    );
                  }(),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Harga Beli (Rp)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _price,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(hintText: '0'),
                              onChanged: (val) {
                                final formatted = formatMoneyInput(val);
                                if (formatted != val) {
                                  _price.value = TextEditingValue(
                                    text: formatted,
                                    selection: TextSelection.collapsed(offset: formatted.length),
                                  );
                                }
                                setState(() {});
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Nilai Sekarang (Rp)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _value,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(hintText: '0'),
                              onChanged: (val) {
                                final formatted = formatMoneyInput(val);
                                if (formatted != val) {
                                  _value.value = TextEditingValue(
                                    text: formatted,
                                    selection: TextSelection.collapsed(offset: formatted.length),
                                  );
                                }
                                setState(() {});
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.event_outlined, size: 18),
                    label: Text(_purchaseAt == null ? 'Tanggal Pembelian' : formatDate(_purchaseAt!)),
                  ),
                  const SizedBox(height: 16),

                  const Divider(height: 1),
                  const SizedBox(height: 14),
                  const Text('Dinamika Perubahan Nilai Aset', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        selected: _depreciationMethod == 'STRAIGHT_LINE',
                        onSelected: (_) => setState(() => _depreciationMethod = 'STRAIGHT_LINE'),
                        avatar: const Icon(Icons.trending_down_rounded, size: 14, color: Colors.deepOrange),
                        label: const Text('Penyusutan Garis Lurus (Kendaraan/Gadget)'),
                      ),
                      ChoiceChip(
                        selected: _depreciationMethod == 'APPRECIATION',
                        onSelected: (_) => setState(() => _depreciationMethod = 'APPRECIATION'),
                        avatar: const Icon(Icons.trending_up_rounded, size: 14, color: Color(0xFF059669)),
                        label: const Text('Pertambahan Nilai / Apresiasi (Properti/Investasi)'),
                      ),
                      ChoiceChip(
                        selected: _depreciationMethod == 'DECLINING_BALANCE',
                        onSelected: (_) => setState(() => _depreciationMethod = 'DECLINING_BALANCE'),
                        label: const Text('Penyusutan Saldo Menurun'),
                      ),
                      ChoiceChip(
                        selected: _depreciationMethod == 'NONE',
                        onSelected: (_) => setState(() => _depreciationMethod = 'NONE'),
                        label: const Text('Nilai Tetap / Stabil'),
                      ),
                    ],
                  ),
                  if (_depreciationMethod == 'STRAIGHT_LINE' || _depreciationMethod == 'DECLINING_BALANCE') ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Batas Bawah / Nilai Residu (Rp)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _salvageValue,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(hintText: 'Mis: 2.000.000 (Batas Minimal)'),
                                onChanged: (val) {
                                  final formatted = formatMoneyInput(val);
                                  if (formatted != val) {
                                    _salvageValue.value = TextEditingValue(
                                      text: formatted,
                                      selection: TextSelection.collapsed(offset: formatted.length),
                                    );
                                  }
                                  setState(() {});
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Usia Manfaat (Tahun)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _usefulLifeYears,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(hintText: 'Mis: 5 (Tahun)'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ] else if (_depreciationMethod == 'APPRECIATION') ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF059669).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.3)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.trending_up_rounded, color: Color(0xFF059669), size: 20),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Aset Properti / Investasi cenderung mengalami Pertambahan Nilai (Capital Gain). Aplikasi akan menghitung akumulasi keuntungan bersih secara otomatis.',
                              style: TextStyle(fontSize: 11, color: Color(0xFF059669), height: 1.3),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  Text(
                    'Status Aset',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final s in const {'ACTIVE': 'Aktif', 'MAINTENANCE': 'Perawatan', 'SOLD': 'Terjual', 'LOST': 'Hilang'}.entries)
                        ChoiceChip(
                          selected: _status == s.key,
                          onSelected: (_) => setState(() => _status = s.key),
                          label: Text(s.value),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  const Text('Catatan Aset (opsional)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _note,
                    minLines: 1,
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(hintText: 'Nomor seri, spesifikasi, lokasi...'),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Foto Fisik & Berkas Legal Aset (${_attachments.length})',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurfaceVariant),
                      ),
                      IconButton(
                        onPressed: _pickAttachments,
                        tooltip: 'Tambah Foto / Berkas PDF',
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
                                          'Berkas PDF',
                                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.red),
                                        ),
                                      ],
                                    ),
                                  )
                                else if (provider == null)
                                  const Center(child: Icon(Icons.inventory_2_outlined, color: Colors.grey)),
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
              child: FilledButton.icon(
                onPressed: (_saving || _deleting || _saved) ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check, size: 18),
                label: Text(widget.existing == null ? 'Simpan Aset' : 'Simpan Perubahan'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
