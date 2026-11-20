import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/remote/api_client.dart';
import '../common/widgets.dart';

final invoiceFilterProvider = StateProvider<String>((ref) => 'UNPAID');
final invoiceSearchProvider = StateProvider<String>((ref) => '');

class InvoicesScreen extends ConsumerStatefulWidget {
  const InvoicesScreen({super.key});

  @override
  ConsumerState<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends ConsumerState<InvoicesScreen> {
  bool _loading = true;
  String? _error;
  List<dynamic> _invoices = [];
  List<dynamic> _banks = [];

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = ref.read(apiClientProvider);
      
      // Fetch invoices & banks in parallel
      final res = await Future.wait([
        client.get('/api/axon/invoices?full=1&limit=100'),
        client.get('/api/axon/banks'),
      ]);

      final invRes = res[0];
      final bankRes = res[1];

      setState(() {
        _invoices = (invRes['data'] as List?) ?? (invRes['invoices'] as List?) ?? [];
        _banks = (bankRes['data'] as List?) ?? (bankRes['banks'] as List?) ?? [];
        _loading = false;
      });
    } catch (e) {
      String msg = e.toString();
      if (e is ApiException) {
        msg = e.message;
      }
      setState(() {
        _error = msg;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filter = ref.watch(invoiceFilterProvider);
    final search = ref.watch(invoiceSearchProvider).toLowerCase();

    final filtered = _invoices.where((inv) {
      final invNum = (inv['number'] ?? inv['invoiceNumber'] ?? '').toString().toLowerCase();
      final custName = (inv['customer']?['name'] ?? inv['customerName'] ?? '').toString().toLowerCase();
      final matchesSearch = search.isEmpty || invNum.contains(search) || custName.contains(search);

      final status = (inv['status'] ?? inv['paymentStatus'] ?? '').toString().toUpperCase();
      final isOverdue = inv['isOverdue'] == true;
      final outstanding = parseMoney((inv['outstandingAmount'] ?? inv['remaining'] ?? 0).toString());

      if (!matchesSearch) return false;

      if (filter == 'UNPAID') {
        return outstanding > 0 || status == 'SENT' || status == 'POSTED' || status == 'PARTIAL' || isOverdue;
      } else if (filter == 'PAID') {
        return outstanding <= 0 || status == 'PAID';
      }
      return true;
    }).toList();

    // Hitung total sisa tagihan aktif
    final totalOutstanding = _invoices.fold<int>(0, (sum, inv) {
      final out = parseMoney((inv['outstandingAmount'] ?? inv['remaining'] ?? 0).toString());
      return sum + (out > 0 ? out : 0);
    });

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Tagihan & Invoice Axon Web', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            tooltip: 'Segarkan',
            onPressed: _fetchData,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.cloud_off_rounded, size: 48, color: kExpense),
                        const SizedBox(height: 12),
                        Text('Gagal Menghubungkan ke Axon Web:\n$_error', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5)),
                        const SizedBox(height: 16),
                        FilledButton.tonal(onPressed: _fetchData, child: const Text('Coba Lagi')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchData,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    children: [
                      // Banner Ringkasan Tagihan
                      Card(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: LinearGradient(
                              colors: [
                                theme.colorScheme.primary.withValues(alpha: 0.12),
                                theme.colorScheme.surface,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.receipt_long_rounded, color: theme.colorScheme.primary, size: 22),
                                  const SizedBox(width: 10),
                                  const Text('Integrasi Axon Enterprise Engine', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF059669).withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Row(
                                      children: [
                                        Icon(Icons.verified_rounded, size: 12, color: Color(0xFF059669)),
                                        SizedBox(width: 3),
                                        Text('API Ready', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF059669))),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text('Total Sisa Tagihan Aktif', style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                              const SizedBox(height: 2),
                              Text(
                                formatMoney(totalOutstanding),
                                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: kExpense, letterSpacing: -0.8),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${_invoices.length} Invoice terdaftar dari sistem Web Axon',
                                style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Filter & Search
                      ShadInput(
                        placeholder: const Text('Cari Nomor Invoice (INV-...) atau Nama Customer...'),
                        leading: const Icon(Icons.search, size: 18),
                        onChanged: (v) => ref.read(invoiceSearchProvider.notifier).state = v,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          ChoiceChip(
                            selected: filter == 'UNPAID',
                            onSelected: (_) => ref.read(invoiceFilterProvider.notifier).state = 'UNPAID',
                            label: const Text('Belum Lunas / Overdue'),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            selected: filter == 'PAID',
                            onSelected: (_) => ref.read(invoiceFilterProvider.notifier).state = 'PAID',
                            label: const Text('Sudah Lunas'),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            selected: filter == 'ALL',
                            onSelected: (_) => ref.read(invoiceFilterProvider.notifier).state = 'ALL',
                            label: const Text('Semua'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      if (filtered.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 32),
                          child: EmptyState(
                            icon: Icons.receipt_long_outlined,
                            title: 'Tidak Ada Tagihan',
                            message: 'Tidak ada invoice yang sesuai kriteria filter.',
                          ),
                        )
                      else
                        for (final inv in filtered) ...[
                          _InvoiceCard(
                            invoice: inv,
                            banks: _banks,
                            onPaymentRecorded: _fetchData,
                          ),
                          const SizedBox(height: 8),
                        ],
                    ],
                  ),
                ),
    );
  }
}

class _InvoiceCard extends ConsumerWidget {
  const _InvoiceCard({
    required this.invoice,
    required this.banks,
    required this.onPaymentRecorded,
  });

  final Map<String, dynamic> invoice;
  final List<dynamic> banks;
  final VoidCallback onPaymentRecorded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final id = (invoice['id'] ?? '').toString();
    final number = (invoice['number'] ?? invoice['invoiceNumber'] ?? 'INV-...').toString();
    final customerName = (invoice['customer']?['name'] ?? invoice['customerName'] ?? 'Customer').toString();
    final totalAmount = parseMoney((invoice['total'] ?? invoice['amount'] ?? 0).toString());
    final paidAmount = parseMoney((invoice['paidAmount'] ?? invoice['paid'] ?? 0).toString());
    final outstandingAmount = parseMoney((invoice['outstandingAmount'] ?? invoice['remaining'] ?? (totalAmount - paidAmount)).toString());
    final isOverdue = invoice['isOverdue'] == true;
    final status = (invoice['status'] ?? invoice['paymentStatus'] ?? 'POSTED').toString().toUpperCase();

    final issueDateStr = invoice['date'] ?? invoice['issueDate'] ?? invoice['createdAt'];
    final dueDateStr = invoice['dueDate'];

    final issueDate = issueDateStr != null ? DateTime.tryParse(issueDateStr.toString()) : null;
    final dueDate = dueDateStr != null ? DateTime.tryParse(dueDateStr.toString()) : null;

    final canPay = outstandingAmount > 0 && status != 'PAID' && status != 'CANCELLED';

    Color statusColor;
    String statusLabelStr;

    if (status == 'PAID' || outstandingAmount <= 0) {
      statusColor = const Color(0xFF059669);
      statusLabelStr = 'LUNAS';
    } else if (isOverdue || status == 'OVERDUE') {
      statusColor = Colors.red.shade700;
      statusLabelStr = 'JATUH TEMPO';
    } else if (status == 'PARTIAL') {
      statusColor = Colors.orange.shade800;
      statusLabelStr = 'SEBAGIAN';
    } else {
      statusColor = const Color(0xFF2563EB);
      statusLabelStr = status;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    number,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, fontFamily: 'monospace'),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: number));
                    showAppSnack(context, 'Nomor invoice "$number" disalin!');
                  },
                  child: Icon(Icons.copy_rounded, size: 14, color: theme.colorScheme.primary),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    statusLabelStr,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: statusColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            Text(customerName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),

            Row(
              children: [
                if (issueDate != null)
                  Text('Terbit: ${formatDate(issueDate)}', style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                if (issueDate != null && dueDate != null)
                  const Text(' · ', style: TextStyle(fontSize: 11)),
                if (dueDate != null)
                  Text(
                    'Tenggat: ${formatDate(dueDate)}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isOverdue ? FontWeight.w700 : FontWeight.w400,
                      color: isOverdue ? Colors.red.shade700 : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total Tagihan', style: TextStyle(fontSize: 10.5, color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 2),
                    Text(formatMoney(totalAmount), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Sisa Tagihan (Belum Lunas)', style: TextStyle(fontSize: 10.5, color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 2),
                    Text(
                      formatMoney(outstandingAmount),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: outstandingAmount > 0 ? kExpense : const Color(0xFF059669),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            if (canPay) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _showPaymentDialog(context, ref, id, number, customerName, outstandingAmount),
                  icon: const Icon(Icons.payment_rounded, size: 16),
                  label: const Text('Catat Pembayaran Invoice (+)', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showPaymentDialog(
    BuildContext context,
    WidgetRef ref,
    String invoiceId,
    String invoiceNumber,
    String customerName,
    int maxOutstanding,
  ) async {
    final amountController = TextEditingController(text: formatNumber(maxOutstanding));
    final referenceController = TextEditingController();
    final notesController = TextEditingController();

    String selectedMethod = 'TRANSFER';
    String? selectedBankId = banks.isNotEmpty ? (banks.first['id'] ?? '').toString() : null;
    String? proofBase64;
    bool saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final bottomInset = MediaQuery.viewInsetsOf(ctx).bottom;

          return Padding(
            padding: EdgeInsets.only(bottom: bottomInset),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Catat Pembayaran Invoice', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                          Text('$invoiceNumber · $customerName', style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 14),

                  const Text('Nominal Pembayaran (Rp) *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: amountController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kIncome),
                    decoration: const InputDecoration(hintText: '0'),
                    onChanged: (val) {
                      final formatted = formatMoneyInput(val);
                      if (formatted != val) {
                        amountController.value = TextEditingValue(
                          text: formatted,
                          selection: TextSelection.collapsed(offset: formatted.length),
                        );
                      }
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 14),

                  const Text('Metode Pembayaran', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final m in const {'TRANSFER': 'Transfer Bank', 'CASH': 'Tunai', 'QRIS': 'QRIS / E-Money'}.entries)
                        ChoiceChip(
                          selected: selectedMethod == m.key,
                          onSelected: (_) => setState(() => selectedMethod = m.key),
                          label: Text(m.value),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  if (banks.isNotEmpty) ...[
                    const Text('Pilih Rekening Bank Tujuan', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: selectedBankId,
                      decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                      items: [
                        for (final b in banks)
                          DropdownMenuItem<String>(
                            value: (b['id'] ?? '').toString(),
                            child: Text('${b['bankName'] ?? b['name'] ?? 'Bank'} - ${b['accountNumber'] ?? ''} (${b['accountName'] ?? ''})', style: const TextStyle(fontSize: 12.5)),
                          ),
                      ],
                      onChanged: (v) => setState(() => selectedBankId = v),
                    ),
                    const SizedBox(height: 14),
                  ],

                  const Text('Nomor Referensi / No TRX (opsional)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: referenceController,
                    decoration: const InputDecoration(hintText: 'Misal: TRX-98234 / BCA-8812'),
                  ),
                  const SizedBox(height: 14),

                  const Text('Catatan Pembayaran (opsional)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: notesController,
                    decoration: const InputDecoration(hintText: 'Misal: Pelunasan via Mobile Axon'),
                  ),
                  const SizedBox(height: 14),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Foto / PDF Bukti Bayar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      TextButton.icon(
                        onPressed: () async {
                          final picker = ImagePicker();
                          final XFile? file = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1200, imageQuality: 70);
                          if (file != null) {
                            final bytes = await file.readAsBytes();
                            final mime = file.mimeType ?? 'image/jpeg';
                            setState(() {
                              proofBase64 = 'data:$mime;base64,${base64Encode(bytes)}';
                            });
                          }
                        },
                        icon: const Icon(Icons.attach_file_rounded, size: 16),
                        label: Text(proofBase64 != null ? 'Bukti Dilihat' : 'Pilih Bukti'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  FilledButton(
                    onPressed: saving
                        ? null
                        : () async {
                            final amount = parseMoney(amountController.text);
                            if (amount <= 0) {
                              showAppSnack(ctx, 'Nominal pembayaran wajib lebih dari 0', error: true);
                              return;
                            }

                            setState(() => saving = true);

                            try {
                              final auth = ref.read(authControllerProvider);
                              final paymentId = const Uuid().v4(); // Client-generated Idempotency UUID Key

                              final payload = {
                                'paymentId': paymentId,
                                'amount': amount,
                                'date': DateTime.now().toIso8601String(),
                                'paymentMethod': selectedMethod,
                                'bankAccountId': selectedBankId,
                                'reference': referenceController.text.trim().isEmpty ? null : referenceController.text.trim(),
                                'notes': notesController.text.trim().isEmpty ? 'Pembayaran via Axon Mobile' : notesController.text.trim(),
                                'proofOfPayment': proofBase64,
                                'recordedBy': auth.name ?? 'Axon Mobile User',
                              };

                              final client = ref.read(apiClientProvider);
                              await client.post('/api/axon/invoices/$invoiceId/payments', payload);

                              if (ctx.mounted) {
                                Navigator.pop(ctx);
                                showAppSnack(context, 'Pembayaran Invoice $invoiceNumber sebesar ${formatMoney(amount)} berhasil dicatat!');
                                onPaymentRecorded();
                              }
                            } catch (e) {
                              if (ctx.mounted) {
                                setState(() => saving = false);
                                showAppSnack(ctx, 'Gagal mencatat pembayaran: $e', error: true);
                              }
                            }
                          },
                    child: saving
                        ? const CircularProgressIndicator(strokeWidth: 2, color: Colors.white)
                        : const Text('Kirim Pembayaran ke Axon Web', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
