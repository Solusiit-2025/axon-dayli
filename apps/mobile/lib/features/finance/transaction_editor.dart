import 'dart:convert';
import 'package:collection/collection.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/providers.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/ocr_service.dart';
import '../../core/theme.dart';
import '../../data/local/database.dart';
import '../common/widgets.dart';
import 'amount_calculator.dart';

Future<void> showTransactionEditor(
  BuildContext context,
  WidgetRef ref, {
  Txn? existing,
  String initialType = 'EXPENSE',
  String? initialCategoryId,
  String? initialBudgetId,
  String? initialNote,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _TransactionEditorSheet(
      existing: existing,
      initialType: initialType,
      initialCategoryId: initialCategoryId,
      initialBudgetId: initialBudgetId,
      initialNote: initialNote,
    ),
  );
}

class _TransactionEditorSheet extends ConsumerStatefulWidget {
  const _TransactionEditorSheet({
    this.existing,
    required this.initialType,
    this.initialCategoryId,
    this.initialBudgetId,
    this.initialNote,
  });

  final Txn? existing;
  final String initialType;
  final String? initialCategoryId;
  final String? initialBudgetId;
  final String? initialNote;

  @override
  ConsumerState<_TransactionEditorSheet> createState() =>
      _TransactionEditorSheetState();
}

class _TransactionEditorSheetState
    extends ConsumerState<_TransactionEditorSheet> {
  late String _type;
  late String? _categoryId;
  late String? _budgetId;
  late String? _walletId;
  late String? _toWalletId;
  late DateTime _occurredAt;
  late final TextEditingController _amount;
  late final TextEditingController _fee;
  late final TextEditingController _note;
  late final TextEditingController _payee;
  List<String> _attachments = [];
  bool _saving = false;

  /// Mencegah simpan ganda saat sheet belum selesai ditutup.
  bool _saved = false;
  bool _scanningOcr = false;

  @override
  void initState() {
    super.initState();
    final t = widget.existing;
    _type = t?.type ?? widget.initialType;
    _categoryId = t?.categoryId ?? widget.initialCategoryId;
    _budgetId = t?.budgetId ?? widget.initialBudgetId;
    _walletId = t?.walletId;
    _toWalletId = null;
    _occurredAt = t?.occurredAt ?? DateTime.now();
    _amount = TextEditingController(
      text: t == null ? '' : formatNumber(t.amount),
    );
    _fee = TextEditingController(
      text: t?.fee != null && t!.fee > 0 ? formatNumber(t.fee) : '',
    );
    _note = TextEditingController(text: t?.note ?? widget.initialNote ?? '');
    _payee = TextEditingController(text: t?.payee ?? '');

    if (t?.attachmentId != null && t!.attachmentId!.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(t.attachmentId!);
        if (decoded is List) {
          _attachments = decoded.map((e) => e.toString()).toList();
        } else {
          _attachments = [t.attachmentId!];
        }
      } catch (_) {
        _attachments = [t.attachmentId!];
      }
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _fee.dispose();
    _note.dispose();
    _payee.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    try {
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(
                  Icons.camera_alt_outlined,
                  color: Color(0xFF4F46E5),
                ),
                title: const Text(
                  'Ambil Foto Kamera',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Foto struk / nota langsung dengan kamera HP',
                ),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(
                  Icons.photo_library_outlined,
                  color: Color(0xFF2563EB),
                ),
                title: const Text(
                  'Pilih dari Galeri',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text('Pilih foto struk/bukti dari galeri'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      );

      if (source == null) return;

      if (source == ImageSource.camera) {
        final picker = ImagePicker();
        final XFile? file = await picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 70,
        );
        if (file == null) return;

        final bytes = await file.readAsBytes();
        final base64Str = base64Encode(bytes);
        final mimeType = file.mimeType ?? 'image/jpeg';
        final dataUrl = 'data:$mimeType;base64,$base64Str';
        setState(() {
          _attachments.add(dataUrl);
        });
      } else {
        final picker = ImagePicker();
        final List<XFile> pickedFiles = await picker.pickMultiImage(
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 70,
        );
        if (pickedFiles.isEmpty) return;

        for (final file in pickedFiles) {
          final bytes = await file.readAsBytes();
          final base64Str = base64Encode(bytes);
          final mimeType = file.mimeType ?? 'image/jpeg';
          final dataUrl = 'data:$mimeType;base64,$base64Str';
          _attachments.add(dataUrl);
        }
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal mengambil gambar: $e')));
      }
    }
  }

  Future<void> _scanOcr() async {
    try {
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(
                  Icons.camera_alt_outlined,
                  color: Color(0xFF4F46E5),
                ),
                title: const Text(
                  'Foto Struk dengan Kamera',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Ambil foto nota/struk langsung untuk di-scan OCR',
                ),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(
                  Icons.photo_library_outlined,
                  color: Color(0xFF2563EB),
                ),
                title: const Text(
                  'Pilih Foto dari Galeri',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Pilih foto nota yang sudah ada di galeri',
                ),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      );

      if (source == null) return;

      final picker = ImagePicker();
      final XFile? file = await picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 70,
      );
      if (file == null) return;

      final bytes = await file.readAsBytes();
      final base64Str = base64Encode(bytes);
      final mimeType = file.mimeType ?? 'image/jpeg';
      final dataUrl = 'data:$mimeType;base64,$base64Str';

      if (!_attachments.contains(dataUrl)) {
        _attachments.add(dataUrl);
      }

      setState(() => _scanningOcr = true);

      final ocrRes = await OcrService.scanReceipt(dataUrl);

      if (!mounted) return;

      if (ocrRes != null) {
        if (ocrRes.amount != null && ocrRes.amount! > 0) {
          final formatted = formatMoneyInput(ocrRes.amount.toString());
          _amount.value = TextEditingValue(
            text: formatted,
            selection: TextSelection.collapsed(offset: formatted.length),
          );
        }
        if (ocrRes.payee != null &&
            ocrRes.payee!.isNotEmpty &&
            _payee.text.trim().isEmpty) {
          _payee.text = ocrRes.payee!;
        }
        if (ocrRes.date != null) {
          _occurredAt = ocrRes.date!;
        }

        final foundText = ocrRes.amount != null
            ? 'Rp ${formatNumber(ocrRes.amount!)}'
            : 'Teks dibaca';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('OCR Berhasil: $foundText'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Toko/Nominal nota tidak terdeteksi otomatis. Lampiran tetap disimpan.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Pemindaian OCR gagal: $e')));
      }
    } finally {
      if (mounted) setState(() => _scanningOcr = false);
    }
  }

  void _showImageDialog(String item) {
    ImageProvider? provider;
    if (item.startsWith('data:image')) {
      final base64Part = item.split(',').last;
      provider = MemoryImage(base64Decode(base64Part));
    } else if (item.startsWith('http')) {
      provider = NetworkImage(item);
    }

    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (provider != null)
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

  Future<void> _openCalculator() async {
    final result = await showAmountCalculator(
      context,
      initial: parseMoney(_amount.text),
    );
    if (result == null || !mounted) return;
    setState(() {
      _amount.text = formatNumber(result);
      _amount.selection = TextSelection.collapsed(offset: _amount.text.length);
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime(DateTime.now().year - 5),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(
        () => _occurredAt = DateTime(picked.year, picked.month, picked.day, 12),
      );
    }
  }

  Future<void> _save() async {
    if (_saving || _saved) return;

    final amount = parseMoney(_amount.text);
    if (amount <= 0) {
      setState(() {});
      return;
    }

    final ws = ref.read(currentWorkspaceProvider);
    final wallets = ref.read(walletsProvider).valueOrNull ?? const <Wallet>[];
    if (ws == null || wallets.isEmpty) return;

    final walletId = _walletId ?? wallets.first.id;
    setState(() => _saving = true);

    try {
      final db = ref.read(databaseProvider);
      final now = DateTime.now();
      final attachmentValue = Value(
        _attachments.isEmpty ? null : jsonEncode(_attachments),
      );

      if (_type == 'TRANSFER') {
        final toId = _toWalletId ?? (wallets.length > 1 ? (wallets.first.id == walletId ? wallets[1].id : wallets.first.id) : walletId);
        if (walletId == toId) {
          showAppSnack(context, 'Dompet asal dan dompet tujuan tidak boleh sama', error: true);
          if (mounted) setState(() => _saving = false);
          return;
        }

        final transferGroup = widget.existing?.transferGroupId ?? newId();
        final feeAmount = parseMoney(_fee.text);
        final targetWallet = wallets.firstWhereOrNull((w) => w.id == toId);
        final sourceWallet = wallets.firstWhereOrNull((w) => w.id == walletId);

        await db.saveTransaction(
          TransactionsCompanion.insert(
            id: widget.existing?.id ?? newId(),
            workspaceId: ws.id,
            walletId: walletId,
            type: 'TRANSFER',
            amount: amount,
            fee: Value(feeAmount),
            transferGroupId: Value(transferGroup),
            occurredAt: _occurredAt,
            payee: Value(targetWallet != null ? 'Transfer ke ${targetWallet.name}' : 'Transfer Keluar'),
            note: Value(_note.text.trim().isEmpty ? null : _note.text.trim()),
            attachmentId: attachmentValue,
            createdAt: now,
            updatedAt: now,
            deviceId: '',
          ),
        );

        if (widget.existing == null) {
          await db.saveTransaction(
            TransactionsCompanion.insert(
              id: newId(),
              workspaceId: ws.id,
              walletId: toId,
              type: 'INCOME',
              amount: amount,
              fee: const Value(0),
              transferGroupId: Value(transferGroup),
              occurredAt: _occurredAt,
              payee: Value(sourceWallet != null ? 'Transfer dari ${sourceWallet.name}' : 'Transfer Masuk'),
              note: Value(_note.text.trim().isEmpty ? null : _note.text.trim()),
              createdAt: now,
              updatedAt: now,
              deviceId: '',
            ),
          );
        }
      } else if (widget.existing == null) {
        await db.saveTransaction(
          TransactionsCompanion.insert(
            id: newId(),
            workspaceId: ws.id,
            walletId: walletId,
            categoryId: Value(_categoryId),
            budgetId: Value(_budgetId),
            type: _type,
            amount: amount,
            occurredAt: _occurredAt,
            note: Value(_note.text.trim().isEmpty ? null : _note.text.trim()),
            payee: Value(
              _payee.text.trim().isEmpty ? null : _payee.text.trim(),
            ),
            attachmentId: attachmentValue,
            createdAt: now,
            updatedAt: now,
            deviceId: '',
          ),
        );
      } else {
        await db.saveTransaction(
          TransactionsCompanion(
            id: Value(widget.existing!.id),
            walletId: Value(walletId),
            categoryId: Value(_categoryId),
            budgetId: Value(_budgetId),
            type: Value(_type),
            amount: Value(amount),
            occurredAt: Value(_occurredAt),
            note: Value(_note.text.trim().isEmpty ? null : _note.text.trim()),
            payee: Value(
              _payee.text.trim().isEmpty ? null : _payee.text.trim(),
            ),
            attachmentId: attachmentValue,
          ),
        );
      }

      ref.read(syncSchedulerProvider).schedule();
      if (mounted) {
        _saved = true;
        final messenger = ScaffoldMessenger.of(context);
        // Pop lewat navigator terdekat (navigator cabang), bukan root.
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              widget.existing == null
                  ? 'Transaksi berhasil dicatat!'
                  : 'Perubahan transaksi disimpan!',
            ),
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted && !_saved) setState(() => _saving = false);
    }
  }

  Future<void> _deleteTransaction() async {
    final t = widget.existing;
    if (t == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Transaksi?'),
        content: Text('Apakah Anda yakin ingin menghapus transaksi nominal ${formatMoney(t.amount)} ini? Saldo dompet akan disesuaikan kembali.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kDanger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus Transaksi'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final db = ref.read(databaseProvider);
      await db.deleteTransaction(t.id);
      ref.read(syncSchedulerProvider).schedule();

      if (mounted) {
        Navigator.of(context).pop();
        showAppSnack(context, 'Transaksi berhasil dihapus & saldo disesuaikan');
      }
    } catch (e) {
      if (mounted) showAppSnack(context, 'Gagal menghapus: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories =
        ref.watch(categoriesProvider(_type)).valueOrNull ?? const <Category>[];
    final wallets = ref.watch(walletsProvider).valueOrNull ?? const <Wallet>[];
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final isExpense = _type == 'EXPENSE';
    final accent = isExpense ? kExpense : kIncome;

    final sheetHeight =
        (MediaQuery.sizeOf(context).height -
                bottomInset -
                MediaQuery.paddingOf(context).top -
                72)
            .clamp(280.0, MediaQuery.sizeOf(context).height * 0.88);

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: sheetHeight,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.existing == null ? 'Catat Transaksi Baru' : 'Koreksi Transaksi',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  if (widget.existing != null)
                    IconButton(
                      tooltip: 'Hapus Transaksi',
                      icon: const Icon(Icons.delete_outline_rounded, color: kDanger, size: 20),
                      onPressed: _deleteTransaction,
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(
                                value: 'EXPENSE',
                                label: Text('Keluar'),
                                icon: Icon(Icons.south_west, size: 15),
                              ),
                              ButtonSegment(
                                value: 'INCOME',
                                label: Text('Masuk'),
                                icon: Icon(Icons.north_east, size: 15),
                              ),
                              ButtonSegment(
                                value: 'TRANSFER',
                                label: Text('Transfer'),
                                icon: Icon(Icons.swap_horiz, size: 15),
                              ),
                            ],
                            selected: {_type},
                            onSelectionChanged: (s) => setState(() {
                              _type = s.first;
                              _categoryId = null;
                            }),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    Text(
                      _type == 'TRANSFER' ? 'Nominal Transfer' : 'Nominal',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'Rp',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: _type == 'TRANSFER' ? theme.colorScheme.primary : accent,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _amount,
                            autofocus: widget.existing == null,
                            keyboardType: TextInputType.number,
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              color: _type == 'TRANSFER' ? theme.colorScheme.primary : accent,
                              letterSpacing: -1,
                            ),
                            decoration: const InputDecoration(
                              hintText: '0',
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                              contentPadding: EdgeInsets.zero,
                            ),
                            onChanged: (value) {
                              final formatted = formatMoneyInput(value);
                              if (formatted != value) {
                                _amount.value = TextEditingValue(
                                  text: formatted,
                                  selection: TextSelection.collapsed(
                                    offset: formatted.length,
                                  ),
                                );
                              }
                              setState(() {});
                            },
                          ),
                        ),
                        IconButton(
                          tooltip: 'Kalkulator nominal',
                          onPressed: _openCalculator,
                          icon: const Icon(Icons.calculate_outlined, size: 22),
                        ),
                      ],
                    ),
                    const Divider(height: 1),
                    const SizedBox(height: 16),

                    if (_type != 'TRANSFER') ...[
                      Text(
                        'Kategori',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (categories.isEmpty)
                        Text(
                          'Belum ada kategori',
                          style: theme.textTheme.bodySmall,
                        )
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final c in categories)
                              ChoiceChip(
                                selected: _categoryId == c.id,
                                onSelected: (_) => setState(
                                  () => _categoryId = _categoryId == c.id
                                      ? null
                                      : c.id,
                                ),
                                avatar: CircleAvatar(
                                  radius: 5,
                                  backgroundColor: _parseColor(c.color),
                                ),
                                label: Text(c.name),
                              ),
                          ],
                        ),

                      if (isExpense) ...[
                        const SizedBox(height: 16),
                        Text(
                          'Pos Anggaran (Relasi Kuota Anggaran)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        () {
                          final budgetsList = ref.watch(budgetsProvider).valueOrNull ?? const <Budget>[];
                          if (budgetsList.isEmpty) {
                            return Text(
                              'Belum ada pos anggaran aktif',
                              style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                            );
                          }
                          return Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ChoiceChip(
                                selected: _budgetId == null,
                                onSelected: (_) => setState(() => _budgetId = null),
                                label: const Text('Otomatis / Kategori Umum'),
                              ),
                              for (final b in budgetsList)
                                ChoiceChip(
                                  selected: _budgetId == b.id,
                                  onSelected: (_) => setState(() {
                                    if (_budgetId == b.id) {
                                      _budgetId = null;
                                    } else {
                                      _budgetId = b.id;
                                      _categoryId = b.categoryId;
                                      if (_note.text.trim().isEmpty && b.name?.isNotEmpty == true) {
                                        _note.text = b.name!;
                                      }
                                    }
                                  }),
                                  avatar: const Icon(Icons.savings_outlined, size: 14),
                                  label: Text(b.name?.isNotEmpty == true ? b.name! : (categories.where((c) => c.id == b.categoryId).firstOrNull?.name ?? 'Anggaran')),
                                ),
                            ],
                          );
                        }(),
                      ],

                      const SizedBox(height: 16),
                      Text(
                        'Dompet',
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
                          for (final w in wallets)
                            ChoiceChip(
                              selected: (_walletId ?? wallets.first.id) == w.id,
                              onSelected: (_) => setState(() => _walletId = w.id),
                              label: Text(w.name),
                            ),
                        ],
                      ),
                    ] else ...[
                      // UI Transfer Saldo Antar Dompet
                      Text(
                        'Dompet Asal (Dari)',
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
                          for (final w in wallets)
                            ChoiceChip(
                              selected: (_walletId ?? wallets.first.id) == w.id,
                              onSelected: (_) => setState(() => _walletId = w.id),
                              avatar: const Icon(Icons.outbox_rounded, size: 14),
                              label: Text(w.name),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      Text(
                        'Dompet Tujuan (Ke)',
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
                          for (final w in wallets)
                            ChoiceChip(
                              selected: (_toWalletId ?? (wallets.length > 1 ? (wallets.first.id == (_walletId ?? wallets.first.id) ? wallets[1].id : wallets.first.id) : wallets.first.id)) == w.id,
                              onSelected: (_) => setState(() => _toWalletId = w.id),
                              avatar: const Icon(Icons.inbox_rounded, size: 14),
                              label: Text(w.name),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      const Text(
                        'Biaya Admin / Transfer (opsional)',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _fee,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          hintText: 'Misal: 6.500 (opsional)',
                        ),
                        onChanged: (val) {
                          final formatted = formatMoneyInput(val);
                          if (formatted != val) {
                            _fee.value = TextEditingValue(
                              text: formatted,
                              selection: TextSelection.collapsed(offset: formatted.length),
                            );
                          }
                        },
                      ),
                    ],

                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickDate,
                            icon: const Icon(Icons.event_outlined, size: 18),
                            label: Text(formatDate(_occurredAt)),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),
                    const Text(
                      'Untuk / Dari Siapa',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _payee,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        hintText: 'Misal: Toko ABC / PT XYZ',
                      ),
                    ),
                    const SizedBox(height: 14),

                    const Text(
                      'Catatan',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _note,
                      minLines: 1,
                      maxLines: 2,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Catatan detail transaksi...',
                      ),
                    ),

                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Lampiran Bukti (${_attachments.length})',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Row(
                          children: [
                            OutlinedButton.icon(
                              onPressed: _scanningOcr ? null : _scanOcr,
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 38),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                              ),
                              icon: _scanningOcr
                                  ? const SizedBox(
                                      width: 13,
                                      height: 13,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.document_scanner_outlined,
                                      size: 15,
                                    ),
                              label: Text(
                                _scanningOcr ? 'Scanning...' : 'Scan OCR',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            const SizedBox(width: 6),
                            IconButton(
                              onPressed: _pickImages,
                              tooltip: 'Tambah Foto',
                              icon: const Icon(
                                Icons.add_a_photo_outlined,
                                size: 20,
                              ),
                            ),
                          ],
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
                            ImageProvider? provider;
                            if (item.startsWith('data:image')) {
                              final base64Part = item.split(',').last;
                              provider = MemoryImage(base64Decode(base64Part));
                            } else if (item.startsWith('http')) {
                              provider = NetworkImage(item);
                            }

                            return Container(
                              width: 85,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: theme.dividerColor),
                                image: provider != null
                                    ? DecorationImage(
                                        image: provider,
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                              ),
                              child: Stack(
                                children: [
                                  if (provider == null)
                                    const Center(
                                      child: Icon(
                                        Icons.image,
                                        color: Colors.grey,
                                      ),
                                    ),
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
                                          color: Colors.black.withValues(
                                            alpha: 0.7,
                                          ),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.close,
                                          size: 12,
                                          color: Colors.white,
                                        ),
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

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // Footer tetap: tombol simpan selalu terlihat & bisa ditekan.
            Container(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(top: BorderSide(color: theme.dividerColor)),
              ),
              child: SafeArea(
                top: false,
                minimum: const EdgeInsets.only(bottom: 8),
                child: FilledButton.icon(
                  onPressed: (_saving || _saved) ? null : _save,
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check, size: 18),
                  label: Text(
                    widget.existing == null
                        ? 'Simpan Transaksi'
                        : 'Simpan Perubahan',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Color _parseColor(String hex) {
  final cleaned = hex.replaceAll('#', '');
  final value = int.tryParse(cleaned, radix: 16) ?? 0x64748B;
  return Color(0xFF000000 | value);
}
