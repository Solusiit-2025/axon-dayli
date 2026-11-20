import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/local/database.dart';
import '../common/widgets.dart';
import 'transaction_editor.dart';

class FinanceScreen extends ConsumerWidget {
  const FinanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final month = ref.watch(selectedMonthProvider);
    final summary = ref.watch(monthlySummaryProvider).valueOrNull;
    final balances = ref.watch(walletBalancesProvider).valueOrNull ?? const <WalletBalance>[];
    final transactions = ref.watch(transactionsProvider).valueOrNull ?? const <Txn>[];
    final byCategory = ref.watch(expenseByCategoryProvider).valueOrNull ?? const <String, int>{};
    final categories = ref.watch(categoriesProvider('ALL')).valueOrNull ?? const <Category>[];

    final total = balances.fold<int>(0, (s, b) => s + b.balance);
    final categoryMap = {for (final c in categories) c.id: c};

    String categoryName(String? id) => id == null ? 'Tanpa kategori' : (categoryMap[id]?.name ?? 'Tanpa kategori');

    final grouped = <String, List<Txn>>{};
    for (final t in transactions) {
      final key = formatDate(t.occurredAt);
      grouped.putIfAbsent(key, () => []).add(t);
    }

    final topCategories = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        // Pemilih bulan
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              IconButton(
                onPressed: () => ref.read(selectedMonthProvider.notifier).state =
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
                onPressed: () => ref.read(selectedMonthProvider.notifier).state =
                    DateTime(month.year, month.month + 1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),

        // Kartu saldo
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Total saldo',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => context.push('/wallets'),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Dompet', style: TextStyle(fontSize: 11.5)),
                      ),
                      const SizedBox(width: 4),
                      TextButton(
                        onPressed: () => context.push('/planning'),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Anggaran', style: TextStyle(fontSize: 11.5)),
                      ),
                      const SizedBox(width: 4),
                      TextButton(
                        onPressed: () => context.push('/reports'),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Laporan', style: TextStyle(fontSize: 11.5)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatMoney(total),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.8),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _MiniStat(
                          label: 'Masuk',
                          value: formatCompactMoney(summary?.income ?? 0),
                          color: kIncome,
                          icon: Icons.north_east,
                        ),
                      ),
                      Container(width: 1, height: 32, color: theme.dividerColor),
                      Expanded(
                        child: _MiniStat(
                          label: 'Keluar',
                          value: formatCompactMoney(summary?.expense ?? 0),
                          color: kExpense,
                          icon: Icons.south_west,
                        ),
                      ),
                      Container(width: 1, height: 32, color: theme.dividerColor),
                      Expanded(
                        child: _MiniStat(
                          label: 'Selisih',
                          value: formatCompactMoney(summary?.net ?? 0),
                          color: (summary?.net ?? 0) >= 0 ? kIncome : kExpense,
                          icon: Icons.balance,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),

        // Dompet horizontal
        if (balances.isNotEmpty) ...[
          const SizedBox(height: 4),
          SizedBox(
            height: 74,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                for (final b in balances)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          b.name,
                          style: TextStyle(fontSize: 10.5, color: theme.colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          formatCompactMoney(b.balance),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],

        // Breakdown kategori
        if (topCategories.isNotEmpty) ...[
          const SectionHeader(title: 'Ke mana uang pergi'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    SizedBox(
                      width: 110,
                      height: 110,
                      child: PieChart(
                        PieChartData(
                          sectionsSpace: 2,
                          centerSpaceRadius: 30,
                          sections: _sections(topCategories, byCategory, categoryMap),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final entry in topCategories.take(4))
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: _colorFor(entry.key, categoryMap),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      categoryName(entry.key == 'uncategorized' ? null : entry.key),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11.5),
                                    ),
                                  ),
                                  Text(
                                    formatCompactMoney(entry.value),
                                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],

        // Kartu perencanaan & hutang (tautan ke modul Anggaran)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => context.push('/planning'),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.savings_outlined, size: 18, color: theme.colorScheme.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Anggaran & Utang', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(
                            'Pantau batas pengeluaran per kategori dan posisi utang/piutang.',
                            style: theme.textTheme.bodySmall?.copyWith(fontSize: 10.5, color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, size: 18),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),

        SectionHeader(
          title: 'Transaksi',
          action: TextButton.icon(
            onPressed: () => showTransactionEditor(context, ref),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Catat'),
          ),
        ),

        if (transactions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              child: EmptyState(
                icon: Icons.account_balance_wallet_outlined,
                title: 'Belum ada transaksi bulan ini',
                message: 'Catat pemasukan atau pengeluaran pertama.',
                action: FilledButton.tonal(
                  onPressed: () => showTransactionEditor(context, ref),
                  child: const Text('Catat transaksi'),
                ),
              ),
            ),
          )
        else
          for (final entry in grouped.entries)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
                  child: Text(
                    entry.key,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Card(
                    child: Column(
                      children: [
                        for (var i = 0; i < entry.value.length; i++) ...[
                          if (i > 0) const Divider(height: 1, indent: 56),
                          ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundColor: (entry.value[i].type == 'INCOME' ? kIncome : kExpense)
                                  .withValues(alpha: 0.12),
                              child: Icon(
                                entry.value[i].type == 'INCOME' ? Icons.north_east : Icons.south_west,
                                size: 14,
                                color: entry.value[i].type == 'INCOME' ? kIncome : kExpense,
                              ),
                            ),
                            title: Text(
                              categoryName(entry.value[i].categoryId),
                              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                            ),
                            subtitle: Row(
                              children: [
                                if (entry.value[i].attachmentId != null && entry.value[i].attachmentId!.isNotEmpty) ...[
                                  const Icon(Icons.attach_file, size: 12, color: Colors.indigoAccent),
                                  const SizedBox(width: 3),
                                ],
                                Expanded(
                                  child: Text(
                                    entry.value[i].note?.isNotEmpty == true
                                        ? entry.value[i].note!
                                        : (entry.value[i].payee ?? ''),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                MoneyText(
                                  entry.value[i].type == 'INCOME'
                                      ? entry.value[i].amount
                                      : -entry.value[i].amount,
                                  fontSize: 13,
                                  bold: true,
                                  color: entry.value[i].type == 'INCOME' ? kIncome : null,
                                ),
                                const SizedBox(width: 6),
                                Icon(Icons.edit_outlined, size: 14, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                              ],
                            ),
                            onTap: () => showTransactionEditor(context, ref, existing: entry.value[i]),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
      ],
    );
  }

  List<PieChartSectionData> _sections(
    List<MapEntry<String, int>> entries,
    Map<String, int> byCategory,
    Map<String, Category> categoryMap,
  ) {
    final top = entries.take(5).toList();
    final rest = entries.skip(5).fold<int>(0, (s, e) => s + e.value);

    return [
      for (final entry in top)
        PieChartSectionData(
          value: entry.value.toDouble(),
          color: _colorFor(entry.key, categoryMap),
          radius: 28,
          showTitle: false,
        ),
      if (rest > 0)
        PieChartSectionData(
          value: rest.toDouble(),
          color: const Color(0xFF94A3B8),
          radius: 28,
          showTitle: false,
        ),
    ];
  }

  Color _colorFor(String categoryId, Map<String, Category> categoryMap) {
    final hex = categoryMap[categoryId]?.color;
    if (hex == null) return const Color(0xFF94A3B8);
    final value = int.tryParse(hex.replaceAll('#', ''), radix: 16) ?? 0x94A3B8;
    return Color(0xFF000000 | value);
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color),
          ),
        ),
      ],
    );
  }
}
