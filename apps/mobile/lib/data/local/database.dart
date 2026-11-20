import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'connection/connection.dart';
import 'mappers.dart';
import 'tables.dart';

part 'database.g.dart';

/// Ringkasan saldo satu dompet.
class WalletBalance {
  const WalletBalance({
    required this.walletId,
    required this.name,
    required this.type,
    required this.balance,
  });

  final String walletId;
  final String name;
  final String type;
  final int balance;
}

/// Ringkasan keuangan satu periode.
class FinanceSummary {
  const FinanceSummary({
    required this.income,
    required this.expense,
    required this.transfer,
  });

  final int income;
  final int expense;
  final int transfer;

  int get net => income - expense;
}

const _uuid = Uuid();

@DriftDatabase(tables: [
  Workspaces,
  Projects,
  Tasks,
  ChecklistItems,
  TaskProgressLogs,
  Reminders,
  CalendarEvents,
  Wallets,
  Categories,
  Transactions,
  Budgets,
  Debts,
  Assets,
  AssetValuations,
  AssetMaintenances,
  Documents,
  Outbox,
  SyncStates,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            try {
              await m.createTable(documents);
            } catch (_) {}
            try {
              await m.addColumn(assets, assets.attachments);
            } catch (_) {}
          }
          if (from < 3) {
            try {
              await m.addColumn(budgets, budgets.name);
            } catch (_) {}
            try {
              await m.addColumn(budgets, budgets.note);
            } catch (_) {}
          }
          if (from < 4) {
            try {
              await m.addColumn(debts, debts.category);
            } catch (_) {}
            try {
              await m.addColumn(debts, debts.monthlyInstallment);
            } catch (_) {}
            try {
              await m.addColumn(debts, debts.tenorMonths);
            } catch (_) {}
            try {
              await m.addColumn(debts, debts.contractNumber);
            } catch (_) {}
          }
          if (from < 5) {
            try {
              await m.addColumn(transactions, transactions.budgetId);
            } catch (_) {}
          }
          if (from < 6) {
            try {
              await m.addColumn(assets, assets.debtId);
            } catch (_) {}
          }
          if (from < 7) {
            try {
              await m.addColumn(debts, debts.assetId);
            } catch (_) {}
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          try {
            await customStatement('ALTER TABLE budgets ADD COLUMN name TEXT');
          } catch (_) {}
          try {
            await customStatement('ALTER TABLE budgets ADD COLUMN note TEXT');
          } catch (_) {}
          try {
            await customStatement('ALTER TABLE debts ADD COLUMN category TEXT');
          } catch (_) {}
          try {
            await customStatement('ALTER TABLE debts ADD COLUMN monthly_installment INTEGER');
          } catch (_) {}
          try {
            await customStatement('ALTER TABLE debts ADD COLUMN tenor_months INTEGER');
          } catch (_) {}
          try {
            await customStatement('ALTER TABLE debts ADD COLUMN contract_number TEXT');
          } catch (_) {}
          try {
            await customStatement('ALTER TABLE debts ADD COLUMN asset_id TEXT');
          } catch (_) {}
          try {
            await customStatement('ALTER TABLE transactions ADD COLUMN budget_id TEXT');
          } catch (_) {}
          try {
            await customStatement('ALTER TABLE assets ADD COLUMN debt_id TEXT');
          } catch (_) {}
          try {
            await autoRepairUncategorizedTransactions();
          } catch (_) {}
        },
      );

  String? _cachedDeviceId;

  // ───────────────────────────── Device & meta ─────────────────────────────

  Future<String> deviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;
    final existing = await getMeta('deviceId');
    if (existing != null) {
      _cachedDeviceId = existing;
      return existing;
    }
    final id = _uuid.v4();
    await setMeta('deviceId', id);
    _cachedDeviceId = id;
    return id;
  }

  Future<String?> getMeta(String key) async {
    final row = await (select(syncStates)..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> setMeta(String key, String value) async {
    await into(syncStates).insertOnConflictUpdate(SyncStatesCompanion.insert(key: key, value: value));
  }

  Future<void> deleteMeta(String key) async {
    await (delete(syncStates)..where((t) => t.key.equals(key))).go();
  }

  // ───────────────────────────── Workspaces ─────────────────────────────

  Stream<List<Workspace>> watchWorkspaces() {
    return (select(workspaces)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .watch();
  }

  Future<List<Workspace>> listWorkspaces() {
    return (select(workspaces)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  Future<void> upsertWorkspaceFromServer(Map<String, dynamic> json) async {
    final now = DateTime.now();
    final existing = await (select(workspaces)..where((t) => t.id.equals(json['id'] as String)))
        .getSingleOrNull();
    await into(workspaces).insertOnConflictUpdate(
      WorkspacesCompanion.insert(
        id: json['id'] as String,
        type: (json['type'] as String?) ?? 'PERSONAL',
        name: json['name'] as String,
        color: Value((json['color'] as String?) ?? '#2563EB'),
        icon: Value((json['icon'] as String?) ?? 'briefcase'),
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
        deviceId: 'server',
      ),
    );
  }

  Future<void> upsertCategoryFromServer(Map<String, dynamic> json) async {
    final now = DateTime.now();
    final existing = await (select(categories)..where((t) => t.id.equals(json['id'] as String)))
        .getSingleOrNull();
    await into(categories).insertOnConflictUpdate(
      CategoriesCompanion.insert(
        id: json['id'] as String,
        workspaceId: json['workspaceId'] as String,
        name: json['name'] as String,
        kind: json['kind'] as String,
        parentId: Value(json['parentId'] as String?),
        icon: Value((json['icon'] as String?) ?? 'label'),
        color: Value((json['color'] as String?) ?? '#64748B'),
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
        deviceId: 'server',
        syncedAt: Value(now),
      ),
    );
  }

  Future<void> upsertWalletFromServer(Map<String, dynamic> json) async {
    final now = DateTime.now();
    final existing = await (select(wallets)..where((t) => t.id.equals(json['id'] as String)))
        .getSingleOrNull();
    await into(wallets).insertOnConflictUpdate(
      WalletsCompanion.insert(
        id: json['id'] as String,
        workspaceId: json['workspaceId'] as String,
        name: json['name'] as String,
        type: Value((json['type'] as String?) ?? 'CASH'),
        initialBalance: Value((json['initialBalance'] as num?)?.toInt() ?? 0),
        currency: Value((json['currency'] as String?) ?? 'IDR'),
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
        deviceId: 'server',
        syncedAt: Value(now),
      ),
    );
  }

  Future<String> activeWorkspaceId() async {
    final stored = await getMeta('activeWorkspaceId');
    final all = await listWorkspaces();
    if (stored != null && all.any((w) => w.id == stored)) return stored;
    if (all.isEmpty) return '';
    await setMeta('activeWorkspaceId', all.first.id);
    return all.first.id;
  }

  Future<void> setActiveWorkspace(String id) => setMeta('activeWorkspaceId', id);

  /// Membuat kategori & dompet awal saat workspace belum punya data.
  Future<void> ensureWorkspaceDefaults(String workspaceId, String type) async {
    final walletCount = await (select(wallets)..where((t) => t.workspaceId.equals(workspaceId))).get();
    if (walletCount.isNotEmpty) return;

    final now = DateTime.now();
    final dev = await deviceId();
    final isCompany = type == 'COMPANY';

    final expense = <List<String>>[
      ['Makan & Minum', 'restaurant', '#F97316'],
      ['Transport', 'directions_car', '#0EA5E9'],
      ['Tagihan', 'receipt_long', '#8B5CF6'],
      ['Belanja', 'shopping_bag', '#EC4899'],
      ['Kesehatan', 'health_and_safety', '#EF4444'],
      ['Hiburan', 'movie', '#F59E0B'],
      if (isCompany) ['Operasional', 'engineering', '#64748B'],
      ['Lainnya', 'more_horiz', '#94A3B8'],
    ];
    final income = <List<String>>[
      ['Gaji', 'payments', '#10B981'],
      ['Bonus', 'card_giftcard', '#22C55E'],
      if (isCompany) ['Pendapatan Jasa', 'work', '#14B8A6'],
      ['Lainnya', 'add_circle', '#94A3B8'],
    ];

    for (final c in expense) {
      final category = Category(
        id: newId(),
        workspaceId: workspaceId,
        name: c[0],
        kind: 'EXPENSE',
        parentId: null,
        icon: c[1],
        color: c[2],
        createdAt: now,
        updatedAt: now,
        deletedAt: null,
        version: 1,
        deviceId: dev,
        syncedAt: null,
      );
      await _insertAndSync(categories, category, 'category', categoryToWire);
    }
    for (final c in income) {
      final category = Category(
        id: newId(),
        workspaceId: workspaceId,
        name: c[0],
        kind: 'INCOME',
        parentId: null,
        icon: c[1],
        color: c[2],
        createdAt: now,
        updatedAt: now,
        deletedAt: null,
        version: 1,
        deviceId: dev,
        syncedAt: null,
      );
      await _insertAndSync(categories, category, 'category', categoryToWire);
    }

    final wallet = Wallet(
      id: newId(),
      workspaceId: workspaceId,
      name: isCompany ? 'Kas Perusahaan' : 'Tunai',
      type: isCompany ? 'BANK' : 'CASH',
      initialBalance: 0,
      currency: 'IDR',
      archivedAt: null,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
      version: 1,
      deviceId: dev,
      syncedAt: null,
    );
    await _insertAndSync(wallets, wallet, 'wallet', walletToWire);
  }

  // ───────────────────────────── Projects ─────────────────────────────

  Stream<List<Project>> watchProjects(String workspaceId) {
    return (select(projects)
          ..where((t) => t.workspaceId.equals(workspaceId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch();
  }

  // ───────────────────────────── Tasks ─────────────────────────────

  Stream<List<Task>> watchTasks(String workspaceId, {String? status, String? search}) {
    final q = select(tasks)
      ..where((t) => t.workspaceId.equals(workspaceId) & t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.dueAt, mode: OrderingMode.asc),
        (t) => OrderingTerm(expression: t.priority, mode: OrderingMode.asc),
      ]);
    if (status != null && status != 'ALL') {
      q.where((t) => t.status.equals(status));
    }
    if (search != null && search.trim().isNotEmpty) {
      q.where((t) => t.title.like('%${search.trim()}%'));
    }
    return q.watch();
  }

  Stream<List<Task>> watchTodayTasks(String workspaceId, {DateTime? now}) {
    final ref = now ?? DateTime.now();
    final endOfDay = DateTime(ref.year, ref.month, ref.day).add(const Duration(days: 1));
    return (select(tasks)
          ..where((t) =>
              t.workspaceId.equals(workspaceId) &
              t.deletedAt.isNull() &
              t.status.isNotIn(['DONE', 'CANCELLED']) &
              t.dueAt.isSmallerThanValue(endOfDay))
          ..orderBy([(t) => OrderingTerm.asc(t.dueAt)]))
        .watch();
  }

  Stream<List<Task>> watchSubtasks(String parentId) {
    return (select(tasks)
          ..where((t) => t.parentTaskId.equals(parentId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .watch();
  }

  Future<Task?> getTask(String id) {
    return (select(tasks)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Stream<Task?> watchTask(String id) {
    return (select(tasks)..where((t) => t.id.equals(id))).watchSingleOrNull();
  }

  Future<Task> saveTask(TasksCompanion input) async {
    final dev = await deviceId();
    final now = DateTime.now();
    final id = input.id.value;
    final existing = await getTask(id);

    final row = TasksCompanion(
      id: Value(id),
      workspaceId: existing != null
          ? Value(existing.workspaceId)
          : (input.workspaceId.present ? input.workspaceId : const Value('')),
      projectId: input.projectId.present ? input.projectId : Value(existing?.projectId),
      parentTaskId: input.parentTaskId.present ? input.parentTaskId : Value(existing?.parentTaskId),
      title: existing != null
          ? (input.title.present ? input.title : Value(existing.title))
          : input.title,
      description: input.description.present ? input.description : Value(existing?.description),
      status: input.status.present ? input.status : Value(existing?.status ?? 'TODO'),
      priority: input.priority.present ? input.priority : Value(existing?.priority ?? 2),
      progress: input.progress.present ? input.progress : Value(existing?.progress ?? 0),
      startAt: input.startAt.present ? input.startAt : Value(existing?.startAt),
      dueAt: input.dueAt.present ? input.dueAt : Value(existing?.dueAt),
      completedAt: input.completedAt.present ? input.completedAt : Value(existing?.completedAt),
      estimatedMinutes: input.estimatedMinutes.present
          ? input.estimatedMinutes
          : Value(existing?.estimatedMinutes),
      actualMinutes: input.actualMinutes.present
          ? input.actualMinutes
          : Value(existing?.actualMinutes ?? 0),
      tags: input.tags.present ? input.tags : Value(existing?.tags ?? '[]'),
      recurrenceRule: input.recurrenceRule.present
          ? input.recurrenceRule
          : Value(existing?.recurrenceRule),
      createdAt: Value(existing?.createdAt ?? now),
      updatedAt: Value(now),
      deletedAt: Value(existing?.deletedAt),
      version: Value((existing?.version ?? 0) + 1),
      deviceId: Value(dev),
      syncedAt: const Value(null),
    );

    await into(tasks).insertOnConflictUpdate(row);
    final saved = (await getTask(id))!;
    await _enqueue('task', id, taskToWire(saved));
    return saved;
  }

  /// Mengubah progres + mencatat log progres (append-only).
  Future<void> updateProgress(Task task, int progress, {String? note}) async {
    final clamped = progress.clamp(0, 100);
    final dev = await deviceId();
    final now = DateTime.now();

    await saveTask(TasksCompanion(
      id: Value(task.id),
      progress: Value(clamped),
      status: Value(clamped == 100
          ? 'DONE'
          : task.status == 'TODO' && clamped > 0
              ? 'IN_PROGRESS'
              : task.status),
      completedAt: Value(clamped == 100 ? now : null),
    ));

    // Otomatis buat tugas berikutnya jika tugas ini memiliki pengulangan (Recurring Task)
    if (clamped == 100 && task.recurrenceRule != null && task.recurrenceRule!.isNotEmpty) {
      final due = task.dueAt ?? now;
      DateTime nextDue;
      if (task.recurrenceRule == 'DAILY') {
        nextDue = due.add(const Duration(days: 1));
      } else if (task.recurrenceRule == 'WEEKLY') {
        nextDue = due.add(const Duration(days: 7));
      } else if (task.recurrenceRule == 'MONTHLY') {
        nextDue = DateTime(due.year, due.month + 1, due.day, due.hour, due.minute);
      } else {
        nextDue = due.add(const Duration(days: 1));
      }

      await saveTask(TasksCompanion.insert(
        id: newId(),
        workspaceId: task.workspaceId,
        title: task.title,
        description: Value(task.description),
        dueAt: Value(nextDue),
        priority: Value(task.priority),
        status: const Value('TODO'),
        estimatedMinutes: Value(task.estimatedMinutes),
        recurrenceRule: Value(task.recurrenceRule),
        createdAt: now,
        updatedAt: now,
        deviceId: '',
      ));
    }

    final log = ProgressLog(
      id: newId(),
      workspaceId: task.workspaceId,
      taskId: task.id,
      progressBefore: task.progress,
      progressAfter: clamped,
      note: note,
      occurredAt: now,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
      version: 1,
      deviceId: dev,
      syncedAt: null,
    );
    await into(taskProgressLogs).insert(log);
    await _enqueue('taskProgressLog', log.id, progressLogToWire(log));
  }

  Future<void> deleteTask(String id) async {
    final task = await getTask(id);
    if (task == null) return;
    final dev = await deviceId();
    final now = DateTime.now();
    await (update(tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        version: Value(task.version + 1),
        deviceId: Value(dev),
        syncedAt: const Value(null),
      ),
    );
    final saved = (await getTask(id))!;
    await _enqueue('task', id, taskToWire(saved));
  }

  Stream<List<ChecklistEntry>> watchChecklist(String taskId) {
    return (select(checklistItems)
          ..where((t) => t.taskId.equals(taskId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .watch();
  }

  Future<void> addChecklistItem(String workspaceId, String taskId, String title) async {
    final dev = await deviceId();
    final now = DateTime.now();
    final count = await (select(checklistItems)..where((t) => t.taskId.equals(taskId))).get();
    final item = ChecklistEntry(
      id: newId(),
      workspaceId: workspaceId,
      taskId: taskId,
      title: title,
      isDone: false,
      sortOrder: count.length,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
      version: 1,
      deviceId: dev,
      syncedAt: null,
    );
    await _insertAndSync(checklistItems, item, 'checklistItem', checklistToWire);
  }

  Future<void> toggleChecklistItem(ChecklistEntry item) async {
    final dev = await deviceId();
    final now = DateTime.now();
    final updated = item.copyWith(
      isDone: !item.isDone,
      updatedAt: now,
      version: item.version + 1,
      deviceId: dev,
      syncedAt: const Value(null),
    );
    await (update(checklistItems)..where((t) => t.id.equals(item.id))).write(updated);
    await _enqueue('checklistItem', item.id, checklistToWire(updated));
  }

  Future<void> deleteChecklistItem(String id) async {
    final dev = await deviceId();
    final now = DateTime.now();
    final item = await (select(checklistItems)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (item == null) return;
    final updated = item.copyWith(
      deletedAt: Value(now),
      updatedAt: now,
      version: item.version + 1,
      deviceId: dev,
      syncedAt: const Value(null),
    );
    await (update(checklistItems)..where((t) => t.id.equals(id))).write(updated);
    await _enqueue('checklistItem', id, checklistToWire(updated));
  }

  Stream<List<ProgressLog>> watchProgressLogs(String taskId) {
    return (select(taskProgressLogs)
          ..where((t) => t.taskId.equals(taskId))
          ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]))
        .watch();
  }

  // ───────────────────────────── Finance ─────────────────────────────

  Stream<List<Wallet>> watchWallets(String workspaceId) {
    return (select(wallets)
          ..where((t) => t.workspaceId.equals(workspaceId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch();
  }

  Future<List<Wallet>> listWallets(String workspaceId) {
    return (select(wallets)
          ..where((t) => t.workspaceId.equals(workspaceId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
  }

  Stream<List<WalletBalance>> watchWalletBalances(String workspaceId) {
    final query = customSelect(
      '''
      SELECT w.id AS wallet_id,
             w.name AS name,
             w.type AS type,
             w.initial_balance + COALESCE(SUM(
               CASE
                 WHEN t.type = 'INCOME' THEN t.amount
                 WHEN t.type = 'EXPENSE' THEN -(t.amount + t.fee)
                 WHEN t.type = 'TRANSFER' THEN -(t.amount + t.fee)
                 ELSE 0
               END), 0) AS balance
      FROM wallets w
      LEFT JOIN transactions t ON t.wallet_id = w.id AND t.deleted_at IS NULL
      WHERE w.workspace_id = ? AND w.deleted_at IS NULL
      GROUP BY w.id
      ORDER BY w.name
      ''',
      variables: [Variable<String>(workspaceId)],
      readsFrom: {wallets, transactions},
    );

    return query.watch().map((rows) => rows
        .map((r) => WalletBalance(
              walletId: r.read<String>('wallet_id'),
              name: r.read<String>('name'),
              type: r.read<String>('type'),
              balance: r.read<int>('balance'),
            ))
        .toList());
  }

  Stream<List<Category>> watchCategories(String workspaceId, {String? kind}) {
    final q = select(categories)
      ..where((t) => t.workspaceId.equals(workspaceId) & t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.name)]);
    if (kind != null) q.where((t) => t.kind.equals(kind));
    return q.watch();
  }

  Future<List<Category>> listCategories(String workspaceId, {String? kind}) {
    final q = select(categories)
      ..where((t) => t.workspaceId.equals(workspaceId) & t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.name)]);
    if (kind != null) q.where((t) => t.kind.equals(kind));
    return q.get();
  }

  Stream<List<Txn>> watchTransactions(String workspaceId, DateTime from, DateTime to) {
    return (select(transactions)
          ..where((t) =>
              (t.workspaceId.equals(workspaceId) | t.workspaceId.equals('')) &
              t.deletedAt.isNull() &
              t.occurredAt.isBiggerOrEqualValue(from) &
              t.occurredAt.isSmallerThanValue(to))
          ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]))
        .watch();
  }

  Stream<List<Txn>> watchRecentTransactions(String workspaceId, {int limit = 10}) {
    return (select(transactions)
          ..where((t) => (t.workspaceId.equals(workspaceId) | t.workspaceId.equals('')) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)])
          ..limit(limit))
        .watch();
  }

  Stream<FinanceSummary> watchSummary(String workspaceId, DateTime from, DateTime to) {
    return watchTransactions(workspaceId, from, to).map((rows) {
      var income = 0;
      var expense = 0;
      var transfer = 0;
      for (final t in rows) {
        switch (t.type) {
          case 'INCOME':
            income += t.amount;
          case 'EXPENSE':
            expense += t.amount + t.fee;
          case 'TRANSFER':
            transfer += t.amount;
        }
      }
      return FinanceSummary(income: income, expense: expense, transfer: transfer);
    });
  }

  Stream<Map<String, int>> watchExpenseByCategory(String workspaceId, DateTime from, DateTime to) {
    return watchTransactions(workspaceId, from, to).map((rows) {
      final map = <String, int>{};
      for (final t in rows) {
        if (t.type != 'EXPENSE') continue;
        final key = t.categoryId ?? 'uncategorized';
        map[key] = (map[key] ?? 0) + t.amount + t.fee;
      }
      return map;
    });
  }

  Future<Txn> saveTransaction(TransactionsCompanion input) async {
    final dev = await deviceId();
    final now = DateTime.now();
    final id = input.id.value;
    final existing = await (select(transactions)..where((t) => t.id.equals(id))).getSingleOrNull();

    final row = TransactionsCompanion(
      id: Value(id),
      workspaceId: existing != null
          ? Value(existing.workspaceId)
          : (input.workspaceId.present ? input.workspaceId : const Value('')),
      walletId: existing != null
          ? (input.walletId.present ? input.walletId : Value(existing.walletId))
          : input.walletId,
      categoryId: input.categoryId.present ? input.categoryId : Value(existing?.categoryId),
      budgetId: input.budgetId.present ? input.budgetId : Value(existing?.budgetId),
      type: existing != null
          ? (input.type.present ? input.type : Value(existing.type))
          : input.type,
      amount: existing != null
          ? (input.amount.present ? input.amount : Value(existing.amount))
          : input.amount,
      fee: input.fee.present ? input.fee : Value(existing?.fee ?? 0),
      transferGroupId: input.transferGroupId.present ? input.transferGroupId : Value(existing?.transferGroupId),
      occurredAt: input.occurredAt.present ? input.occurredAt : Value(existing?.occurredAt ?? now),
      note: input.note.present ? input.note : Value(existing?.note),
      payee: input.payee.present ? input.payee : Value(existing?.payee),
      attachmentId: input.attachmentId.present ? input.attachmentId : Value(existing?.attachmentId),
      isReconciled: input.isReconciled.present ? input.isReconciled : Value(existing?.isReconciled ?? false),
      createdAt: Value(existing?.createdAt ?? now),
      updatedAt: Value(now),
      deletedAt: Value(existing?.deletedAt),
      version: Value((existing?.version ?? 0) + 1),
      deviceId: Value(dev),
      syncedAt: const Value(null),
    );

    await into(transactions).insertOnConflictUpdate(row);
    final saved = (await (select(transactions)..where((t) => t.id.equals(id))).getSingle());
    await _enqueue('transaction', id, transactionToWire(saved));
    return saved;
  }

  Future<void> deleteTransaction(String id) async {
    final row = await (select(transactions)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return;
    final dev = await deviceId();
    final now = DateTime.now();
    final updated = row.copyWith(
      deletedAt: Value(now),
      updatedAt: now,
      version: row.version + 1,
      deviceId: dev,
      syncedAt: const Value(null),
    );
    await (update(transactions)..where((t) => t.id.equals(id))).write(updated);
    await _enqueue('transaction', id, transactionToWire(updated));
  }

  Future<Wallet> saveWallet(WalletsCompanion input) async {
    final dev = await deviceId();
    final now = DateTime.now();
    final id = input.id.value;
    final existing = await (select(wallets)..where((t) => t.id.equals(id))).getSingleOrNull();
    final row = input.copyWith(
      version: Value((existing?.version ?? 0) + 1),
      createdAt: Value(existing?.createdAt ?? now),
      updatedAt: Value(now),
      deviceId: Value(dev),
      syncedAt: const Value(null),
    );
    await into(wallets).insertOnConflictUpdate(row);
    final saved = await (select(wallets)..where((t) => t.id.equals(id))).getSingle();
    await _enqueue('wallet', id, walletToWire(saved));
    return saved;
  }

  Future<void> deleteWallet(String id) async {
    final row = await (select(wallets)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return;
    final dev = await deviceId();
    final now = DateTime.now();
    final updated = row.copyWith(
      deletedAt: Value(now),
      updatedAt: now,
      version: row.version + 1,
      deviceId: dev,
      syncedAt: const Value(null),
    );
    await (update(wallets)..where((t) => t.id.equals(id))).write(updated);
    await _enqueue('wallet', id, walletToWire(updated));
  }

  Future<void> saveBudget(BudgetsCompanion input) async {
    final dev = await deviceId();
    final now = DateTime.now();
    final id = input.id.value;
    final existing = await (select(budgets)..where((t) => t.id.equals(id))).getSingleOrNull();

    final row = BudgetsCompanion(
      id: Value(id),
      workspaceId: existing != null
          ? Value(existing.workspaceId)
          : (input.workspaceId.present ? input.workspaceId : const Value('')),
      categoryId: existing != null
          ? (input.categoryId.present ? input.categoryId : Value(existing.categoryId))
          : input.categoryId,
      name: input.name.present ? input.name : Value(existing?.name),
      period: input.period.present ? input.period : Value(existing?.period ?? 'MONTHLY'),
      amount: input.amount.present ? input.amount : Value(existing?.amount ?? 0),
      startAt: input.startAt.present ? input.startAt : Value(existing?.startAt ?? now),
      endAt: input.endAt.present ? input.endAt : Value(existing?.endAt),
      rollover: input.rollover.present ? input.rollover : Value(existing?.rollover ?? false),
      note: input.note.present ? input.note : Value(existing?.note),
      createdAt: Value(existing?.createdAt ?? now),
      updatedAt: Value(now),
      deletedAt: Value(existing?.deletedAt),
      version: Value((existing?.version ?? 0) + 1),
      deviceId: Value(dev),
      syncedAt: const Value(null),
    );

    await into(budgets).insertOnConflictUpdate(row);
    final saved = await (select(budgets)..where((t) => t.id.equals(id))).getSingle();
    await _enqueue('budget', id, budgetToWire(saved));
  }

  Stream<List<Budget>> watchBudgets(String workspaceId) {
    return (select(budgets)
          ..where((t) => (t.workspaceId.equals(workspaceId) | t.workspaceId.equals('')) & t.deletedAt.isNull()))
        .watch();
  }

  Future<void> deleteBudget(String id) async {
    final row = await (select(budgets)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return;
    final dev = await deviceId();
    final now = DateTime.now();
    final updated = row.copyWith(
      deletedAt: Value(now),
      updatedAt: now,
      version: row.version + 1,
      deviceId: dev,
      syncedAt: const Value(null),
    );
    await (update(budgets)..where((t) => t.id.equals(id))).write(updated);
    await _enqueue('budget', id, budgetToWire(updated));
  }

  Stream<List<Debt>> watchDebts(String workspaceId) {
    return (select(debts)
          ..where((t) => (t.workspaceId.equals(workspaceId) | t.workspaceId.equals('')) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.dueAt)]))
        .watch();
  }

  Future<Debt> saveDebt(DebtsCompanion input) async {
    final dev = await deviceId();
    final now = DateTime.now();
    final id = input.id.value;
    final existing = await (select(debts)..where((t) => t.id.equals(id))).getSingleOrNull();

    final row = DebtsCompanion(
      id: Value(id),
      workspaceId: existing != null
          ? Value(existing.workspaceId)
          : (input.workspaceId.present ? input.workspaceId : const Value('')),
      counterparty: existing != null
          ? (input.counterparty.present ? input.counterparty : Value(existing.counterparty))
          : input.counterparty,
      direction: existing != null
          ? (input.direction.present ? input.direction : Value(existing.direction))
          : input.direction,
      category: input.category.present ? input.category : Value(existing?.category),
      assetId: input.assetId.present ? input.assetId : Value(existing?.assetId),
      principal: existing != null
          ? (input.principal.present ? input.principal : Value(existing.principal))
          : input.principal,
      remaining: existing != null
          ? (input.remaining.present ? input.remaining : Value(existing.remaining))
          : input.remaining,
      monthlyInstallment: input.monthlyInstallment.present
          ? input.monthlyInstallment
          : Value(existing?.monthlyInstallment),
      tenorMonths: input.tenorMonths.present ? input.tenorMonths : Value(existing?.tenorMonths),
      contractNumber: input.contractNumber.present
          ? input.contractNumber
          : Value(existing?.contractNumber),
      dueAt: input.dueAt.present ? input.dueAt : Value(existing?.dueAt),
      note: input.note.present ? input.note : Value(existing?.note),
      status: input.status.present ? input.status : Value(existing?.status ?? 'open'),
      createdAt: Value(existing?.createdAt ?? now),
      updatedAt: Value(now),
      deletedAt: Value(existing?.deletedAt),
      version: Value((existing?.version ?? 0) + 1),
      deviceId: Value(dev),
      syncedAt: const Value(null),
    );

    await into(debts).insertOnConflictUpdate(row);
    final saved = await (select(debts)..where((t) => t.id.equals(id))).getSingle();
    await _enqueue('debt', id, debtToWire(saved));
    return saved;
  }

  /// Mengubah batas anggaran tanpa menyentuh kolom lain.
  Future<Budget> updateBudgetAmount(Budget budget, int amount) async {
    final dev = await deviceId();
    final now = DateTime.now();
    final updated = budget.copyWith(
      amount: amount,
      updatedAt: now,
      version: budget.version + 1,
      deviceId: dev,
      syncedAt: const Value(null),
    );
    await (update(budgets)..where((t) => t.id.equals(budget.id))).write(updated);
    await _enqueue('budget', budget.id, budgetToWire(updated));
    return updated;
  }

  /// Mencatat pembayaran utang/piutang; sisa tidak boleh negatif.
  Future<Debt> payDebt(Debt debt, int amount) async {
    final remaining = (debt.remaining - amount).clamp(0, debt.principal);
    final dev = await deviceId();
    final now = DateTime.now();
    final updated = debt.copyWith(
      remaining: remaining,
      status: remaining == 0 ? 'settled' : 'open',
      updatedAt: now,
      version: debt.version + 1,
      deviceId: dev,
      syncedAt: const Value(null),
    );
    await (update(debts)..where((t) => t.id.equals(debt.id))).write(updated);
    await _enqueue('debt', debt.id, debtToWire(updated));
    return updated;
  }

  Future<void> deleteDebt(String id) async {
    final row = await (select(debts)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return;
    final dev = await deviceId();
    final now = DateTime.now();
    final updated = row.copyWith(
      deletedAt: Value(now),
      updatedAt: now,
      version: row.version + 1,
      deviceId: dev,
      syncedAt: const Value(null),
    );
    await (update(debts)..where((t) => t.id.equals(id))).write(updated);
    await _enqueue('debt', id, debtToWire(updated));
  }

  // ───────────────────────────── Assets ─────────────────────────────

  Stream<List<Asset>> watchAssets(String workspaceId) {
    return (select(assets)
          ..where((t) => (t.workspaceId.equals(workspaceId) | t.workspaceId.equals('')) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.currentValue)]))
        .watch();
  }

  Stream<Asset?> watchAsset(String id) {
    return (select(assets)..where((t) => t.id.equals(id))).watchSingleOrNull();
  }

  Stream<List<AssetValuation>> watchValuations(String assetId) {
    return (select(assetValuations)
          ..where((t) => t.assetId.equals(assetId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.valuedAt)]))
        .watch();
  }

  Stream<List<AssetMaintenance>> watchMaintenances(String assetId) {
    return (select(assetMaintenances)
          ..where((t) => t.assetId.equals(assetId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.performedAt)]))
        .watch();
  }

  Future<Asset> saveAsset(AssetsCompanion input) async {
    final dev = await deviceId();
    final now = DateTime.now();
    final id = input.id.value;
    final existing = await (select(assets)..where((t) => t.id.equals(id))).getSingleOrNull();

    final row = AssetsCompanion(
      id: Value(id),
      workspaceId: existing != null
          ? Value(existing.workspaceId)
          : (input.workspaceId.present ? input.workspaceId : const Value('')),
      name: existing != null
          ? (input.name.present ? input.name : Value(existing.name))
          : input.name,
      category: existing != null
          ? (input.category.present ? input.category : Value(existing.category))
          : input.category,
      purchaseAt: input.purchaseAt.present
          ? input.purchaseAt
          : Value(existing?.purchaseAt),
      purchasePrice: input.purchasePrice.present
          ? input.purchasePrice
          : Value(existing?.purchasePrice),
      currentValue: input.currentValue.present
          ? input.currentValue
          : Value(existing?.currentValue ?? 0),
      depreciationMethod: input.depreciationMethod.present
          ? input.depreciationMethod
          : Value(existing?.depreciationMethod ?? 'NONE'),
      usefulLifeMonths: input.usefulLifeMonths.present
          ? input.usefulLifeMonths
          : Value(existing?.usefulLifeMonths),
      salvageValue: input.salvageValue.present
          ? input.salvageValue
          : Value(existing?.salvageValue),
      status: existing != null
          ? (input.status.present ? input.status : Value(existing.status))
          : input.status,
      serialNumber: input.serialNumber.present
          ? input.serialNumber
          : Value(existing?.serialNumber),
      debtId: input.debtId.present ? input.debtId : Value(existing?.debtId),
      attachments: input.attachments.present
          ? input.attachments
          : Value(existing?.attachments),
      note: input.note.present ? input.note : Value(existing?.note),
      createdAt: Value(existing?.createdAt ?? now),
      updatedAt: Value(now),
      deletedAt: Value(existing?.deletedAt),
      version: Value((existing?.version ?? 0) + 1),
      deviceId: Value(dev),
      syncedAt: const Value(null),
    );

    await into(assets).insertOnConflictUpdate(row);
    final saved = await (select(assets)..where((t) => t.id.equals(id))).getSingle();
    await _enqueue('asset', id, assetToWire(saved));
    return saved;
  }

  Future<void> deleteAsset(String id) async {
    final row = await (select(assets)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return;
    final dev = await deviceId();
    final now = DateTime.now();
    final updated = row.copyWith(
      deletedAt: Value(now),
      updatedAt: now,
      version: row.version + 1,
      deviceId: dev,
      syncedAt: const Value(null),
    );
    await (update(assets)..where((t) => t.id.equals(id))).write(updated);
    await _enqueue('asset', id, assetToWire(updated));
  }

  Future<void> addValuation({
    required String workspaceId,
    required String assetId,
    required int value,
    DateTime? valuedAt,
    String source = 'MANUAL',
    String? note,
  }) async {
    final dev = await deviceId();
    final now = DateTime.now();
    final valuation = AssetValuation(
      id: newId(),
      workspaceId: workspaceId,
      assetId: assetId,
      value: value,
      valuedAt: valuedAt ?? now,
      source: source,
      note: note,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
      version: 1,
      deviceId: dev,
      syncedAt: null,
    );
    await into(assetValuations).insert(valuation);
    await _enqueue('assetValuation', valuation.id, assetValuationToWire(valuation));

    final asset = await (select(assets)..where((t) => t.id.equals(assetId))).getSingleOrNull();
    if (asset != null) {
      await saveAsset(AssetsCompanion(
        id: Value(asset.id),
        workspaceId: Value(asset.workspaceId),
        name: Value(asset.name),
        category: Value(asset.category),
        currentValue: Value(value),
        status: Value(asset.status),
      ));
    }
  }

  Future<void> addMaintenance({
    required String workspaceId,
    required String assetId,
    required String title,
    int cost = 0,
    DateTime? performedAt,
    DateTime? nextDueAt,
    String? note,
  }) async {
    final dev = await deviceId();
    final now = DateTime.now();
    final row = AssetMaintenance(
      id: newId(),
      workspaceId: workspaceId,
      assetId: assetId,
      title: title,
      cost: cost,
      performedAt: performedAt ?? now,
      nextDueAt: nextDueAt,
      note: note,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
      version: 1,
      deviceId: dev,
      syncedAt: null,
    );
    await into(assetMaintenances).insert(row);
    await _enqueue('assetMaintenance', row.id, assetMaintenanceToWire(row));
  }

  // ───────────────────────────── Documents ─────────────────────────────

  Stream<List<DocEntry>> watchDocuments(String workspaceId, {String? category, String? search}) {
    final q = select(documents)
      ..where((t) => t.workspaceId.equals(workspaceId) & t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.title)]);
    if (category != null && category != 'ALL') {
      q.where((t) => t.category.equals(category));
    }
    if (search != null && search.trim().isNotEmpty) {
      q.where((t) =>
          t.title.like('%${search.trim()}%') |
          t.docNumber.like('%${search.trim()}%') |
          t.holderName.like('%${search.trim()}%'));
    }
    return q.watch();
  }

  Future<DocEntry> saveDocument(DocumentsCompanion input) async {
    final dev = await deviceId();
    final now = DateTime.now();
    final id = input.id.value;
    final existing = await (select(documents)..where((t) => t.id.equals(id))).getSingleOrNull();
    final row = input.copyWith(
      workspaceId: existing != null ? Value(existing.workspaceId) : input.workspaceId,
      version: Value((existing?.version ?? 0) + 1),
      createdAt: Value(existing?.createdAt ?? now),
      updatedAt: Value(now),
      deviceId: Value(dev),
      syncedAt: const Value(null),
    );
    await into(documents).insertOnConflictUpdate(row);
    final saved = await (select(documents)..where((t) => t.id.equals(id))).getSingle();
    await _enqueue('document', id, documentToWire(saved));
    return saved;
  }

  Future<void> deleteDocument(String id) async {
    final row = await (select(documents)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return;
    final dev = await deviceId();
    final now = DateTime.now();
    final updated = row.copyWith(
      deletedAt: Value(now),
      updatedAt: now,
      version: row.version + 1,
      deviceId: dev,
      syncedAt: const Value(null),
    );
    await (update(documents)..where((t) => t.id.equals(id))).write(updated);
    await _enqueue('document', id, documentToWire(updated));
  }

  // ───────────────────────────── Calendar ─────────────────────────────

  Stream<List<CalendarEvent>> watchEvents(String workspaceId, DateTime from, DateTime to) {
    return (select(calendarEvents)
          ..where((t) =>
              t.workspaceId.equals(workspaceId) &
              t.deletedAt.isNull() &
              t.startAt.isSmallerThanValue(to) &
              t.endAt.isBiggerOrEqualValue(from))
          ..orderBy([(t) => OrderingTerm.asc(t.startAt)]))
        .watch();
  }

  Future<void> saveEvent(CalendarEventsCompanion input) async {
    final dev = await deviceId();
    final now = DateTime.now();
    final id = input.id.value;
    final existing =
        await (select(calendarEvents)..where((t) => t.id.equals(id))).getSingleOrNull();

    final row = CalendarEventsCompanion(
      id: Value(id),
      workspaceId: existing != null
          ? Value(existing.workspaceId)
          : (input.workspaceId.present ? input.workspaceId : const Value('')),
      title: existing != null
          ? (input.title.present ? input.title : Value(existing.title))
          : input.title,
      location: input.location.present ? input.location : Value(existing?.location),
      startAt: existing != null
          ? (input.startAt.present ? input.startAt : Value(existing.startAt))
          : input.startAt,
      endAt: existing != null
          ? (input.endAt.present ? input.endAt : Value(existing.endAt))
          : input.endAt,
      allDay: input.allDay.present ? input.allDay : Value(existing?.allDay ?? false),
      recurrenceRule: input.recurrenceRule.present
          ? input.recurrenceRule
          : Value(existing?.recurrenceRule),
      linkedTaskId: input.linkedTaskId.present ? input.linkedTaskId : Value(existing?.linkedTaskId),
      note: input.note.present ? input.note : Value(existing?.note),
      createdAt: Value(existing?.createdAt ?? now),
      updatedAt: Value(now),
      deletedAt: Value(existing?.deletedAt),
      version: Value((existing?.version ?? 0) + 1),
      deviceId: Value(dev),
      syncedAt: const Value(null),
    );

    await into(calendarEvents).insertOnConflictUpdate(row);
    final saved = await (select(calendarEvents)..where((t) => t.id.equals(id))).getSingle();
    await _enqueue('calendarEvent', id, calendarEventToWire(saved));
  }

  Future<void> deleteEvent(String id) async {
    final row = await (select(calendarEvents)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return;
    final dev = await deviceId();
    final now = DateTime.now();
    final updated = row.copyWith(
      deletedAt: Value(now),
      updatedAt: now,
      version: row.version + 1,
      deviceId: dev,
      syncedAt: const Value(null),
    );
    await (update(calendarEvents)..where((t) => t.id.equals(id))).write(updated);
    await _enqueue('calendarEvent', id, calendarEventToWire(updated));
  }

  // ───────────────────────────── Reminders ─────────────────────────────

  Stream<List<Reminder>> watchReminders(String workspaceId) {
    return (select(reminders)
          ..where((t) =>
              t.workspaceId.equals(workspaceId) & t.deletedAt.isNull() & t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm.asc(t.triggerAt)]))
        .watch();
  }

  Future<Reminder> saveReminder(RemindersCompanion input) async {
    final dev = await deviceId();
    final now = DateTime.now();
    final id = input.id.value;
    final existing = await (select(reminders)..where((t) => t.id.equals(id))).getSingleOrNull();

    final row = RemindersCompanion(
      id: Value(id),
      workspaceId: existing != null
          ? Value(existing.workspaceId)
          : (input.workspaceId.present ? input.workspaceId : const Value('')),
      entityType: input.entityType.present ? input.entityType : Value(existing?.entityType ?? 'CUSTOM'),
      entityId: input.entityId.present ? input.entityId : Value(existing?.entityId),
      title: input.title.present ? input.title : Value(existing?.title ?? ''),
      message: input.message.present ? input.message : Value(existing?.message),
      triggerAt: input.triggerAt.present ? input.triggerAt : Value(existing?.triggerAt ?? now),
      recurrenceRule: input.recurrenceRule.present ? input.recurrenceRule : Value(existing?.recurrenceRule),
      snoozeUntil: input.snoozeUntil.present ? input.snoozeUntil : Value(existing?.snoozeUntil),
      isActive: input.isActive.present ? input.isActive : Value(existing?.isActive ?? true),
      firedAt: input.firedAt.present ? input.firedAt : Value(existing?.firedAt),
      createdAt: Value(existing?.createdAt ?? now),
      updatedAt: Value(now),
      deletedAt: Value(existing?.deletedAt),
      version: Value((existing?.version ?? 0) + 1),
      deviceId: Value(dev),
      syncedAt: const Value(null),
    );

    await into(reminders).insertOnConflictUpdate(row);
    final saved = await (select(reminders)..where((t) => t.id.equals(id))).getSingle();
    await _enqueue('reminder', id, reminderToWire(saved));
    return saved;
  }

  Future<String> exportBackupJson() async {
    final ws = await select(workspaces).get();
    final tsk = await select(tasks).get();
    final txn = await select(transactions).get();
    final wal = await select(wallets).get();
    final cat = await select(categories).get();
    final ast = await select(assets).get();
    final doc = await select(documents).get();
    final bdg = await select(budgets).get();
    final dbt = await select(debts).get();

    final data = {
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'workspaces': ws.map((w) => workspaceToWire(w)).toList(),
      'tasks': tsk.map((t) => taskToWire(t)).toList(),
      'transactions': txn.map((t) => transactionToWire(t)).toList(),
      'wallets': wal.map((w) => walletToWire(w)).toList(),
      'categories': cat.map((c) => categoryToWire(c)).toList(),
      'assets': ast.map((a) => assetToWire(a)).toList(),
      'documents': doc.map((d) => documentToWire(d)).toList(),
      'budgets': bdg.map((b) => budgetToWire(b)).toList(),
      'debts': dbt.map((d) => debtToWire(d)).toList(),
    };

    return jsonEncode(data);
  }

  Future<int> importBackupJson(String jsonStr) async {
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    var count = 0;

    if (map['workspaces'] is List) {
      for (final item in map['workspaces'] as List) {
        await upsertWorkspaceFromServer(item as Map<String, dynamic>);
        count++;
      }
    }
    if (map['categories'] is List) {
      for (final item in map['categories'] as List) {
        await upsertCategoryFromServer(item as Map<String, dynamic>);
        count++;
      }
    }
    if (map['wallets'] is List) {
      for (final item in map['wallets'] as List) {
        final w = walletFromWire(item as Map<String, dynamic>);
        await into(wallets).insertOnConflictUpdate(w);
        count++;
      }
    }
    if (map['tasks'] is List) {
      for (final item in map['tasks'] as List) {
        final t = taskFromWire(item as Map<String, dynamic>);
        await saveTask(t);
        count++;
      }
    }
    if (map['transactions'] is List) {
      for (final item in map['transactions'] as List) {
        final t = transactionFromWire(item as Map<String, dynamic>);
        await saveTransaction(t);
        count++;
      }
    }
    if (map['assets'] is List) {
      for (final item in map['assets'] as List) {
        final a = assetFromWire(item as Map<String, dynamic>);
        await saveAsset(a);
        count++;
      }
    }
    if (map['documents'] is List) {
      for (final item in map['documents'] as List) {
        final d = documentFromWire(item as Map<String, dynamic>);
        await saveDocument(d);
        count++;
      }
    }
    if (map['budgets'] is List) {
      for (final item in map['budgets'] as List) {
        final b = budgetFromWire(item as Map<String, dynamic>);
        await saveBudget(b);
        count++;
      }
    }
    if (map['debts'] is List) {
      for (final item in map['debts'] as List) {
        final d = debtFromWire(item as Map<String, dynamic>);
        await saveDebt(d);
        count++;
      }
    }

    return count;
  }

  Future<Reminder?> getReminder(String id) {
    return (select(reminders)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<List<Reminder>> listActiveReminders() {
    return (select(reminders)
          ..where((t) => t.deletedAt.isNull() & t.isActive.equals(true)))
        .get();
  }

  Future<void> setReminderActive(Reminder reminder, bool active) async {
    final dev = await deviceId();
    final now = DateTime.now();
    final updated = reminder.copyWith(
      isActive: active,
      updatedAt: now,
      version: reminder.version + 1,
      deviceId: dev,
      syncedAt: const Value(null),
    );
    await (update(reminders)..where((t) => t.id.equals(reminder.id))).write(updated);
    await _enqueue('reminder', reminder.id, reminderToWire(updated));
  }

  Future<void> deleteReminder(String id) async {
    final row = await getReminder(id);
    if (row == null) return;
    final dev = await deviceId();
    final now = DateTime.now();
    final updated = row.copyWith(
      deletedAt: Value(now),
      isActive: false,
      updatedAt: now,
      version: row.version + 1,
      deviceId: dev,
      syncedAt: const Value(null),
    );
    await (update(reminders)..where((t) => t.id.equals(id))).write(updated);
    await _enqueue('reminder', id, reminderToWire(updated));
  }

  Future<void> autoRepairUncategorizedTransactions() async {
    try {
      final activeWsId = await activeWorkspaceId();
      if (activeWsId.isNotEmpty) {
        await customStatement(
          'UPDATE transactions SET workspace_id = ? WHERE workspace_id IS NULL OR workspace_id = ""',
          [activeWsId],
        );
      }

      final cats = await (select(categories)..where((t) => t.kind.equals('EXPENSE') & t.deletedAt.isNull())).get();
      if (cats.isNotEmpty) {
        final tagihanCat = cats.where((c) => c.name.toLowerCase().contains('tagihan') || c.name.toLowerCase().contains('operasional')).firstOrNull ?? cats.first;

        await customStatement(
          'UPDATE transactions SET category_id = ? WHERE type = "EXPENSE" AND (category_id IS NULL OR category_id = "")',
          [tagihanCat.id],
        );
      }
    } catch (_) {}
  }

  // ───────────────────────────── Outbox ─────────────────────────────

  Future<void> _enqueue(String entity, String entityId, Map<String, Object?> payload) async {
    await into(outbox).insert(
      OutboxCompanion.insert(
        opId: newId(),
        entity: entity,
        entityId: entityId,
        op: 'upsert',
        payload: jsonEncode(payload),
        createdAt: DateTime.now(),
      ),
    );
  }

  /// Helper generik: insert lalu masukkan ke outbox.
  Future<void> _insertAndSync<T extends Table, D>(
    TableInfo<T, D> table,
    D data,
    String entity,
    Map<String, Object?> Function(D) toWire,
  ) async {
    final wire = toWire(data);
    await into(table).insertOnConflictUpdate(data as Insertable<D>);
    await _enqueue(entity, wire['id'] as String, wire);
  }

  Stream<int> watchPendingCount() {
    return customSelect(
      'SELECT COUNT(*) AS c FROM outbox',
      readsFrom: {outbox},
    ).watchSingle().map((row) => row.read<int>('c'));
  }

  Future<int> pendingCount() async {
    final row = await customSelect('SELECT COUNT(*) AS c FROM outbox').getSingle();
    return row.read<int>('c');
  }

  Future<List<OutboxOp>> pendingOps({int limit = 200}) {
    return (select(outbox)..orderBy([(t) => OrderingTerm.asc(t.createdAt)])..limit(limit)).get();
  }

  Future<void> removeOps(List<String> opIds) async {
    if (opIds.isEmpty) return;
    await (delete(outbox)..where((t) => t.opId.isIn(opIds))).go();
  }

  Future<void> markOpFailed(String opId, String error) async {
    final row = await (select(outbox)..where((t) => t.opId.equals(opId))).getSingleOrNull();
    if (row == null) return;
    await (update(outbox)..where((t) => t.opId.equals(opId))).write(
      OutboxCompanion(
        attempts: Value(row.attempts + 1),
        lastError: Value(error),
      ),
    );
  }

  // ───────────────────────────── Apply remote ─────────────────────────────

  Future<void> applyRemoteChanges(List<Map<String, dynamic>> changes) async {
    if (changes.isEmpty) return;
    await transaction(() async {
      for (final change in changes) {
        final entity = change['entity'] as String;
        final data = Map<String, dynamic>.from(change['data'] as Map);
        switch (entity) {
          case 'project':
            await into(projects).insertOnConflictUpdate(projectFromWire(data));
          case 'task':
            await into(tasks).insertOnConflictUpdate(taskFromWire(data));
          case 'checklistItem':
            await into(checklistItems).insertOnConflictUpdate(checklistFromWire(data));
          case 'taskProgressLog':
            await into(taskProgressLogs).insertOnConflictUpdate(progressLogFromWire(data));
          case 'reminder':
            await into(reminders).insertOnConflictUpdate(reminderFromWire(data));
          case 'calendarEvent':
            await into(calendarEvents).insertOnConflictUpdate(calendarEventFromWire(data));
          case 'wallet':
            await into(wallets).insertOnConflictUpdate(walletFromWire(data));
          case 'category':
            await into(categories).insertOnConflictUpdate(categoryFromWire(data));
          case 'transaction':
            await into(transactions).insertOnConflictUpdate(transactionFromWire(data));
          case 'budget':
            await into(budgets).insertOnConflictUpdate(budgetFromWire(data));
          case 'debt':
            await into(debts).insertOnConflictUpdate(debtFromWire(data));
          case 'asset':
            await into(assets).insertOnConflictUpdate(assetFromWire(data));
          case 'assetValuation':
            await into(assetValuations).insertOnConflictUpdate(assetValuationFromWire(data));
          case 'assetMaintenance':
            await into(assetMaintenances).insertOnConflictUpdate(assetMaintenanceFromWire(data));
          case 'document':
            await into(documents).insertOnConflictUpdate(documentFromWire(data));
          default:
            break;
        }
      }
    });
  }

  Future<void> wipeLocalData() async {
    await transaction(() async {
      await delete(workspaces).go();
      await delete(projects).go();
      await delete(tasks).go();
      await delete(checklistItems).go();
      await delete(taskProgressLogs).go();
      await delete(reminders).go();
      await delete(calendarEvents).go();
      await delete(wallets).go();
      await delete(categories).go();
      await delete(transactions).go();
      await delete(budgets).go();
      await delete(debts).go();
      await delete(assets).go();
      await delete(assetValuations).go();
      await delete(assetMaintenances).go();
      await delete(outbox).go();
    });
    await deleteMeta('lastPullCursor');
    await deleteMeta('activeWorkspaceId');
  }
}

QueryExecutor _openConnection() => openConnection();

/// Helper membuat id baru (UUID v7: urut waktu, aman dibuat offline).
String newId() => _uuid.v7();
