import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/local/database.dart';
import '../common/widgets.dart';

/// Laporan Keuangan Lengkap & Analisis Otomatis Eksekutif.
class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final month = ref.watch(selectedMonthProvider);
    final summary = ref.watch(monthlySummaryProvider).valueOrNull;
    final balances = ref.watch(walletBalancesProvider).valueOrNull ?? const <WalletBalance>[];
    final transactions = ref.watch(transactionsProvider).valueOrNull ?? const <Txn>[];
    final byCategory = ref.watch(expenseByCategoryProvider).valueOrNull ?? const <String, int>{};
    final categories = ref.watch(categoriesProvider('ALL')).valueOrNull ?? const <Category>[];
    final budgets = ref.watch(budgetsProvider).valueOrNull ?? const <Budget>[];
    final spentMap = ref.watch(expenseByCategoryProvider).valueOrNull ?? const <String, int>{};
    final debts = ref.watch(debtsProvider).valueOrNull ?? const <Debt>[];
    final trend = ref.watch(sixMonthTransactionsProvider).valueOrNull ?? const <Txn>[];

    final categoryMap = {for (final c in categories) c.id: c};
    final totalBalance = balances.fold<int>(0, (s, b) => s + b.balance);
    final income = summary?.income ?? 0;
    final expense = summary?.expense ?? 0;
    final net = summary?.net ?? 0;
    final savingsRate = income <= 0 ? 0.0 : (income - expense) / income;

    // Trend bulanan (6 bulan terakhir)
    final monthly = <String, _MonthAgg>{};
    for (final t in trend) {
      final key = '${t.occurredAt.year}-${t.occurredAt.month.toString().padLeft(2, '0')}';
      monthly.putIfAbsent(key, () => _MonthAgg());
      if (t.type == 'INCOME') monthly[key]!.income += t.amount;
      if (t.type == 'EXPENSE') monthly[key]!.expense += t.amount;
    }
    final trendKeys = monthly.keys.toList()..sort();
    final maxTrend = trendKeys.fold<int>(
        0, (m, k) => [m, monthly[k]!.income, monthly[k]!.expense].reduce((a, b) => a > b ? a : b));

    // Top kategori pengeluaran
    final topExpense = byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final totalExpenseCat = byCategory.values.fold<int>(0, (s, v) => s + v);

    // Anggaran vs realisasi
    final overBudget = budgets.where((b) => (spentMap[b.categoryId] ?? 0) > b.amount).toList();

    // Utang/piutang
    final openDebts = debts.where((d) => d.remaining > 0).toList();
    final receivable = openDebts.where((d) => d.direction == 'RECEIVABLE').fold<int>(0, (s, d) => s + d.remaining);
    final payable = openDebts.where((d) => d.direction == 'PAYABLE').fold<int>(0, (s, d) => s + d.remaining);
    final overdueDebts = openDebts.where((d) => d.dueAt != null && d.dueAt!.isBefore(DateTime.now())).toList();

    // Insights Otomatis
    final insights = _buildInsights(
      income: income,
      expense: expense,
      net: net,
      savingsRate: savingsRate,
      month: month,
      trend: monthly,
      trendKeys: trendKeys,
      topExpense: topExpense,
      totalExpenseCat: totalExpenseCat,
      categoryMap: categoryMap,
      overBudget: overBudget,
      overdueDebts: overdueDebts,
      totalBalance: totalBalance,
    );

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Laporan Keuangan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined, size: 20),
            tooltip: 'Ekspor Laporan Keuangan',
            onPressed: () => _exportFinancialReport(
              context,
              ref,
              month,
              income,
              expense,
              net,
              totalBalance,
              transactions,
              byCategory,
              categoryMap,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            tooltip: 'Segarkan',
            onPressed: () => ref.read(syncSchedulerProvider).now(),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          // Pemilih Bulan Modern
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => ref.read(selectedMonthProvider.notifier).state =
                        DateTime(month.year, month.month - 1),
                    icon: const Icon(Icons.chevron_left_rounded, size: 22),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          formatMonthYear(month),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: -0.3),
                        ),
                        Text(
                          '${transactions.length} Transaksi Tercatat Bulan Ini',
                          style: TextStyle(fontSize: 10.5, color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => ref.read(selectedMonthProvider.notifier).state =
                        DateTime(month.year, month.month + 1),
                    icon: const Icon(Icons.chevron_right_rounded, size: 22),
                  ),
                ],
              ),
            ),
          ),

          // 1. HERO FINANCIAL HEALTH CARD (Kartu Utama Kesehatan Keuangan)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: theme.dividerColor),
              ),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
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
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: (net >= 0 ? kIncome : kExpense).withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                net >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                                size: 18,
                                color: net >= 0 ? kIncome : kExpense,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Arus Kas Bersih',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: (savingsRate >= 0.2
                                    ? const Color(0xFF059669)
                                    : savingsRate >= 0
                                        ? const Color(0xFFD97706)
                                        : kDanger)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            savingsRate >= 0
                                ? '${(savingsRate * 100).round()}% Tabungan'
                                : 'Defisit',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: savingsRate >= 0.2
                                  ? const Color(0xFF059669)
                                  : savingsRate >= 0
                                      ? const Color(0xFFD97706)
                                      : kDanger,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      formatMoney(net),
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1,
                        color: net >= 0 ? theme.colorScheme.onSurface : kDanger,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 14),

                    // Grid Cashflow: Pemasukan vs Pengeluaran
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.arrow_downward_rounded, size: 14, color: kIncome),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Pemasukan',
                                    style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                formatMoney(income),
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: kIncome),
                              ),
                            ],
                          ),
                        ),
                        Container(width: 1, height: 32, color: theme.dividerColor),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.arrow_upward_rounded, size: 14, color: kExpense),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Pengeluaran',
                                    style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                formatMoney(expense),
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: kExpense),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 2. INSIGHTS AI ANALISIS PINTAR (Jika ada)
          if (insights.isNotEmpty) ...[
            const SectionHeader(title: 'Analisis & Rekomendasi Pintar'),
            for (final ins in insights)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: ins.color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: ins.color.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: ins.color.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(ins.icon, color: ins.color, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ins.title,
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ins.color),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              ins.detail,
                              style: TextStyle(fontSize: 11.5, color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],

          // 3. TREN ARUS KAS 6 BULAN (Grafik Bar Modern)
          if (trendKeys.isNotEmpty) ...[
            const SectionHeader(title: 'Tren Arus Kas 6 Bulan Terakhir'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 190,
                        child: BarChart(
                          BarChartData(
                            alignment: BarChartAlignment.spaceAround,
                            maxY: (maxTrend * 1.25).toDouble().clamp(100.0, double.infinity),
                            barTouchData: BarTouchData(
                              enabled: true,
                              touchTooltipData: BarTouchTooltipData(
                                getTooltipColor: (group) => theme.colorScheme.surfaceContainerHighest,
                                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                  final isInc = rodIndex == 0;
                                  return BarTooltipItem(
                                    '${isInc ? 'Masuk' : 'Keluar'}\n${formatMoney(rod.toY.toInt())}',
                                    TextStyle(
                                      color: isInc ? kIncome : kExpense,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11,
                                    ),
                                  );
                                },
                              ),
                            ),
                            titlesData: FlTitlesData(
                              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  getTitlesWidget: (value, meta) {
                                    final i = value.toInt();
                                    if (i < 0 || i >= trendKeys.length) return const SizedBox.shrink();
                                    final parts = trendKeys[i].split('-');
                                    final mName = _monthAbbr(int.parse(parts[1]));
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(
                                        '$mName ${parts[0].substring(2)}',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: theme.colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                            gridData: const FlGridData(show: false),
                            borderData: FlBorderData(show: false),
                            barGroups: [
                              for (var i = 0; i < trendKeys.length; i++)
                                BarChartGroupData(
                                  x: i,
                                  barRods: [
                                    BarChartRodData(
                                      toY: monthly[trendKeys[i]]!.income.toDouble(),
                                      color: kIncome,
                                      width: 10,
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                                    ),
                                    BarChartRodData(
                                      toY: monthly[trendKeys[i]]!.expense.toDouble(),
                                      color: kExpense,
                                      width: 10,
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _legendDot(kIncome, 'Pemasukan'),
                          const SizedBox(width: 20),
                          _legendDot(kExpense, 'Pengeluaran'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],

          // 4. DISTRIBUSI PENGELUARAN PER KATEGORI (Donut Chart & List)
          if (topExpense.isNotEmpty) ...[
            const SectionHeader(title: 'Distribusi Pengeluaran Per Kategori'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 150,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            PieChart(
                              PieChartData(
                                sectionsSpace: 3,
                                centerSpaceRadius: 42,
                                sections: [
                                  for (final e in topExpense.take(6))
                                    PieChartSectionData(
                                      value: e.value.toDouble(),
                                      color: _colorFor(e.key, categoryMap),
                                      radius: 22,
                                      showTitle: false,
                                    ),
                                  if (topExpense.length > 6)
                                    PieChartSectionData(
                                      value: topExpense.skip(6).fold<int>(0, (s, e) => s + e.value).toDouble(),
                                      color: const Color(0xFF94A3B8),
                                      radius: 22,
                                      showTitle: false,
                                    ),
                                ],
                              ),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Total',
                                  style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
                                ),
                                Text(
                                  formatCompactMoney(totalExpenseCat),
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      for (final e in topExpense.take(8)) ...[
                        _CategoryExpenseRow(
                          name: e.key == 'uncategorized' ? 'Tanpa kategori' : (categoryMap[e.key]?.name ?? 'Kategori'),
                          amount: e.value,
                          percent: totalExpenseCat == 0 ? 0 : (e.value / totalExpenseCat * 100).round(),
                          color: _colorFor(e.key, categoryMap),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],

          // 5. SALDO PER DOMPET & ANGGARAN
          if (balances.isNotEmpty) ...[
            const SectionHeader(title: 'Rincian Saldo Per Dompet'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      for (final b in balances)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
                                child: Icon(Icons.account_balance_wallet_outlined, size: 14, color: theme.colorScheme.primary),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(b.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              ),
                              Text(
                                formatMoney(b.balance),
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      const Divider(height: 16),
                      Row(
                        children: [
                          const Expanded(
                            child: Text('Total Saldo Tersedia', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                          ),
                          Text(
                            formatMoney(totalBalance),
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: theme.colorScheme.primary),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],

          // 6. POSISI UTANG & PIUTANG RINGKAS
          const SectionHeader(title: 'Ringkasan Utang & Piutang'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _kvRow('Total Piutang (Tagihan ke Orang)', formatMoney(receivable), kIncome),
                    const SizedBox(height: 6),
                    _kvRow('Total Utang / KPR / Angsuran', formatMoney(payable), kExpense),
                    const Divider(height: 16),
                    _kvRow('Posisi Bersih Kewajiban', formatMoney(receivable - payable), receivable - payable >= 0 ? kIncome : kExpense, bold: true),
                    if (overdueDebts.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: kDanger.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, size: 14, color: kDanger),
                            const SizedBox(width: 6),
                            Text(
                              'Ada ${overdueDebts.length} catatan utang jatuh tempo terlewat',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kDanger),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _kvRow(String label, String value, Color? color, {bool bold = false}) {
    return Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 12.5))),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Color _colorFor(String categoryId, Map<String, Category> categoryMap) {
    final hex = categoryMap[categoryId]?.color;
    if (hex == null) return const Color(0xFF94A3B8);
    final value = int.tryParse(hex.replaceAll('#', ''), radix: 16) ?? 0x94A3B8;
    return Color(0xFF000000 | value);
  }

  String _monthAbbr(int m) {
    const names = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
    if (m >= 1 && m <= 12) return names[m - 1];
    return '';
  }

  Future<void> _exportFinancialReport(
    BuildContext context,
    WidgetRef ref,
    DateTime month,
    int income,
    int expense,
    int net,
    int totalBalance,
    List<Txn> transactions,
    Map<String, int> byCategory,
    Map<String, Category> categoryMap,
  ) async {
    final monthName = formatMonthYear(month);

    final sb = StringBuffer();
    sb.writeln('==========================================');
    sb.writeln('  LAPORAN KEUANGAN EKSEKUTIF - $monthName');
    sb.writeln('  Aplikasi: Axon Dayli Pilot');
    sb.writeln('  Tanggal Cetak: ${formatDateFull(DateTime.now())}');
    sb.writeln('==========================================\n');

    sb.writeln('--- RINGKASAN ARUS KAS ---');
    sb.writeln('Total Saldo Dompet : ${formatMoney(totalBalance)}');
    sb.writeln('Total Pemasukan    : ${formatMoney(income)}');
    sb.writeln('Total Pengeluaran  : ${formatMoney(expense)}');
    sb.writeln('Arus Kas Bersih    : ${formatMoney(net)}');
    sb.writeln('');

    sb.writeln('--- RINCIAN PENGELUARAN PER KATEGORI ---');
    if (byCategory.isEmpty) {
      sb.writeln('Belum ada pengeluaran tercatat.');
    } else {
      byCategory.forEach((catId, total) {
        final name = categoryMap[catId]?.name ?? 'Kategori Lain';
        sb.writeln('- $name: ${formatMoney(total)}');
      });
    }
    sb.writeln('');

    sb.writeln('--- TRANSAKSI BULAN INI (${transactions.length}) ---');
    for (final t in transactions) {
      final sign = t.type == 'INCOME' ? '+' : '-';
      final typeStr = t.type == 'INCOME' ? '[MASUK]' : (t.type == 'EXPENSE' ? '[KELUAR]' : '[TRANSFER]');
      sb.writeln('${formatDateShort(t.occurredAt)} $typeStr $sign${formatMoney(t.amount)} | ${t.payee ?? t.note ?? 'Transaksi'}');
    }
    sb.writeln('\n==========================================');

    final textReport = sb.toString();
    await Clipboard.setData(ClipboardData(text: textReport));

    if (context.mounted) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Laporan $monthName Disalin'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Ringkasan Laporan Keuangan Eksekutif Anda telah disalin ke Clipboard!'),
              const SizedBox(height: 12),
              const Text('Gunakan laporan ini untuk dibagikan ke akuntan atau disimpan sebagai arsip:'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                height: 140,
                child: SingleChildScrollView(
                  child: Text(textReport, style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace')),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: textReport));
                showAppSnack(ctx, 'Teks laporan disalin ke clipboard');
              },
              child: const Text('Salin Teks'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Selesai'),
            ),
          ],
        ),
      );
    }
  }
}

class _CategoryExpenseRow extends StatelessWidget {
  const _CategoryExpenseRow({
    required this.name,
    required this.amount,
    required this.percent,
    required this.color,
  });

  final String name;
  final int amount;
  final int percent;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Row(
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
            Text(formatMoney(amount), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('$percent%', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ProgressBar(value: percent / 100, color: color),
      ],
    );
  }
}

class _MonthAgg {
  int income = 0;
  int expense = 0;
}

List<_Insight> _buildInsights({
  required int income,
  required int expense,
  required int net,
  required double savingsRate,
  required DateTime month,
  required Map<String, _MonthAgg> trend,
  required List<String> trendKeys,
  required List<MapEntry<String, int>> topExpense,
  required int totalExpenseCat,
  required Map<String, Category> categoryMap,
  required List<Budget> overBudget,
  required List<Debt> overdueDebts,
  required int totalBalance,
}) {
  final insights = <_Insight>[];
  if (income > 0) {
    if (savingsRate >= 0.2) {
      insights.add(_Insight(Icons.check_circle_rounded, const Color(0xFF059669), 'Kesehatan Tabungan Sangat Baik', 'Anda berhasil menyisihkan ${(savingsRate * 100).round()}% dari total pemasukan bulan ini.'));
    } else if (savingsRate >= 0) {
      insights.add(_Insight(Icons.info_outline_rounded, const Color(0xFFD97706), 'Tabungan Masih Rendah', 'Hanya ${(savingsRate * 100).round()}% dari pemasukan tersisa. Target rekomendasi ideal adalah 20%.'));
    } else {
      insights.add(_Insight(Icons.warning_amber_rounded, kDanger, 'Kondisi Keuangan Defisit', 'Pengeluaran Anda melebihi pemasukan sebesar ${formatMoney(expense - income)}.'));
    }
  }
  if (trendKeys.length >= 2) {
    final prev = trend[trendKeys[trendKeys.length - 2]]!;
    final curr = trend[trendKeys.last]!;
    if (prev.expense > 0) {
      final change = (curr.expense - prev.expense) / prev.expense;
      if (change > 0.1) {
        insights.add(_Insight(Icons.trending_up_rounded, kDanger, 'Kenaikan Pengeluaran Signifikan', 'Pengeluaran naik ${(change * 100).round()}% dibanding bulan lalu. Harap tinjau pos pengeluaran terbesar.'));
      } else if (change < -0.1) {
        insights.add(_Insight(Icons.trending_down_rounded, const Color(0xFF059669), 'Efisiensi Pengeluaran', 'Pengeluaran berhasil ditekan turun ${(change.abs() * 100).round()}% dibanding bulan lalu.'));
      }
    }
  }
  if (overBudget.isNotEmpty) {
    insights.add(_Insight(Icons.warning_amber_rounded, kDanger, '${overBudget.length} Pos Anggaran Terlampaui', 'Terdapat kategori pengeluaran yang sudah melewati batas anggaran bulanan.'));
  }
  if (overdueDebts.isNotEmpty) {
    insights.add(_Insight(Icons.event_busy_rounded, kDanger, '${overdueDebts.length} Kewajiban Jatuh Tempo Terlewat', 'Segera lakukan pembayaran untuk menghentikan denda angsuran.'));
  }
  if (topExpense.isNotEmpty && totalExpenseCat > 0) {
    final top = topExpense.first;
    final share = top.value / totalExpenseCat;
    if (share >= 0.4) {
      insights.add(_Insight(Icons.pie_chart_outline_rounded, const Color(0xFFD97706), 'Pengeluaran Terpusat di Satu Kategori', 'Kategori "${categoryMap[top.key]?.name ?? 'Utama'}" menyerap ${(share * 100).round()}% dari total belanja bulan ini.'));
    }
  }
  if (totalBalance < 0) {
    insights.add(_Insight(Icons.warning_amber_rounded, kDanger, 'Saldo Dompet Negatif', 'Total gabungan saldo dompet bernilai minus.'));
  }
  return insights;
}

class _Insight {
  const _Insight(this.icon, this.color, this.title, this.detail);
  final IconData icon;
  final Color color;
  final String title;
  final String detail;
}
