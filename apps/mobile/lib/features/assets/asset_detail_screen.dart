import 'dart:convert';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/local/database.dart';
import '../common/widgets.dart';
import 'asset_editor.dart';

class AssetDetailScreen extends ConsumerWidget {
  const AssetDetailScreen({super.key, required this.assetId});

  final String assetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final asset = ref.watch(assetProvider(assetId)).valueOrNull;
    final valuations = ref.watch(assetValuationsProvider(assetId)).valueOrNull ?? const <AssetValuation>[];
    final maintenances =
        ref.watch(assetMaintenancesProvider(assetId)).valueOrNull ?? const <AssetMaintenance>[];

    if (asset == null) {
      return Scaffold(
        appBar: AppBar(leading: const BackButton()),
        body: const Center(child: Text('Aset tidak ditemukan')),
      );
    }

    final gain = asset.purchasePrice == null ? null : asset.currentValue - asset.purchasePrice!;

    final debts = ref.watch(debtsProvider).valueOrNull ?? const <Debt>[];
    final linkedDebt = debts.where((d) => d.deletedAt == null && (d.id == asset.debtId || d.assetId == asset.id)).firstOrNull;

    // Cari jadwal service mendatang (nextDueAt)
    final upcomingServices = maintenances
        .where((m) => m.nextDueAt != null)
        .toList()
      ..sort((a, b) => a.nextDueAt!.compareTo(b.nextDueAt!));

    final nextService = upcomingServices.isNotEmpty ? upcomingServices.first : null;

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(assetCategories[asset.category] ?? 'Aset'),
        actions: [
          IconButton(
            tooltip: 'Edit Aset',
            onPressed: () => showAssetEditor(context, ref, existing: asset),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Hapus Aset',
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Hapus Aset?'),
                  content: Text('Apakah Anda yakin ingin menghapus aset "${asset.name}"?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Hapus'),
                    ),
                  ],
                ),
              );

              if (confirm == true) {
                await ref.read(databaseProvider).deleteAsset(asset.id);
                ref.read(syncSchedulerProvider).schedule();
                if (context.mounted) Navigator.pop(context); // Kembali ke daftar aset
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Text(
            asset.name,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.5),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nilai sekarang',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatMoney(asset.currentValue),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.8),
                  ),
                  if (gain != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${gain >= 0 ? '+' : ''}${formatMoney(gain)} dari harga beli',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: gain >= 0 ? kIncome : kExpense,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (asset.purchaseAt != null)
                        _Pill(icon: Icons.event_outlined, text: formatDate(asset.purchaseAt!)),
                      if (asset.purchasePrice != null)
                        _Pill(icon: Icons.payments_outlined, text: formatMoney(asset.purchasePrice!)),
                      if (asset.serialNumber?.isNotEmpty == true)
                        _Pill(icon: Icons.tag, text: asset.serialNumber!),
                    ],
                  ),
                ],
              ),
            ),
          ),

          if (asset.purchasePrice != null && asset.purchaseAt != null && asset.purchasePrice! > 0)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: _DepreciationCard(asset: asset),
            ),

          if (linkedDebt != null) ...[
            const SizedBox(height: 16),
            _LinkedDebtCard(debt: linkedDebt, assetValue: asset.currentValue),
          ],

          if (_parsePhotos(asset.attachments).isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Foto Fisik & Dokumen Aset', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            SizedBox(
              height: 110,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _parsePhotos(asset.attachments).length,
                itemBuilder: (context, index) {
                  final item = _parsePhotos(asset.attachments)[index];
                  ImageProvider? provider;
                  if (item.startsWith('data:image')) {
                    final base64Part = item.split(',').last;
                    provider = MemoryImage(base64Decode(base64Part));
                  } else if (item.startsWith('http')) {
                    provider = NetworkImage(item);
                  }

                  return Container(
                    width: 110,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: theme.dividerColor),
                      image: provider != null ? DecorationImage(image: provider, fit: BoxFit.cover) : null,
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _showAssetPhotoDialog(context, item),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],

          if (asset.note?.isNotEmpty == true) ...[
            const SizedBox(height: 16),
            Text(asset.note!, style: const TextStyle(fontSize: 13.5, height: 1.5)),
          ],

          // Banner Jadwal Service Mendatang
          if (nextService != null && nextService.nextDueAt != null) ...[
            const SizedBox(height: 16),
            _UpcomingServiceCard(maintenance: nextService),
          ],

          // Riwayat Valuasi
          SectionHeader(
            title: 'Riwayat Nilai Aset',
            action: TextButton.icon(
              onPressed: () => _addValuation(context, ref, asset),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Valuasi'),
            ),
          ),
          if (valuations.isEmpty)
            Text(
              'Belum ada riwayat valuasi.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            )
          else
            Card(
              child: Column(
                children: [
                  for (var i = 0; i < valuations.length; i++) ...[
                    if (i > 0) const Divider(height: 1, indent: 20),
                    ListTile(
                      dense: true,
                      title: MoneyText(valuations[i].value, fontSize: 14, bold: true),
                      subtitle: Text(
                        '${formatDate(valuations[i].valuedAt)} · ${valuations[i].source == 'MANUAL' ? 'Manual' : 'Penyusutan'}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: i == 0
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Terkini',
                                style: TextStyle(fontSize: 9, color: theme.colorScheme.primary),
                              ),
                            )
                          : null,
                    ),
                  ],
                ],
              ),
            ),

          // Riwayat & Input Perawatan / Service
          SectionHeader(
            title: 'Riwayat & Jadwal Perawatan',
            action: TextButton.icon(
              onPressed: () => _addMaintenance(context, ref, asset),
              icon: const Icon(Icons.build_circle_outlined, size: 16),
              label: const Text('Input Service'),
            ),
          ),
          if (maintenances.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(Icons.build_outlined, size: 36, color: theme.colorScheme.outline),
                    const SizedBox(height: 8),
                    const Text(
                      'Belum ada riwayat service',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Catat jadwal perawatan berkala, biaya teknisi, atau perbaikan aset.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed: () => _addMaintenance(context, ref, asset),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Input Service Pertama'),
                    ),
                  ],
                ),
              ),
            )
          else
            Card(
              child: Column(
                children: [
                  for (var i = 0; i < maintenances.length; i++) ...[
                    if (i > 0) const Divider(height: 1, indent: 20),
                    ListTile(
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
                        child: Icon(Icons.build_outlined, size: 16, color: theme.colorScheme.primary),
                      ),
                      title: Text(maintenances[i].title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 2),
                          Text(
                            'Dilakukan: ${formatDate(maintenances[i].performedAt)}'
                            '${maintenances[i].note?.isNotEmpty == true ? ' · ${maintenances[i].note}' : ''}',
                            style: const TextStyle(fontSize: 11.5),
                          ),
                          if (maintenances[i].nextDueAt != null) ...[
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Icon(Icons.schedule, size: 12, color: theme.colorScheme.tertiary),
                                const SizedBox(width: 4),
                                Text(
                                  'Jadwal berikutnya: ${formatDate(maintenances[i].nextDueAt!)}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.tertiary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          MoneyText(maintenances[i].cost, fontSize: 13, bold: true),
                          const Text('Biaya', style: TextStyle(fontSize: 9.5, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _addValuation(BuildContext context, WidgetRef ref, Asset asset) async {
    final controller = TextEditingController(text: formatNumber(asset.currentValue));
    var date = DateTime.now();

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Valuasi baru'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nilai (Rp)'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setState(() => date = picked);
                },
                icon: const Icon(Icons.event_outlined, size: 16),
                label: Text(formatDate(date)),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
            FilledButton(
              onPressed: () async {
                final value = parseMoney(controller.text);
                if (value > 0) {
                  await ref.read(databaseProvider).addValuation(
                        workspaceId: asset.workspaceId,
                        assetId: asset.id,
                        value: value,
                        valuedAt: date,
                      );
                  ref.read(syncSchedulerProvider).schedule();
                }
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addMaintenance(BuildContext context, WidgetRef ref, Asset asset) async {
    final title = TextEditingController();
    final vendor = TextEditingController();
    final cost = TextEditingController();

    var date = DateTime.now();
    DateTime? nextDueDate;
    bool createExpense = true;
    String? selectedWalletId;

    final wallets = ref.read(walletsProvider).valueOrNull ?? const <Wallet>[];
    if (wallets.isNotEmpty) {
      selectedWalletId = wallets.first.id;
    }

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Input Service / Perawatan'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: title,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Jenis Perawatan / Service *',
                    hintText: 'Mis: Service Berkala, Ganti Oli, AC',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: vendor,
                  decoration: const InputDecoration(
                    labelText: 'Bengkel / Spesialis / Profesional (opsional)',
                    hintText: 'Mis: Bengkel Resmi Toyota, Teknisi AC',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: cost,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Biaya Service (Rp)',
                    hintText: '0',
                  ),
                  onChanged: (val) {
                    final formatted = formatMoneyInput(val);
                    if (formatted != val) {
                      cost.value = TextEditingValue(
                        text: formatted,
                        selection: TextSelection.collapsed(offset: formatted.length),
                      );
                    }
                    setState(() {});
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Tanggal Service', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          OutlinedButton.icon(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: date,
                                firstDate: DateTime(2000),
                                lastDate: DateTime.now().add(const Duration(days: 365)),
                              );
                              if (picked != null) setState(() => date = picked);
                            },
                            icon: const Icon(Icons.event_outlined, size: 14),
                            label: Text(formatDate(date), style: const TextStyle(fontSize: 11.5)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Jadwal Service Berikutnya (opsional)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: nextDueDate ?? date.add(const Duration(days: 180)),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 3650)),
                        );
                        if (picked != null) setState(() => nextDueDate = picked);
                      },
                      icon: const Icon(Icons.schedule, size: 14),
                      label: Text(
                        nextDueDate == null ? 'Set Jadwal Mendatang' : formatDate(nextDueDate!),
                        style: const TextStyle(fontSize: 11.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Catat Pengeluaran di Keuangan', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Otomatis mengurangi saldo dompet', style: TextStyle(fontSize: 10.5)),
                  value: createExpense,
                  onChanged: (val) => setState(() => createExpense = val),
                ),
                if (createExpense && wallets.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  const Text('Pilih Dompet Pengeluaran:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final w in wallets)
                        ChoiceChip(
                          selected: selectedWalletId == w.id,
                          onSelected: (_) => setState(() => selectedWalletId = w.id),
                          label: Text(w.name, style: const TextStyle(fontSize: 11)),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
            FilledButton(
              onPressed: () async {
                final serviceTitle = title.text.trim();
                if (serviceTitle.isEmpty) return;

                final c = parseMoney(cost.text);
                final db = ref.read(databaseProvider);
                final noteText = vendor.text.trim();

                await db.addMaintenance(
                  workspaceId: asset.workspaceId,
                  assetId: asset.id,
                  title: serviceTitle,
                  cost: c,
                  performedAt: date,
                  nextDueAt: nextDueDate,
                  note: noteText.isNotEmpty ? noteText : null,
                );

                if (createExpense && c > 0 && selectedWalletId != null) {
                  final now = DateTime.now();
                  final categories = await db.listCategories(asset.workspaceId, kind: 'EXPENSE');
                  final categoryId = categories.isNotEmpty ? categories.first.id : null;

                  await db.saveTransaction(TransactionsCompanion.insert(
                    id: newId(),
                    workspaceId: asset.workspaceId,
                    walletId: selectedWalletId!,
                    categoryId: Value(categoryId),
                    type: 'EXPENSE',
                    amount: c,
                    occurredAt: date,
                    note: Value('Service Aset (${asset.name}): $serviceTitle'),
                    payee: Value(noteText.isNotEmpty ? noteText : 'Service Profesional'),
                    createdAt: now,
                    updatedAt: now,
                    deviceId: '',
                  ));
                }

                ref.read(syncSchedulerProvider).schedule();
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Simpan Service'),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpcomingServiceCard extends StatelessWidget {
  const _UpcomingServiceCard({required this.maintenance});

  final AssetMaintenance maintenance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final due = maintenance.nextDueAt!;
    final now = DateTime.now();
    final diffDays = due.difference(DateTime(now.year, now.month, now.day)).inDays;

    String statusText;
    Color statusColor;

    if (diffDays < 0) {
      statusText = 'Terlewat ${diffDays.abs()} hari';
      statusColor = Colors.red.shade700;
    } else if (diffDays == 0) {
      statusText = 'Jadwal Hari Ini';
      statusColor = Colors.orange.shade800;
    } else {
      statusText = '$diffDays hari lagi';
      statusColor = theme.colorScheme.primary;
    }

    return Card(
      color: statusColor.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.build_circle_outlined, color: statusColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Jadwal Service Mendatang',
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: statusColor),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    maintenance.title,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Jadwal: ${formatDate(due)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                statusText,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}

List<String> _parsePhotos(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List) return decoded.map((e) => e.toString()).toList();
  } catch (_) {}
  return [raw];
}

void _showAssetPhotoDialog(BuildContext context, String item) {
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

class _LinkedDebtCard extends StatelessWidget {
  const _LinkedDebtCard({required this.debt, required this.assetValue});

  final Debt debt;
  final int assetValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final netEquity = assetValue - debt.remaining;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.orange.shade700.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade700.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.account_balance_outlined, color: Colors.orange.shade800, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Informasi Angsuran / Pembiayaan Aktif',
                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.orange.shade800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        debt.counterparty,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (debt.remaining <= 0 ? const Color(0xFF059669) : Colors.orange.shade800).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    debt.remaining <= 0 ? 'Lunas' : 'Ada Angsuran',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: debt.remaining <= 0 ? const Color(0xFF059669) : Colors.orange.shade800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Sisa Pokok Angsuran', style: TextStyle(fontSize: 10.5, color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 2),
                    Text(formatMoney(debt.remaining), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kExpense)),
                  ],
                ),
                if (debt.monthlyInstallment != null && debt.monthlyInstallment! > 0)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Cicilan Bulanan', style: TextStyle(fontSize: 10.5, color: theme.colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 2),
                      Text('${formatMoney(debt.monthlyInstallment!)}/bln', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: theme.colorScheme.primary)),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ekuitas Bersih Aset (Net Worth)', style: TextStyle(fontSize: 10.5, color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 2),
                    Text(
                      formatMoney(netEquity),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: netEquity >= 0 ? const Color(0xFF059669) : kExpense,
                      ),
                    ),
                  ],
                ),
                if (debt.dueAt != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Jatuh Tempo', style: TextStyle(fontSize: 10.5, color: theme.colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 2),
                      Text(formatDate(debt.dueAt!), style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DepreciationCard extends StatelessWidget {
  const _DepreciationCard({required this.asset});

  final Asset asset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final purchasePrice = asset.purchasePrice!;
    final purchaseDate = asset.purchaseAt!;
    final now = DateTime.now();

    final yearsUsed = (now.difference(purchaseDate).inDays / 365.0).clamp(0.0, 50.0);
    final int usefulLifeYears = (asset.category == 'VEHICLE' ? 8 : (asset.category == 'ELECTRONICS' ? 4 : 10));
    final annualDepreciation = purchasePrice / usefulLifeYears;
    final accumulatedDepreciation = (annualDepreciation * yearsUsed).clamp(0.0, purchasePrice.toDouble()).toInt();
    final calculatedBookValue = (purchasePrice - accumulatedDepreciation).clamp(0, purchasePrice);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.trending_down_rounded, color: Colors.orange.shade800, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Estimasi Penyusutan Nilai Aset (Depresiasi)',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.orange.shade800),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Akumulasi Penyusutan', style: TextStyle(fontSize: 10.5, color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 2),
                    Text('-${formatMoney(accumulatedDepreciation)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kExpense)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Nilai Buku Terhitung', style: TextStyle(fontSize: 10.5, color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 2),
                    Text(formatMoney(calculatedBookValue), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: theme.colorScheme.primary)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Metode garis lurus (Straight-Line) estimasi usia manfaat $usefulLifeYears tahun · terpakai ${yearsUsed.toStringAsFixed(1)} tahun.',
              style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
