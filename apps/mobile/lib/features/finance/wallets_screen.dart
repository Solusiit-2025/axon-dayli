import 'package:collection/collection.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/local/database.dart';
import '../common/widgets.dart';
import 'transaction_editor.dart';

class WalletsScreen extends ConsumerWidget {
  const WalletsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final balances = ref.watch(walletBalancesProvider).valueOrNull ?? const <WalletBalance>[];
    final wallets = ref.watch(walletsProvider).valueOrNull ?? const <Wallet>[];

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Dompet'),
        actions: [
          IconButton(
            onPressed: () => _showEditor(context, ref),
            icon: const Icon(Icons.add),
            tooltip: 'Tambah dompet',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (wallets.isEmpty)
            const EmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Belum ada dompet',
              message: 'Tambahkan dompet tunai, bank, atau e-wallet.',
            )
          else ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: () => showTransactionEditor(context, ref, initialType: 'TRANSFER'),
                icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                label: const Text('Transfer Saldo Antar Dompet', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  for (var i = 0; i < wallets.length; i++) ...[
                    if (i > 0) const Divider(height: 1, indent: 56),
                    Consumer(
                      builder: (context, ref, _) {
                        final balance = balances
                            .where((b) => b.walletId == wallets[i].id)
                            .map((b) => b.balance)
                            .firstOrNull;
                        return ListTile(
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
                            child: Icon(
                              _iconFor(wallets[i].type),
                              size: 17,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          title: Text(
                            wallets[i].name,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(_typeLabel(wallets[i].type), style: const TextStyle(fontSize: 11)),
                          trailing: MoneyText(balance ?? wallets[i].initialBalance, fontSize: 14, bold: true),
                          onTap: () => _showEditor(context, ref, wallet: wallets[i]),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'Saldo dihitung otomatis dari transaksi. Untuk mengoreksi, buat transaksi penyesuaian.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  static IconData _iconFor(String type) {
    switch (type) {
      case 'BANK':
        return Icons.account_balance_outlined;
      case 'EWALLET':
        return Icons.smartphone_outlined;
      case 'CREDIT':
        return Icons.credit_card_outlined;
      default:
        return Icons.payments_outlined;
    }
  }

  static String _typeLabel(String type) {
    switch (type) {
      case 'BANK':
        return 'Rekening bank';
      case 'EWALLET':
        return 'E-wallet';
      case 'CREDIT':
        return 'Kartu kredit';
      default:
        return 'Tunai';
    }
  }

  Future<void> _showEditor(BuildContext context, WidgetRef ref, {Wallet? wallet}) async {
    final name = TextEditingController(text: wallet?.name ?? '');
    final initial = TextEditingController(
      text: wallet == null ? '' : formatNumber(wallet.initialBalance),
    );
    var type = wallet?.type ?? 'CASH';
    final workspace = ref.read(currentWorkspaceProvider);
    if (workspace == null) return;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(wallet == null ? 'Dompet baru' : 'Ubah dompet'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: wallet == null,
                decoration: const InputDecoration(labelText: 'Nama dompet'),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final t in const {'CASH': 'Tunai', 'BANK': 'Bank', 'EWALLET': 'E-wallet', 'CREDIT': 'Kartu'}.entries)
                    ChoiceChip(
                      selected: type == t.key,
                      onSelected: (_) => setState(() => type = t.key),
                      label: Text(t.value),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: initial,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Saldo awal (Rp)'),
              ),
            ],
          ),
          actions: [
            if (wallet != null)
              TextButton(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Hapus Dompet?'),
                      content: Text('Apakah Anda yakin ingin menghapus dompet "${wallet.name}"? Transaksi pada dompet ini akan tetap tersimpan.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: kDanger),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Hapus Dompet'),
                        ),
                      ],
                    ),
                  );

                  if (confirm == true) {
                    await ref.read(databaseProvider).deleteWallet(wallet.id);
                    ref.read(syncSchedulerProvider).schedule();
                    if (context.mounted) {
                      Navigator.pop(context);
                      showAppSnack(context, 'Dompet "${wallet.name}" berhasil dihapus');
                    }
                  }
                },
                child: Text('Hapus', style: TextStyle(color: kDanger)),
              ),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
            FilledButton(
              onPressed: () async {
                if (name.text.trim().isEmpty) return;
                final db = ref.read(databaseProvider);
                final now = DateTime.now();
                if (wallet == null) {
                  await db.saveWallet(WalletsCompanion.insert(
                    id: newId(),
                    workspaceId: workspace.id,
                    name: name.text.trim(),
                    type: Value(type),
                    initialBalance: Value(parseMoney(initial.text)),
                    createdAt: now,
                    updatedAt: now,
                    deviceId: '',
                  ));
                } else {
                  await db.saveWallet(WalletsCompanion(
                    id: Value(wallet.id),
                    name: Value(name.text.trim()),
                    type: Value(type),
                    initialBalance: Value(parseMoney(initial.text)),
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
