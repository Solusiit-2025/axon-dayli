import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/local/database.dart';
import '../common/widgets.dart';
import '../finance/transaction_editor.dart';
import '../tasks/task_editor.dart';

/// Dashboard analisis untuk halaman "Hari Ini".
///
/// Menyajikan ringkasan produktivitas, arus kas, dan pengeluaran per kategori
/// dalam satu layar supaya pengguna langsung melihat kondisi harian & bulanan.
class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final allTasks = ref.watch(tasksProvider).valueOrNull ?? const <Task>[];
    final summary = ref.watch(monthlySummaryProvider).valueOrNull;
    final recent = ref.watch(recentTransactionsProvider).valueOrNull ?? const <Txn>[];
    final txns = ref.watch(transactionsProvider).valueOrNull ?? const <Txn>[];
    final balances = ref.watch(walletBalancesProvider).valueOrNull ?? const <WalletBalance>[];
    final assetTotal = ref.watch(assetTotalProvider);
    final expByCat = ref.watch(expenseByCategoryProvider).valueOrNull ?? const <String, int>{};
    final expCats = ref.watch(categoriesProvider('EXPENSE')).valueOrNull ?? const <Category>[];
    final auth = ref.watch(authControllerProvider);

    final active = allTasks.where((t) => t.status != 'DONE' && t.status != 'CANCELLED').toList();
    final done = allTasks.where((t) => t.status == 'DONE').toList();
    final doneToday = allTasks
        .where((t) => t.status == 'DONE' && t.completedAt != null && isToday(t.completedAt!))
        .toList();
    final overdue = active.where((t) => isOverdue(t.dueAt, status: t.status)).toList();
    final dueToday = active
        .where((t) => t.dueAt != null && isToday(t.dueAt!) && !isOverdue(t.dueAt, status: t.status))
        .toList();
    final noDue = active.where((t) => t.dueAt == null).toList();

    final completionRate = allTasks.isEmpty ? 0.0 : done.length / allTasks.length;
    final totalBalance = balances.fold<int>(0, (s, b) => s + b.balance);

    final catNames = {for (final c in expCats) c.id: c.name};
    final catColors = {for (final c in expCats) c.id: c.color};

    return RefreshIndicator(
      onRefresh: () async {
        final result = await ref.read(syncSchedulerProvider).now();
        if (context.mounted && !result.ok) showAppSnack(context, result.describe(), error: true);
      },
      child: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          _Header(name: auth.name?.split(' ').first ?? 'Bro'),

          // Produktivitas hari ini
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _ProductivityCard(
              rate: completionRate,
              doneToday: doneToday.length,
              active: active.length,
              overdue: overdue.length,
              onAdd: () => showTaskEditor(context, ref),
            ),
          ),

          const SizedBox(height: 12),

          // KPI keuangan & aset
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: StatCard(
                        label: 'Pemasukan',
                        value: formatCompactMoney(summary?.income ?? 0),
                        caption: 'Bulan ini',
                        icon: Icons.north_east_rounded,
                        color: kIncome,
                        onTap: () => context.go('/finance'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: StatCard(
                        label: 'Pengeluaran',
                        value: formatCompactMoney(summary?.expense ?? 0),
                        caption: 'Bulan ini',
                        icon: Icons.south_west_rounded,
                        color: kExpense,
                        onTap: () => context.go('/finance'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: StatCard(
                        label: 'Saldo',
                        value: formatCompactMoney(totalBalance),
                        caption: '${balances.length} dompet',
                        icon: Icons.account_balance_wallet_outlined,
                        color: theme.colorScheme.primary,
                        onTap: () => context.go('/finance'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: StatCard(
                        label: 'Nilai aset',
                        value: formatCompactMoney(assetTotal),
                        caption: 'Aset aktif',
                        icon: Icons.inventory_2_outlined,
                        color: const Color(0xFF8B5CF6),
                        onTap: () => context.go('/assets'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Arus kas 7 hari
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _CashflowCard(txns: txns),
          ),

          const SizedBox(height: 12),

          // Pengeluaran per kategori
          _CategoryBreakdown(
            expByCat: expByCat,
            catNames: catNames,
            catColors: catColors,
            onTap: () => context.go('/finance'),
          ),

          if (overdue.isNotEmpty) ...[
            const SectionHeader(title: 'Perlu perhatian'),
            for (final t in overdue.take(3))
              _TaskTile(task: t, overdue: true, onTap: () => context.push('/task/${t.id}')),
          ],

          SectionHeader(
            title: 'Agenda hari ini',
            action: TextButton.icon(
              onPressed: () => showTaskEditor(context, ref),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Tugas'),
            ),
          ),

          if (dueToday.isEmpty && noDue.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                child: EmptyState(
                  icon: Icons.wb_sunny_outlined,
                  title: 'Hari ini kosong',
                  message: 'Tidak ada tugas terjadwal. Nikmati harimu, atau tambahkan kegiatan baru.',
                  action: FilledButton.tonal(
                    onPressed: () => showTaskEditor(context, ref),
                    child: const Text('Tambah tugas'),
                  ),
                ),
              ),
            )
          else
            for (final t in [...dueToday, ...noDue].take(6))
              _TaskTile(task: t, onTap: () => context.push('/task/${t.id}')),

          SectionHeader(
            title: 'Transaksi terakhir',
            action: TextButton.icon(
              onPressed: () => showTransactionEditor(context, ref),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Catat'),
            ),
          ),

          if (recent.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                child: EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'Belum ada transaksi',
                  message: 'Catat pengeluaran pertama — cukup 3 ketukan.',
                  action: FilledButton.tonal(
                    onPressed: () => showTransactionEditor(context, ref),
                    child: const Text('Catat transaksi'),
                  ),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                child: Column(
                  children: [
                    for (var i = 0; i < recent.length; i++) ...[
                      if (i > 0) const Divider(height: 1, indent: 60),
                      _TransactionTile(
                        txn: recent[i],
                        categoryName: catNames[recent[i].categoryId] ?? 'Tanpa kategori',
                        onTap: () => showTransactionEditor(context, ref, existing: recent[i]),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ───────────────────────── Header ─────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hour = DateTime.now().hour;
    final greeting = hour < 11
        ? 'Selamat pagi'
        : hour < 15
            ? 'Selamat siang'
            : hour < 19
                ? 'Selamat sore'
                : 'Selamat malam';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$greeting, $name',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                ),
                const SizedBox(height: 2),
                Text(
                  formatDateFull(DateTime.now()),
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── Produktivitas ─────────────────────────

class _ProductivityCard extends StatelessWidget {
  const _ProductivityCard({
    required this.rate,
    required this.doneToday,
    required this.active,
    required this.overdue,
    required this.onAdd,
  });

  final double rate;
  final int doneToday;
  final int active;
  final int overdue;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Produktivitas',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                Text(
                  '${(rate * 100).round()}% selesai',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _Donut(value: rate, color: accent),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    children: [
                      _ProductivityStat(label: 'Selesai hari ini', value: '$doneToday', color: kIncome),
                      const SizedBox(height: 12),
                      _ProductivityStat(label: 'Tugas aktif', value: '$active', color: accent),
                      const SizedBox(height: 12),
                      _ProductivityStat(label: 'Terlambat', value: '$overdue', color: overdue > 0 ? kDanger : theme.colorScheme.outline),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_task, size: 18),
                label: const Text('Tambah tugas'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductivityStat extends StatelessWidget {
  const _ProductivityStat({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: -0.3),
        ),
      ],
    );
  }
}

class _Donut extends StatelessWidget {
  const _Donut({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 96,
      height: 96,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 96,
            height: 96,
            child: CircularProgressIndicator(
              value: value.clamp(0, 1),
              strokeWidth: 9,
              strokeCap: StrokeCap.round,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              color: color,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${(value * 100).round()}%',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5),
              ),
              Text(
                'selesai',
                style: TextStyle(fontSize: 10.5, color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── Arus kas 7 hari ─────────────────────────

class _CashflowCard extends StatelessWidget {
  const _CashflowCard({required this.txns});

  final List<Txn> txns;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = startOfDay(DateTime.now());

    final income = List<int>.filled(7, 0);
    final expense = List<int>.filled(7, 0);
    for (final t in txns) {
      final d = startOfDay(t.occurredAt);
      final diff = today.difference(d).inDays;
      if (diff < 0 || diff > 6) continue;
      final idx = 6 - diff;
      if (t.type == 'INCOME') {
        income[idx] += t.amount;
      } else if (t.type == 'EXPENSE') {
        expense[idx] += t.amount + t.fee;
      }
    }

    var maxVal = 0;
    for (var i = 0; i < 7; i++) {
      final v = income[i] + expense[i];
      if (v > maxVal) maxVal = v;
    }
    final labels = [
      for (var i = 0; i < 7; i++) _dayLabel(today.subtract(Duration(days: 6 - i))),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Arus kas 7 hari',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                _LegendDot(color: kIncome, label: 'Masuk'),
                const SizedBox(width: 10),
                _LegendDot(color: kExpense, label: 'Keluar'),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 110,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < 7; i++) ...[
                    Expanded(
                      child: _DayBars(
                        income: income[i],
                        expense: expense[i],
                        max: maxVal == 0 ? 1 : maxVal,
                        label: labels[i],
                      ),
                    ),
                    if (i < 6) const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _dayLabel(DateTime d) {
    const names = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
    return names[d.weekday - 1];
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 10.5, color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _DayBars extends StatelessWidget {
  const _DayBars({required this.income, required this.expense, required this.max, required this.label});

  final int income;
  final int expense;
  final int max;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = income + expense;
    final barHeight = total == 0 ? 3.0 : (total / max * 72).clamp(6.0, 72.0);
    final incomeH = total == 0 ? 1.5 : (income / total * barHeight);
    final expenseH = barHeight - incomeH;

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        SizedBox(
          height: 74,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                width: double.infinity,
                height: incomeH,
                decoration: BoxDecoration(
                  color: kIncome,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              if (expenseH > 0) ...[
                const SizedBox(height: 2),
                Container(
                  width: double.infinity,
                  height: expenseH,
                  decoration: BoxDecoration(
                    color: kExpense,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

// ───────────────────────── Pengeluaran per kategori ─────────────────────────

class _CategoryBreakdown extends StatelessWidget {
  const _CategoryBreakdown({
    required this.expByCat,
    required this.catNames,
    required this.catColors,
    required this.onTap,
  });

  final Map<String, int> expByCat;
  final Map<String, String> catNames;
  final Map<String, String> catColors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = expByCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top = rows.take(4).toList();
    final maxVal = top.isEmpty ? 0 : top.first.value;

    return Column(
      children: [
        SectionHeader(title: 'Pengeluaran per kategori', action: TextButton(onPressed: onTap, child: const Text('Semua'))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: top.isEmpty
                  ? SizedBox(
                      height: 80,
                      child: Center(
                        child: Text(
                          'Belum ada pengeluaran bulan ini',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        for (var i = 0; i < top.length; i++) ...[
                          if (i > 0) const SizedBox(height: 12),
                          _CategoryBar(
                            name: catNames[top[i].key] ?? 'Lainnya',
                            amount: top[i].value,
                            ratio: maxVal == 0 ? 0 : top[i].value / maxVal,
                            color: _parseColor(catColors[top[i].key]),
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Color _parseColor(String? hex) {
    final value = int.tryParse((hex ?? '').replaceAll('#', ''), radix: 16) ?? 0x4F46E5;
    return Color(0xFF000000 | value);
  }
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({required this.name, required this.amount, required this.ratio, required this.color});

  final String name;
  final int amount;
  final double ratio;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
            Text(
              formatCompactMoney(amount),
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: ratio.clamp(0, 1),
            minHeight: 5,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}

// ───────────────────────── Tile ─────────────────────────

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task, required this.onTap, this.overdue = false});

  final Task task;
  final VoidCallback onTap;
  final bool overdue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = overdue ? kDanger : priorityColor(task.priority);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          if (task.dueAt != null) ...[
                            Icon(Icons.schedule, size: 12, color: theme.colorScheme.onSurfaceVariant),
                            const SizedBox(width: 3),
                            Text(
                              overdue ? relativeDue(task.dueAt!) : formatTime(task.dueAt!),
                              style: TextStyle(
                                fontSize: 11,
                                color: overdue ? kDanger : theme.colorScheme.onSurfaceVariant,
                                fontWeight: overdue ? FontWeight.w600 : FontWeight.w400,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Text(
                            '${task.progress}%',
                            style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 34,
                  height: 34,
                  child: CircularProgressIndicator(
                    value: task.progress / 100,
                    strokeWidth: 3,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    strokeCap: StrokeCap.round,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.txn, required this.categoryName, required this.onTap});

  final Txn txn;
  final String categoryName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isIncome = txn.type == 'INCOME';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      leading: CircleAvatar(
        radius: 17,
        backgroundColor: (isIncome ? kIncome : kExpense).withValues(alpha: 0.12),
        child: Icon(
          isIncome ? Icons.north_east : Icons.south_west,
          size: 15,
          color: isIncome ? kIncome : kExpense,
        ),
      ),
      title: Text(
        categoryName,
        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        txn.note?.isNotEmpty == true ? txn.note! : formatDateShort(txn.occurredAt),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11.5),
      ),
      trailing: MoneyText(
        isIncome ? txn.amount : -txn.amount,
        fontSize: 13,
        bold: true,
        color: isIncome ? kIncome : theme.colorScheme.onSurface,
      ),
      onTap: onTap,
    );
  }
}
