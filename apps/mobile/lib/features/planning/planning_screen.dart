import 'package:drift/drift.dart' show Value;
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

/// Pusat perencanaan: anggaran bulanan per kategori, utang/piutang, dan
/// ringkasan posisi keuangan (terhubung ke laporan keuangan).
class PlanningScreen extends ConsumerWidget {
  const PlanningScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          leading: const BackButton(),
          title: const Text('Perencanaan & Laporan'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Anggaran'),
              Tab(text: 'Utang/Piutang'),
              Tab(text: 'Ringkasan'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_BudgetsTab(), _DebtsTab(), _SummaryTab()],
        ),
      ),
    );
  }
}

// ───────────────────────────── Anggaran ─────────────────────────────

class _BudgetsTab extends ConsumerWidget {
  const _BudgetsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final budgets = ref.watch(budgetsProvider).valueOrNull ?? const <Budget>[];
    final categories = ref.watch(categoriesProvider('EXPENSE')).valueOrNull ?? const <Category>[];
    final allTransactions = ref.watch(transactionsProvider).valueOrNull ?? const <Txn>[];
    final month = ref.watch(selectedMonthProvider);

    final monthTxns = allTransactions.where((t) {
      return t.type == 'EXPENSE' &&
          t.deletedAt == null &&
          t.occurredAt.year == month.year &&
          t.occurredAt.month == month.month;
    }).toList();

    int getSpentForBudget(Budget b) {
      return monthTxns.where((t) {
        if (t.budgetId != null && t.budgetId!.isNotEmpty) {
          return t.budgetId == b.id;
        }

        if (b.name != null && b.name!.trim().isNotEmpty) {
          final bName = b.name!.trim().toLowerCase();
          final tNote = (t.note ?? '').toLowerCase();
          final tPayee = (t.payee ?? '').toLowerCase();

          final matchesName = tNote.contains(bName) || tPayee.contains(bName) || (tNote.isNotEmpty && bName.contains(tNote));
          if (matchesName) return true;

          final sameCatCount = budgets.where((x) => x.categoryId == b.categoryId).length;
          if (sameCatCount > 1) {
            return false;
          }
        }

        return t.categoryId == b.categoryId;
      }).fold<int>(0, (sum, t) => sum + t.amount);
    }

    final categoryMap = {for (final c in categories) c.id: c};
    final totalBudget = budgets.fold<int>(0, (s, b) => s + b.amount);
    final totalSpent = budgets.fold<int>(0, (s, b) => s + getSpentForBudget(b));
    final remaining = totalBudget - totalSpent;
    final utilization = totalBudget == 0 ? 0.0 : totalSpent / totalBudget;

    final prevMonth = DateTime(month.year, month.month - 1);
    final prevBudgets = ref.watch(budgetsProvider).valueOrNull ?? const <Budget>[];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        // Pemilih bulan
        Row(
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
        const SizedBox(height: 8),

        // Ringkasan anggaran
        if (budgets.isNotEmpty) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Total Anggaran Bulan Ini',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: (utilization > 1
                                  ? kDanger
                                  : utilization > 0.8
                                      ? const Color(0xFFD97706)
                                      : const Color(0xFF059669))
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${(utilization * 100).round()}% Terpakai',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: utilization > 1
                                ? kDanger
                                : utilization > 0.8
                                    ? const Color(0xFFD97706)
                                    : const Color(0xFF059669),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        formatMoney(totalSpent),
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.6),
                      ),
                      const SizedBox(width: 6),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          'dari ${formatMoney(totalBudget)}',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ProgressBar(
                    value: utilization.clamp(0.0, 1.0),
                    color: utilization > 1
                        ? kDanger
                        : utilization > 0.8
                            ? const Color(0xFFD97706)
                            : null,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        remaining >= 0
                            ? 'Sisa Anggaran: ${formatMoney(remaining)}'
                            : 'Terlampaui: ${formatMoney(remaining.abs())}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: remaining >= 0 ? const Color(0xFF059669) : kDanger,
                        ),
                      ),
                      Text(
                        '${budgets.length} Pos Peruntukan',
                        style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Tombol aksi
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () => _addBudgetDialog(context, ref, budgets, categories),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Buat Anggaran Baru'),
              ),
            ),
            const SizedBox(width: 8),
            if (prevBudgets.isNotEmpty && budgets.isEmpty)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _copyFromPreviousMonth(context, ref, prevMonth, prevBudgets, categories),
                  icon: const Icon(Icons.content_copy, size: 16),
                  label: const Text('Salin Bulan Lalu'),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),

        if (budgets.isEmpty)
          Card(
            child: EmptyState(
              icon: Icons.savings_outlined,
              title: 'Belum ada anggaran bulan ini',
              message: 'Tetapkan peruntukan nama, kategori & batas anggaran agar keuangan Anda terkontrol.',
              action: FilledButton.tonal(
                onPressed: () => _addBudgetDialog(context, ref, budgets, categories),
                child: const Text('Buat Anggaran Pertama'),
              ),
            ),
          )
        else ...[
          for (final budget in budgets)
            _BudgetCard(
              budget: budget,
              category: categoryMap[budget.categoryId],
              spent: getSpentForBudget(budget),
              onEdit: () => _editBudgetDialog(context, ref, budget, categories),
              onDelete: () => _deleteBudget(context, ref, budget, categoryMap[budget.categoryId]?.name),
            ),
        ],
      ],
    );
  }

  Future<void> _addBudgetDialog(
    BuildContext context,
    WidgetRef ref,
    List<Budget> existing,
    List<Category> categories,
  ) async {
    final workspace = ref.read(currentWorkspaceProvider);
    if (workspace == null) return;

    if (categories.isEmpty) {
      showAppSnack(context, 'Belum ada kategori pengeluaran.');
      return;
    }

    final nameController = TextEditingController();
    final amountController = TextEditingController();
    final noteController = TextEditingController();

    var selectedCategoryId = categories.first.id;
    var period = 'MONTHLY';
    final month = ref.read(selectedMonthProvider);
    var startAt = DateTime(month.year, month.month);
    DateTime? endAt = DateTime(month.year, month.month + 1).subtract(const Duration(days: 1));

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 10),
                child: Row(
                  children: [
                    Text('Buat Anggaran Baru', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Nama Anggaran *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(hintText: 'Misal: Belanja Dapur, Operasional Kantor, Mudik'),
                      ),
                      const SizedBox(height: 14),

                      const Text('Peruntukan (Kategori Pengeluaran) *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: selectedCategoryId,
                        decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                        items: [
                          for (final c in categories)
                            DropdownMenuItem(value: c.id, child: Text(c.name, style: const TextStyle(fontSize: 13))),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => selectedCategoryId = val);
                        },
                      ),
                      const SizedBox(height: 14),

                      const Text('Batas Nominal Anggaran (Rp) *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: amountController,
                        keyboardType: TextInputType.number,
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

                      const Text('Jangka Waktu / Periode', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            selected: period == 'MONTHLY',
                            onSelected: (_) => setState(() => period = 'MONTHLY'),
                            label: const Text('Bulanan'),
                          ),
                          ChoiceChip(
                            selected: period == 'WEEKLY',
                            onSelected: (_) => setState(() => period = 'WEEKLY'),
                            label: const Text('Mingguan'),
                          ),
                          ChoiceChip(
                            selected: period == 'CUSTOM',
                            onSelected: (_) => setState(() => period = 'CUSTOM'),
                            label: const Text('Kustom Tanggal'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: ctx,
                                  initialDate: startAt,
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime(2060),
                                );
                                if (picked != null) setState(() => startAt = picked);
                              },
                              icon: const Icon(Icons.event, size: 16),
                              label: Text('Mulai: ${formatDate(startAt)}', style: const TextStyle(fontSize: 11.5)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: ctx,
                                  initialDate: endAt ?? startAt.add(const Duration(days: 30)),
                                  firstDate: startAt,
                                  lastDate: DateTime(2060),
                                );
                                if (picked != null) setState(() => endAt = picked);
                              },
                              icon: const Icon(Icons.history_toggle_off, size: 16),
                              label: Text(endAt == null ? 'Selesai: ∞' : 'Selesai: ${formatDate(endAt!)}', style: const TextStyle(fontSize: 11.5)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      const Text('Catatan / Keterangan (opsional)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: noteController,
                        decoration: const InputDecoration(hintText: 'Catatan batas belanja...'),
                      ),
                    ],
                  ),
                ),
              ),

              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: Theme.of(ctx).dividerColor)),
                ),
                child: SafeArea(
                  top: false,
                  child: FilledButton(
                    onPressed: () async {
                      final val = parseMoney(amountController.text);
                      if (val <= 0) {
                        showAppSnack(ctx, 'Batas anggaran harus lebih dari 0', error: true);
                        return;
                      }

                      final nameText = nameController.text.trim();
                      final noteText = noteController.text.trim();

                      try {
                        final db = ref.read(databaseProvider);
                        await db.saveBudget(BudgetsCompanion.insert(
                          id: newId(),
                          workspaceId: workspace.id,
                          categoryId: selectedCategoryId,
                          name: Value(nameText.isEmpty ? null : nameText),
                          period: Value(period),
                          amount: val,
                          startAt: startAt,
                          endAt: Value(endAt),
                          note: Value(noteText.isEmpty ? null : noteText),
                          createdAt: DateTime.now(),
                          updatedAt: DateTime.now(),
                          deviceId: '',
                        ));

                        ref.read(syncSchedulerProvider).schedule();

                        if (ctx.mounted) {
                          Navigator.of(ctx, rootNavigator: true).pop();
                          showAppSnack(context, 'Anggaran "${nameText.isNotEmpty ? nameText : 'baru'}" berhasil disimpan!');
                        }
                      } catch (e) {
                        if (ctx.mounted) {
                          showAppSnack(ctx, 'Gagal menyimpan anggaran: $e', error: true);
                        }
                      }
                    },
                    child: const Text('Simpan Anggaran'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editBudgetDialog(
    BuildContext context,
    WidgetRef ref,
    Budget budget,
    List<Category> categories,
  ) async {
    final workspace = ref.read(currentWorkspaceProvider);
    if (workspace == null) return;

    final nameController = TextEditingController(text: budget.name ?? '');
    final amountController = TextEditingController(text: formatNumber(budget.amount));
    final noteController = TextEditingController(text: budget.note ?? '');

    var selectedCategoryId = budget.categoryId;
    var period = budget.period;
    var startAt = budget.startAt;
    DateTime? endAt = budget.endAt;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 10),
                child: Row(
                  children: [
                    Text('Edit Anggaran', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Nama Anggaran', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(hintText: 'Misal: Belanja Dapur, Operasional Kantor'),
                      ),
                      const SizedBox(height: 14),

                      const Text('Peruntukan (Kategori)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: selectedCategoryId,
                        decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                        items: [
                          for (final c in categories)
                            DropdownMenuItem(value: c.id, child: Text(c.name, style: const TextStyle(fontSize: 13))),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => selectedCategoryId = val);
                        },
                      ),
                      const SizedBox(height: 14),

                      const Text('Batas Nominal (Rp)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: amountController,
                        keyboardType: TextInputType.number,
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

                      const Text('Jangka Waktu / Periode', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            selected: period == 'MONTHLY',
                            onSelected: (_) => setState(() => period = 'MONTHLY'),
                            label: const Text('Bulanan'),
                          ),
                          ChoiceChip(
                            selected: period == 'WEEKLY',
                            onSelected: (_) => setState(() => period = 'WEEKLY'),
                            label: const Text('Mingguan'),
                          ),
                          ChoiceChip(
                            selected: period == 'CUSTOM',
                            onSelected: (_) => setState(() => period = 'CUSTOM'),
                            label: const Text('Kustom Tanggal'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: ctx,
                                  initialDate: startAt,
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime(2060),
                                );
                                if (picked != null) setState(() => startAt = picked);
                              },
                              icon: const Icon(Icons.event, size: 16),
                              label: Text('Mulai: ${formatDate(startAt)}', style: const TextStyle(fontSize: 11.5)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: ctx,
                                  initialDate: endAt ?? startAt.add(const Duration(days: 30)),
                                  firstDate: startAt,
                                  lastDate: DateTime(2060),
                                );
                                if (picked != null) setState(() => endAt = picked);
                              },
                              icon: const Icon(Icons.history_toggle_off, size: 16),
                              label: Text(endAt == null ? 'Selesai: ∞' : 'Selesai: ${formatDate(endAt!)}', style: const TextStyle(fontSize: 11.5)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      const Text('Catatan / Keterangan (opsional)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: noteController,
                        decoration: const InputDecoration(hintText: 'Catatan batas belanja...'),
                      ),
                    ],
                  ),
                ),
              ),

              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: Theme.of(ctx).dividerColor)),
                ),
                child: SafeArea(
                  top: false,
                  child: FilledButton(
                    onPressed: () async {
                      final val = parseMoney(amountController.text);
                      if (val <= 0) {
                        showAppSnack(ctx, 'Batas anggaran harus lebih dari 0', error: true);
                        return;
                      }

                      final nameText = nameController.text.trim();
                      final noteText = noteController.text.trim();

                      try {
                        final db = ref.read(databaseProvider);
                        await db.saveBudget(BudgetsCompanion(
                          id: Value(budget.id),
                          workspaceId: Value(workspace.id),
                          categoryId: Value(selectedCategoryId),
                          name: Value(nameText.isEmpty ? null : nameText),
                          period: Value(period),
                          amount: Value(val),
                          startAt: Value(startAt),
                          endAt: Value(endAt),
                          note: Value(noteText.isEmpty ? null : noteText),
                        ));

                        ref.read(syncSchedulerProvider).schedule();

                        if (ctx.mounted) {
                          Navigator.of(ctx, rootNavigator: true).pop();
                          showAppSnack(context, 'Perubahan anggaran berhasil disimpan');
                        }
                      } catch (e) {
                        if (ctx.mounted) {
                          showAppSnack(ctx, 'Gagal mengedit anggaran: $e', error: true);
                        }
                      }
                    },
                    child: const Text('Simpan Perubahan'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteBudget(BuildContext context, WidgetRef ref, Budget budget, String? categoryName) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Anggaran?'),
        content: Text('Anggaran "${budget.name ?? categoryName ?? 'kategori'}" akan dihapus.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kDanger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(databaseProvider).deleteBudget(budget.id);
      ref.read(syncSchedulerProvider).schedule();
      if (context.mounted) showAppSnack(context, 'Anggaran dihapus');
    }
  }

  Future<void> _copyFromPreviousMonth(
    BuildContext context,
    WidgetRef ref,
    DateTime prevMonth,
    List<Budget> prevBudgets,
    List<Category> categories,
  ) async {
    final workspace = ref.read(currentWorkspaceProvider);
    if (workspace == null) return;
    final month = ref.read(selectedMonthProvider);
    final categoryIds = categories.map((c) => c.id).toSet();
    var copied = 0;
    for (final b in prevBudgets) {
      if (!categoryIds.contains(b.categoryId)) continue;
      await ref.read(databaseProvider).saveBudget(BudgetsCompanion.insert(
            id: newId(),
            workspaceId: workspace.id,
            categoryId: b.categoryId,
            name: Value(b.name),
            period: Value(b.period),
            amount: b.amount,
            startAt: DateTime(month.year, month.month),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            deviceId: '',
          ));
      copied++;
    }
    ref.read(syncSchedulerProvider).schedule();
    if (context.mounted) {
      showAppSnack(context, copied == 0 ? 'Tidak ada anggaran yang bisa disalin.' : '$copied anggaran disalin dari bulan lalu.');
    }
  }
}

class _BudgetCard extends ConsumerWidget {
  const _BudgetCard({
    required this.budget,
    required this.category,
    required this.spent,
    required this.onEdit,
    required this.onDelete,
  });

  final Budget budget;
  final Category? category;
  final int spent;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ratio = budget.amount == 0 ? 0.0 : spent / budget.amount;
    final over = spent > budget.amount;
    final remaining = budget.amount - spent;
    final pct = (ratio * 100).round();
    final warn = !over && ratio >= 0.75;

    Color badgeColor;
    String badgeLabel;

    if (over) {
      badgeColor = kDanger;
      badgeLabel = 'Terlampaui';
    } else if (warn) {
      badgeColor = const Color(0xFFD97706);
      badgeLabel = 'Waspada ($pct%)';
    } else {
      badgeColor = const Color(0xFF059669);
      badgeLabel = 'Aman ($pct%)';
    }

    String periodLabel;
    switch (budget.period) {
      case 'WEEKLY':
        periodLabel = 'Mingguan';
        break;
      case 'CUSTOM':
        periodLabel = 'Kustom';
        break;
      default:
        periodLabel = 'Bulanan';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _parseColor(category?.color ?? '#64748B'),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          budget.name?.isNotEmpty == true ? budget.name! : (category?.name ?? 'Kategori Pengeluaran'),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                        if (budget.name?.isNotEmpty == true)
                          Text(
                            'Peruntukan: ${category?.name ?? 'Pengeluaran'} · $periodLabel',
                            style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      badgeLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: badgeColor,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_vert, size: 18),
                    onPressed: onDelete,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ProgressBar(
                value: ratio.clamp(0.0, 1.0),
                color: badgeColor,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Realisasi Pemakaian',
                        style: TextStyle(fontSize: 10.5, color: theme.colorScheme.onSurfaceVariant),
                      ),
                      Text(
                        '${formatMoney(spent)} / ${formatMoney(budget.amount)}',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        over ? 'Kelebihan' : 'Sisa Kuota',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: over ? kDanger : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        over ? '+${formatMoney(-remaining)}' : formatMoney(remaining),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: over ? kDanger : const Color(0xFF059669),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => showTransactionEditor(
                    context,
                    ref,
                    initialType: 'EXPENSE',
                    initialCategoryId: budget.categoryId,
                    initialBudgetId: budget.id,
                    initialNote: budget.name,
                  ),
                  icon: const Icon(Icons.add_circle_outline, size: 15),
                  label: Text('Catat Pengeluaran (${category?.name ?? 'Anggaran'})', style: const TextStyle(fontSize: 11.5)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _parseColor(String hex) {
    final value = int.tryParse(hex.replaceAll('#', ''), radix: 16) ?? 0x64748B;
    return Color(0xFF000000 | value);
  }
}

// ───────────────────────────── Utang / Piutang ─────────────────────────────

class _DebtsTab extends ConsumerWidget {
  const _DebtsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debts = ref.watch(debtsProvider).valueOrNull ?? const <Debt>[];
    final open = debts.where((d) => d.remaining > 0).toList();
    final settled = debts.where((d) => d.remaining <= 0).toList();

    final receivable = open.where((d) => d.direction == 'RECEIVABLE').fold<int>(0, (s, d) => s + d.remaining);
    final payable = open.where((d) => d.direction == 'PAYABLE').fold<int>(0, (s, d) => s + d.remaining);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Row(
          children: [
            Expanded(
              child: StatCard(
                label: 'Piutang (orang utang ke kita)',
                value: formatCompactMoney(receivable),
                icon: Icons.call_received,
                color: kIncome,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatCard(
                label: 'Utang (kita utang ke orang)',
                value: formatCompactMoney(payable),
                icon: Icons.call_made,
                color: kExpense,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.balance, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Posisi bersih: ',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        formatMoney(receivable - payable),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: receivable - payable >= 0 ? kIncome : kExpense,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed: () => _addDebt(context, ref),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Catat'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (debts.isEmpty)
          Card(
            child: EmptyState(
              icon: Icons.handshake_outlined,
              title: 'Belum ada catatan utang/piutang',
              message: 'Catat uang yang dipinjam atau dipinjamkan agar tidak lupa.',
              action: FilledButton.tonal(
                onPressed: () => _addDebt(context, ref),
                child: const Text('Catat sekarang'),
              ),
            ),
          )
        else ...[
          if (open.isNotEmpty) ...[
            const SectionHeader(title: 'Belum lunas', padding: EdgeInsets.fromLTRB(4, 4, 4, 8)),
            for (final debt in open) _DebtRow(debt: debt),
          ],
          if (settled.isNotEmpty) ...[
            const SectionHeader(title: 'Sudah lunas', padding: EdgeInsets.fromLTRB(4, 16, 4, 8)),
            for (final debt in settled) _DebtRow(debt: debt, dimmed: true),
          ],
        ],
      ],
    );
  }

  Future<void> _addDebt(BuildContext context, WidgetRef ref) async {
    await _showDebtDialog(context, ref, null);
  }
}

class _DebtRow extends ConsumerWidget {
  const _DebtRow({required this.debt, this.dimmed = false});

  final Debt debt;
  final bool dimmed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isReceivable = debt.direction == 'RECEIVABLE';
    final overdue = debt.dueAt != null && debt.remaining > 0 && debt.dueAt!.isBefore(DateTime.now());
    final daysOverdue = overdue ? DateTime.now().difference(debt.dueAt!).inDays : 0;
    final progress = debt.principal == 0 ? 0.0 : (debt.principal - debt.remaining) / debt.principal;

    IconData debtIcon;
    switch (debt.category) {
      case 'MORTGAGE':
        debtIcon = Icons.home_outlined;
        break;
      case 'VEHICLE':
        debtIcon = Icons.directions_car_outlined;
        break;
      case 'CREDIT_CARD':
        debtIcon = Icons.credit_card_outlined;
        break;
      case 'BANK':
        debtIcon = Icons.account_balance_outlined;
        break;
      default:
        debtIcon = isReceivable ? Icons.call_received : Icons.call_made;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showDebtDialog(context, ref, debt),
        onLongPress: () => _deleteDebt(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 17,
                    backgroundColor: (isReceivable ? kIncome : kExpense).withValues(alpha: 0.12),
                    child: Icon(debtIcon, size: 18, color: isReceivable ? kIncome : kExpense),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          debt.counterparty,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: dimmed ? theme.colorScheme.onSurfaceVariant : null,
                            decoration: dimmed ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        Row(
                          children: [
                            Text(
                              isReceivable ? 'Piutang' : 'Utang / Angsuran',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurfaceVariant),
                            ),
                            if (debt.contractNumber?.isNotEmpty == true) ...[
                              Text(' · No: ${debt.contractNumber}', style: TextStyle(fontSize: 10.5, color: theme.colorScheme.onSurfaceVariant)),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (debt.remaining <= 0)
                    const Icon(Icons.check_circle, size: 20, color: Color(0xFF059669))
                  else
                    TextButton.icon(
                      onPressed: () => _showPayDialog(context, ref, debt),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        minimumSize: const Size(0, 32),
                      ),
                      icon: const Icon(Icons.payments_outlined, size: 14),
                      label: const Text('Bayar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              ProgressBar(value: progress.clamp(0.0, 1.0), color: isReceivable ? kIncome : kExpense),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Sisa: ${formatMoney(debt.remaining)} / ${formatMoney(debt.principal)}',
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 11.5, fontWeight: FontWeight.w600),
                  ),
                  if (debt.monthlyInstallment != null && debt.monthlyInstallment! > 0) ...[
                    Text(
                      '${formatMoney(debt.monthlyInstallment!)}/bln',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: theme.colorScheme.primary),
                    ),
                  ],
                ],
              ),
              if (debt.dueAt != null || debt.tenorMonths != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (debt.tenorMonths != null && debt.tenorMonths! > 0) ...[
                      Text(
                        'Tenor: ${debt.tenorMonths} bulan',
                        style: TextStyle(fontSize: 10.5, color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(width: 8),
                    ],
                    const Spacer(),
                    if (debt.dueAt != null) ...[
                      Icon(Icons.event_outlined, size: 12, color: overdue ? kDanger : theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 3),
                      Text(
                        overdue
                            ? 'Jatuh tempo lewat $daysOverdue hari'
                            : 'Jatuh tempo: ${formatDate(debt.dueAt!)}',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: overdue ? FontWeight.w700 : FontWeight.w500,
                          color: overdue ? kDanger : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
              if (debt.principal > debt.remaining) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final categories = ref.read(categoriesProvider('EXPENSE')).valueOrNull ?? const <Category>[];
                      final tagihanCat = categories.where((c) => c.name.toLowerCase().contains('tagihan') || c.name.toLowerCase().contains('operasional')).firstOrNull ?? categories.firstOrNull;

                      showTransactionEditor(
                        context,
                        ref,
                        initialType: 'EXPENSE',
                        initialCategoryId: tagihanCat?.id,
                        initialNote: 'Pembayaran Angsuran: ${debt.counterparty}',
                      );
                    },
                    icon: const Icon(Icons.receipt_long_outlined, size: 14),
                    label: Text(
                      'Terbayar ${formatMoney(debt.principal - debt.remaining)} · Catat/Koreksi di Keuangan',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteDebt(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus catatan?'),
        content: Text('Catatan dengan ${debt.counterparty} akan dihapus.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Hapus')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(databaseProvider).deleteDebt(debt.id);
      ref.read(syncSchedulerProvider).schedule();
    }
  }
}

// ───────────────────────────── Ringkasan / Laporan ─────────────────────────────

class _SummaryTab extends ConsumerWidget {
  const _SummaryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final month = ref.watch(selectedMonthProvider);
    final summary = ref.watch(monthlySummaryProvider).valueOrNull;
    final budgets = ref.watch(budgetsProvider).valueOrNull ?? const <Budget>[];
    final spentMap = ref.watch(expenseByCategoryProvider).valueOrNull ?? const <String, int>{};
    final debts = ref.watch(debtsProvider).valueOrNull ?? const <Debt>[];
    final categories = ref.watch(categoriesProvider('EXPENSE')).valueOrNull ?? const <Category>[];
    final categoryMap = {for (final c in categories) c.id: c};

    final totalBudget = budgets.fold<int>(0, (s, b) => s + b.amount);
    final totalSpentBudgeted = budgets.fold<int>(0, (s, b) => s + (spentMap[b.categoryId] ?? 0));
    final overBudget = budgets.where((b) => (spentMap[b.categoryId] ?? 0) > b.amount).toList();

    final openDebts = debts.where((d) => d.remaining > 0).toList();
    final receivable = openDebts.where((d) => d.direction == 'RECEIVABLE').fold<int>(0, (s, d) => s + d.remaining);
    final payable = openDebts.where((d) => d.direction == 'PAYABLE').fold<int>(0, (s, d) => s + d.remaining);
    final overdueDebts = openDebts.where((d) => d.dueAt != null && d.dueAt!.isBefore(DateTime.now())).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        // Pemilih bulan
        Row(
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
        const SizedBox(height: 8),

        // Arus kas bulan ini
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Arus kas bulan ini', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                _kv('Pemasukan', formatMoney(summary?.income ?? 0), kIncome),
                _kv('Pengeluaran', formatMoney(summary?.expense ?? 0), kExpense),
                const Divider(height: 12),
                _kv('Selisih', formatMoney(summary?.net ?? 0), (summary?.net ?? 0) >= 0 ? kIncome : kExpense, bold: true),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Anggaran vs realisasi
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(child: Text('Anggaran vs realisasi', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                    TextButton(
                      onPressed: () => DefaultTabController.of(context).animateTo(0),
                      child: const Text('Detail', style: TextStyle(fontSize: 11.5)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (budgets.isEmpty)
                  Text('Belum ada anggaran. Buat di tab Anggaran.',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant))
                else ...[
                  _kv('Total anggaran', formatMoney(totalBudget), null),
                  _kv('Terpakai', formatMoney(totalSpentBudgeted), null),
                  _kv('Sisa', formatMoney(totalBudget - totalSpentBudgeted), totalBudget - totalSpentBudgeted >= 0 ? const Color(0xFF059669) : kDanger),
                  if (overBudget.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Kategori lewat anggaran:', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: kDanger)),
                    const SizedBox(height: 4),
                    for (final b in overBudget)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, size: 13, color: kDanger),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                categoryMap[b.categoryId]?.name ?? 'Kategori',
                                style: const TextStyle(fontSize: 11.5),
                              ),
                            ),
                            Text(
                              '+${formatCompactMoney((spentMap[b.categoryId] ?? 0) - b.amount)}',
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: kDanger),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Posisi utang/piutang
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(child: Text('Posisi utang / piutang', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                    TextButton(
                      onPressed: () => DefaultTabController.of(context).animateTo(1),
                      child: const Text('Detail', style: TextStyle(fontSize: 11.5)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _kv('Piutang (orang utang ke kita)', formatMoney(receivable), kIncome),
                _kv('Utang (kita utang ke orang)', formatMoney(payable), kExpense),
                const Divider(height: 12),
                _kv('Posisi bersih', formatMoney(receivable - payable), receivable - payable >= 0 ? kIncome : kExpense, bold: true),
                if (overdueDebts.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Jatuh tempo lewat:', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: kDanger)),
                  const SizedBox(height: 4),
                  for (final d in overdueDebts)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Row(
                        children: [
                          const Icon(Icons.event_busy, size: 13, color: kDanger),
                          const SizedBox(width: 6),
                          Expanded(child: Text(d.counterparty, style: const TextStyle(fontSize: 11.5))),
                          Text(
                            '${DateTime.now().difference(d.dueAt!).inDays} hari',
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: kDanger),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Tautan ke laporan keuangan
        Card(
          child: ListTile(
            leading: const Icon(Icons.bar_chart_rounded),
            title: const Text('Laporan keuangan lengkap', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            subtitle: const Text('Transaksi, grafik arus kas, dan breakdown kategori', style: TextStyle(fontSize: 11)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/reports'),
          ),
        ),
      ],
    );
  }

  Widget _kv(String label, String value, Color? color, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
          Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showDebtDialog(BuildContext context, WidgetRef ref, Debt? existing) async {
  final counterparty = TextEditingController(text: existing?.counterparty ?? '');
  final principal = TextEditingController(text: existing != null ? formatNumber(existing.principal) : '');
  final installment = TextEditingController(text: existing?.monthlyInstallment != null ? formatNumber(existing!.monthlyInstallment!) : '');
  final tenor = TextEditingController(text: existing?.tenorMonths?.toString() ?? '');
  final contractNo = TextEditingController(text: existing?.contractNumber ?? '');
  final note = TextEditingController(text: existing?.note ?? '');

  var direction = existing?.direction ?? 'PAYABLE';
  var category = existing?.category ?? 'MORTGAGE';
  String? selectedAssetId = existing?.assetId;
  DateTime? dueAt = existing?.dueAt;
  final workspace = ref.read(currentWorkspaceProvider);
  if (workspace == null) return;

  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(existing == null ? 'Catatan Utang / Angsuran Baru' : 'Ubah Catatan Utang'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (existing == null) ...[
                const Text('Templat Cepat', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.home_outlined, size: 14),
                        label: const Text('KPR Rumah'),
                        onPressed: () => setState(() {
                          direction = 'PAYABLE';
                          category = 'MORTGAGE';
                          counterparty.text = 'KPR Bank (Rumah)';
                        }),
                      ),
                      const SizedBox(width: 6),
                      ActionChip(
                        avatar: const Icon(Icons.directions_car_outlined, size: 14),
                        label: const Text('Angsuran Kendaraan'),
                        onPressed: () => setState(() {
                          direction = 'PAYABLE';
                          category = 'VEHICLE';
                          counterparty.text = 'Leasing (Mobil/Motor)';
                        }),
                      ),
                      const SizedBox(width: 6),
                      ActionChip(
                        avatar: const Icon(Icons.credit_card, size: 14),
                        label: const Text('Kartu Kredit'),
                        onPressed: () => setState(() {
                          direction = 'PAYABLE';
                          category = 'CREDIT_CARD';
                          counterparty.text = 'Kartu Kredit';
                        }),
                      ),
                      const SizedBox(width: 6),
                      ActionChip(
                        avatar: const Icon(Icons.account_balance_outlined, size: 14),
                        label: const Text('Pinjaman Bank'),
                        onPressed: () => setState(() {
                          direction = 'PAYABLE';
                          category = 'BANK';
                          counterparty.text = 'Pinjaman Bank';
                        }),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    selected: direction == 'PAYABLE',
                    onSelected: (_) => setState(() => direction = 'PAYABLE'),
                    label: const Text('Saya Utang / Angsuran'),
                  ),
                  ChoiceChip(
                    selected: direction == 'RECEIVABLE',
                    onSelected: (_) => setState(() => direction = 'RECEIVABLE'),
                    label: const Text('Orang Utang ke Saya'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: counterparty,
                autofocus: existing == null,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Pemberi Pinjaman / Nama Utang *',
                  hintText: 'Misal: KPR Bank BCA, Leasing Mobil',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: principal,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Sisa Total Pinjaman / Plafond (Rp) *',
                  hintText: '0',
                ),
                onChanged: (value) {
                  final formatted = formatMoneyInput(value);
                  if (formatted != value) {
                    principal.value = TextEditingValue(
                      text: formatted,
                      selection: TextSelection.collapsed(offset: formatted.length),
                    );
                  }
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: installment,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Cicilan (Rp/Bulan)',
                        hintText: 'Opsional',
                      ),
                      onChanged: (value) {
                        final formatted = formatMoneyInput(value);
                        if (formatted != value) {
                          installment.value = TextEditingValue(
                            text: formatted,
                            selection: TextSelection.collapsed(offset: formatted.length),
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: tenor,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Tenor (Bulan)',
                        hintText: 'Misal: 120',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contractNo,
                decoration: const InputDecoration(
                  labelText: 'No. Kontrak / Perjanjian (opsional)',
                  hintText: 'Misal: KPR-BCA-2024-001',
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: dueAt ?? DateTime.now().add(const Duration(days: 30)),
                    firstDate: DateTime.now().subtract(const Duration(days: 365)),
                    lastDate: DateTime.now().add(const Duration(days: 365 * 30)),
                    useRootNavigator: true,
                  );
                  if (picked != null) setState(() => dueAt = picked);
                },
                icon: const Icon(Icons.event_outlined, size: 16),
                label: Text(dueAt == null ? 'Jatuh Tempo Pembayaran' : 'Jatuh Tempo: ${formatDate(dueAt!)}'),
              ),
              const SizedBox(height: 12),
              const Text('Hubungkan ke Aset (opsional)', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              () {
                final assetsList = ref.watch(assetsProvider).valueOrNull ?? const <Asset>[];
                final activeAssets = assetsList.where((a) => a.status == 'ACTIVE').toList();

                if (activeAssets.isEmpty) {
                  return const Text('Belum ada aset aktif di Tab Aset.', style: TextStyle(fontSize: 11, color: Colors.grey));
                }

                return DropdownButtonFormField<String?>(
                  initialValue: selectedAssetId,
                  decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Tanpa Hubungan Aset (Utang Umum)', style: TextStyle(fontSize: 12.5))),
                    for (final a in activeAssets)
                      DropdownMenuItem<String?>(
                        value: a.id,
                        child: Text('${a.name} (${formatCompactMoney(a.currentValue)})', style: const TextStyle(fontSize: 12.5)),
                      ),
                  ],
                  onChanged: (val) => setState(() => selectedAssetId = val),
                );
              }(),
              const SizedBox(height: 12),
              TextField(
                controller: note,
                decoration: const InputDecoration(
                  labelText: 'Catatan / Agunan (opsional)',
                  hintText: 'Misal: Jaminan BPKB / SHM No. 1234',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          FilledButton(
            onPressed: () async {
              final value = parseMoney(principal.text);
              final instVal = parseMoney(installment.text);
              final tenorVal = int.tryParse(tenor.text.trim());
              final cNo = contractNo.text.trim();
              final noteTxt = note.text.trim();

              if (counterparty.text.trim().isEmpty || value <= 0) return;
              if (existing == null) {
                final savedDebt = await ref.read(databaseProvider).saveDebt(DebtsCompanion.insert(
                      id: newId(),
                      workspaceId: workspace.id,
                      counterparty: counterparty.text.trim(),
                      direction: direction,
                      category: Value(category),
                      assetId: Value(selectedAssetId),
                      principal: value,
                      remaining: value,
                      monthlyInstallment: Value(instVal == 0 ? null : instVal),
                      tenorMonths: Value(tenorVal),
                      contractNumber: Value(cNo.isEmpty ? null : cNo),
                      dueAt: Value(dueAt),
                      note: Value(noteTxt.isEmpty ? null : noteTxt),
                      createdAt: DateTime.now(),
                      updatedAt: DateTime.now(),
                      deviceId: '',
                    ));
                if (selectedAssetId != null) {
                  await ref.read(databaseProvider).saveAsset(AssetsCompanion(
                    id: Value(selectedAssetId!),
                    debtId: Value(savedDebt.id),
                  ));
                }
              } else {
                final paid = existing.principal - existing.remaining;
                final newRemaining = (value - paid).clamp(0, value);
                await ref.read(databaseProvider).saveDebt(DebtsCompanion(
                  id: Value(existing.id),
                  workspaceId: Value(workspace.id),
                  counterparty: Value(counterparty.text.trim()),
                  direction: Value(direction),
                  category: Value(category),
                  assetId: Value(selectedAssetId),
                  principal: Value(value),
                  remaining: Value(newRemaining),
                  monthlyInstallment: Value(instVal == 0 ? null : instVal),
                  tenorMonths: Value(tenorVal),
                  contractNumber: Value(cNo.isEmpty ? null : cNo),
                  dueAt: Value(dueAt),
                  note: Value(noteTxt.isEmpty ? null : noteTxt),
                ));
                if (selectedAssetId != null) {
                  await ref.read(databaseProvider).saveAsset(AssetsCompanion(
                    id: Value(selectedAssetId!),
                    debtId: Value(existing.id),
                  ));
                }
              }
              ref.read(syncSchedulerProvider).schedule();
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Simpan Catatan'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _showPayDialog(BuildContext context, WidgetRef ref, Debt debt) async {
  final initialPay = debt.monthlyInstallment != null && debt.monthlyInstallment! > 0
      ? debt.monthlyInstallment!
      : debt.remaining;
  final controller = TextEditingController(text: formatNumber(initialPay));
  var createTxn = true;

  final wallets = ref.read(walletsProvider).valueOrNull ?? const <Wallet>[];
  final categories = ref.read(categoriesProvider('EXPENSE')).valueOrNull ?? const <Category>[];
  final tagihanCategory = categories.where((c) => c.name.toLowerCase().contains('tagihan') || c.name.toLowerCase().contains('operasional')).firstOrNull ?? categories.firstOrNull;

  String? selectedWalletId = wallets.isNotEmpty ? wallets.first.id : null;
  String? selectedCategoryId = tagihanCategory?.id;

  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('Bayar Angsuran ${debt.counterparty}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade700.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Sisa Utang:', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    Text(formatMoney(debt.remaining), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kExpense)),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Text('Jumlah Dibayar (Rp) *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(hintText: '0'),
                onChanged: (value) {
                  final formatted = formatMoneyInput(value);
                  if (formatted != value) {
                    controller.value = TextEditingValue(
                      text: formatted,
                      selection: TextSelection.collapsed(offset: formatted.length),
                    );
                  }
                  setState(() {});
                },
              ),
              const SizedBox(height: 14),
              CheckboxListTile(
                value: createTxn,
                onChanged: (v) => setState(() => createTxn = v ?? true),
                title: const Text('Catat sebagai transaksi di Keuangan', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                subtitle: Text(
                  debt.direction == 'PAYABLE' ? 'Otomatis mengurangi saldo dompet (Pengeluaran)' : 'Otomatis menambah saldo dompet (Pemasukan)',
                  style: const TextStyle(fontSize: 10.5),
                ),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              if (createTxn && wallets.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text('Pilih Dompet Pembayaran:', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: selectedWalletId,
                  decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                  items: [
                    for (final w in wallets)
                      DropdownMenuItem(value: w.id, child: Text(w.name, style: const TextStyle(fontSize: 12.5))),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => selectedWalletId = val);
                  },
                ),
              ],
              if (createTxn && categories.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Pilih Kategori Transaksi:', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: selectedCategoryId,
                  decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                  items: [
                    for (final c in categories)
                      DropdownMenuItem(value: c.id, child: Text(c.name, style: const TextStyle(fontSize: 12.5))),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => selectedCategoryId = val);
                  },
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          FilledButton(
            onPressed: () async {
              final amount = parseMoney(controller.text);
              if (amount <= 0) return;

              final db = ref.read(databaseProvider);
              await db.payDebt(debt, amount);

              if (createTxn && selectedWalletId != null) {
                final ws = ref.read(currentWorkspaceProvider);
                if (ws != null) {
                  final isPayable = debt.direction == 'PAYABLE';
                  final now = DateTime.now();

                  await db.saveTransaction(TransactionsCompanion.insert(
                    id: newId(),
                    workspaceId: ws.id,
                    walletId: selectedWalletId!,
                    categoryId: Value(selectedCategoryId),
                    type: isPayable ? 'EXPENSE' : 'INCOME',
                    amount: amount,
                    occurredAt: now,
                    note: Value('Pembayaran Angsuran: ${debt.counterparty}'),
                    payee: Value(debt.counterparty),
                    createdAt: now,
                    updatedAt: now,
                    deviceId: '',
                  ));
                }
              }

              ref.read(syncSchedulerProvider).schedule();

              if (context.mounted) {
                Navigator.pop(context);
                showAppSnack(
                  context,
                  'Pembayaran ${debt.counterparty} (${formatMoney(amount)}) berhasil dicatat di Keuangan!',
                );
              }
            },
            child: const Text('Simpan Pembayaran'),
          ),
        ],
      ),
    ),
  );
}
