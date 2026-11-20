import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notifications.dart';
import '../../data/local/database.dart';
import '../../data/remote/api_client.dart';
import '../../data/remote/session_store.dart';
import '../../data/sync/sync_engine.dart';
import 'auth_controller.dart';

// ───────────────────────────── Infrastruktur ─────────────────────────────

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final sessionStoreProvider = Provider<SessionStore>((ref) => SessionStore());

final notificationsProvider = Provider<NotificationsService>((ref) {
  return NotificationsService();
});

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(store: ref.watch(sessionStoreProvider));
});

final syncEngineProvider = Provider<SyncEngine>((ref) {
  return SyncEngine(
    db: ref.watch(databaseProvider),
    api: ref.watch(apiClientProvider),
    onSessionExpired: () => ref.read(authControllerProvider.notifier).forceSignOut(),
  );
});

final syncSchedulerProvider = Provider<SyncScheduler>((ref) {
  final scheduler = SyncScheduler(ref.watch(syncEngineProvider));
  ref.onDispose(scheduler.dispose);
  return scheduler;
});

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) => AuthController(ref));

/// Menjadwalkan ulang semua pengingat aktif di perangkat.
///
/// Dipakai saat app dibuka dan setelah izin "alarm tepat waktu" diberikan.
Future<void> rescheduleAllReminders(WidgetRef ref) async {
  final db = ref.read(databaseProvider);
  final notifications = ref.read(notificationsProvider);
  final reminders = await db.listActiveReminders();
  await notifications.rescheduleAll(
    reminders.map(
      (r) => ReminderSchedule(
        id: r.id,
        title: r.title,
        message: r.message,
        triggerAt: r.triggerAt,
        snoozeUntil: r.snoozeUntil,
        recurrenceRule: r.recurrenceRule,
        entityId: r.entityId,
        isActive: r.isActive,
      ),
    ),
  );
}

// ───────────────────────────── Workspace ─────────────────────────────

final workspacesProvider = StreamProvider<List<Workspace>>((ref) {
  return ref.watch(databaseProvider).watchWorkspaces();
});

class ActiveWorkspaceController extends AsyncNotifier<String> {
  @override
  Future<String> build() => ref.watch(databaseProvider).activeWorkspaceId();

  Future<void> select(String id) async {
    await ref.read(databaseProvider).setActiveWorkspace(id);
    state = AsyncData(id);
  }
}

final activeWorkspaceIdProvider =
    AsyncNotifierProvider<ActiveWorkspaceController, String>(ActiveWorkspaceController.new);

final currentWorkspaceProvider = Provider<Workspace?>((ref) {
  final id = ref.watch(activeWorkspaceIdProvider).valueOrNull;
  final list = ref.watch(workspacesProvider).valueOrNull ?? const <Workspace>[];
  if (list.isEmpty) return null;
  return list.firstWhereOrNull((w) => w.id == id) ?? list.first;
});

final workspaceIdProvider = Provider<String>((ref) {
  return ref.watch(currentWorkspaceProvider)?.id ?? '';
});

// ───────────────────────────── Sinkronisasi ─────────────────────────────

final pendingSyncCountProvider = StreamProvider<int>((ref) {
  return ref.watch(databaseProvider).watchPendingCount();
});

final syncStatusProvider = StateProvider<String?>((ref) => null);

// ───────────────────────────── Tugas ─────────────────────────────

final taskFilterProvider = StateProvider<String>((ref) => 'ALL');
final taskSearchProvider = StateProvider<String>((ref) => '');

final tasksProvider = StreamProvider<List<Task>>((ref) {
  final ws = ref.watch(currentWorkspaceProvider);
  if (ws == null) return Stream.value(const <Task>[]);
  return ref.watch(databaseProvider).watchTasks(
        ws.id,
        status: ref.watch(taskFilterProvider),
        search: ref.watch(taskSearchProvider),
      );
});

final todayTasksProvider = StreamProvider<List<Task>>((ref) {
  final ws = ref.watch(currentWorkspaceProvider);
  if (ws == null) return Stream.value(const <Task>[]);
  return ref.watch(databaseProvider).watchTodayTasks(ws.id);
});

final taskDetailProvider = StreamProvider.family<Task?, String>((ref, id) {
  return ref.watch(databaseProvider).watchTask(id);
});

final checklistProvider = StreamProvider.family<List<ChecklistEntry>, String>((ref, taskId) {
  return ref.watch(databaseProvider).watchChecklist(taskId);
});

final progressLogsProvider = StreamProvider.family<List<ProgressLog>, String>((ref, taskId) {
  return ref.watch(databaseProvider).watchProgressLogs(taskId);
});

final projectsProvider = StreamProvider<List<Project>>((ref) {
  final ws = ref.watch(currentWorkspaceProvider);
  if (ws == null) return Stream.value(const <Project>[]);
  return ref.watch(databaseProvider).watchProjects(ws.id);
});

// ───────────────────────────── Keuangan ─────────────────────────────

final selectedMonthProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month);
});

final walletsProvider = StreamProvider<List<Wallet>>((ref) {
  final ws = ref.watch(currentWorkspaceProvider);
  if (ws == null) return Stream.value(const <Wallet>[]);
  return ref.watch(databaseProvider).watchWallets(ws.id);
});

final walletBalancesProvider = StreamProvider<List<WalletBalance>>((ref) {
  final ws = ref.watch(currentWorkspaceProvider);
  if (ws == null) return Stream.value(const <WalletBalance>[]);
  return ref.watch(databaseProvider).watchWalletBalances(ws.id);
});

final totalBalanceProvider = Provider<int>((ref) {
  final balances = ref.watch(walletBalancesProvider).valueOrNull ?? const <WalletBalance>[];
  return balances.fold<int>(0, (sum, b) => sum + b.balance);
});

final categoriesProvider = StreamProvider.family<List<Category>, String>((ref, kind) {
  final ws = ref.watch(currentWorkspaceProvider);
  if (ws == null) return Stream.value(const <Category>[]);
  return ref.watch(databaseProvider).watchCategories(ws.id, kind: kind == 'ALL' ? null : kind);
});

final transactionsProvider = StreamProvider<List<Txn>>((ref) {
  final ws = ref.watch(currentWorkspaceProvider);
  if (ws == null) return Stream.value(const <Txn>[]);
  final month = ref.watch(selectedMonthProvider);
  final from = DateTime(month.year, month.month);
  final to = DateTime(month.year, month.month + 1);
  return ref.watch(databaseProvider).watchTransactions(ws.id, from, to);
});

final recentTransactionsProvider = StreamProvider<List<Txn>>((ref) {
  final ws = ref.watch(currentWorkspaceProvider);
  if (ws == null) return Stream.value(const <Txn>[]);
  return ref.watch(databaseProvider).watchRecentTransactions(ws.id, limit: 5);
});

final monthlySummaryProvider = StreamProvider<FinanceSummary>((ref) {
  final ws = ref.watch(currentWorkspaceProvider);
  if (ws == null) return Stream.value(const FinanceSummary(income: 0, expense: 0, transfer: 0));
  final month = ref.watch(selectedMonthProvider);
  final from = DateTime(month.year, month.month);
  final to = DateTime(month.year, month.month + 1);
  return ref.watch(databaseProvider).watchSummary(ws.id, from, to);
});

final expenseByCategoryProvider = StreamProvider<Map<String, int>>((ref) {
  final ws = ref.watch(currentWorkspaceProvider);
  if (ws == null) return Stream.value(const <String, int>{});
  final month = ref.watch(selectedMonthProvider);
  final from = DateTime(month.year, month.month);
  final to = DateTime(month.year, month.month + 1);
  return ref.watch(databaseProvider).watchExpenseByCategory(ws.id, from, to);
});

final budgetsProvider = StreamProvider<List<Budget>>((ref) {
  final ws = ref.watch(currentWorkspaceProvider);
  if (ws == null) return Stream.value(const <Budget>[]);
  return ref.watch(databaseProvider).watchBudgets(ws.id);
});

final sixMonthTransactionsProvider = StreamProvider<List<Txn>>((ref) {
  final ws = ref.watch(currentWorkspaceProvider);
  if (ws == null) return Stream.value(const <Txn>[]);
  final now = DateTime.now();
  final from = DateTime(now.year, now.month - 5);
  final to = DateTime(now.year, now.month + 1);
  return ref.watch(databaseProvider).watchTransactions(ws.id, from, to);
});

final debtsProvider = StreamProvider<List<Debt>>((ref) {
  final ws = ref.watch(currentWorkspaceProvider);
  if (ws == null) return Stream.value(const <Debt>[]);
  return ref.watch(databaseProvider).watchDebts(ws.id);
});

// ───────────────────────────── Aset ─────────────────────────────

final assetsProvider = StreamProvider<List<Asset>>((ref) {
  final ws = ref.watch(currentWorkspaceProvider);
  if (ws == null) return Stream.value(const <Asset>[]);
  return ref.watch(databaseProvider).watchAssets(ws.id);
});

final assetTotalProvider = Provider<int>((ref) {
  final assets = ref.watch(assetsProvider).valueOrNull ?? const <Asset>[];
  return assets
      .where((a) => a.status == 'ACTIVE')
      .fold<int>(0, (sum, a) => sum + a.currentValue);
});

final assetProvider = StreamProvider.family<Asset?, String>((ref, id) {
  return ref.watch(databaseProvider).watchAsset(id);
});

final assetValuationsProvider =
    StreamProvider.family<List<AssetValuation>, String>((ref, assetId) {
  return ref.watch(databaseProvider).watchValuations(assetId);
});

final assetMaintenancesProvider =
    StreamProvider.family<List<AssetMaintenance>, String>((ref, assetId) {
  return ref.watch(databaseProvider).watchMaintenances(assetId);
});

// ───────────────────────────── Dokumen ─────────────────────────────

final docCategoryFilterProvider = StateProvider<String>((ref) => 'ALL');
final docSearchProvider = StateProvider<String>((ref) => '');

final documentsProvider = StreamProvider<List<DocEntry>>((ref) {
  final ws = ref.watch(currentWorkspaceProvider);
  if (ws == null) return Stream.value(const <DocEntry>[]);
  return ref.watch(databaseProvider).watchDocuments(
        ws.id,
        category: ref.watch(docCategoryFilterProvider),
        search: ref.watch(docSearchProvider),
      );
});

// ───────────────────────────── Kalender & pengingat ─────────────────────────────

final calendarMonthProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, 1);
});

final eventsProvider = StreamProvider<List<CalendarEvent>>((ref) {
  final ws = ref.watch(currentWorkspaceProvider);
  if (ws == null) return Stream.value(const <CalendarEvent>[]);
  final month = ref.watch(calendarMonthProvider);
  final from = DateTime(month.year, month.month).subtract(const Duration(days: 7));
  final to = DateTime(month.year, month.month + 1).add(const Duration(days: 7));
  return ref.watch(databaseProvider).watchEvents(ws.id, from, to);
});

final remindersProvider = StreamProvider<List<Reminder>>((ref) {
  final ws = ref.watch(currentWorkspaceProvider);
  if (ws == null) return Stream.value(const <Reminder>[]);
  return ref.watch(databaseProvider).watchReminders(ws.id);
});
