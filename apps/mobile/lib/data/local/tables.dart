import 'package:drift/drift.dart';

/// Skema database lokal (SQLite) yang mencerminkan entitas server.
///
/// Semua tabel sinkron punya kolom:
///  - createdAt / updatedAt / deletedAt  → waktu (Date)
///  - version                            → optimistic concurrency
///  - deviceId                           → asal perubahan terakhir
///  - syncedAt                           → terakhir kali versi ini dikonfirmasi server

class Workspaces extends Table {
  @override
  String get tableName => 'workspaces';

  TextColumn get id => text()();
  TextColumn get type => text()(); // PERSONAL | COMPANY
  TextColumn get name => text()();
  TextColumn get color => text().withDefault(const Constant('#2563EB'))();
  TextColumn get icon => text().withDefault(const Constant('briefcase'))();
  DateTimeColumn get archivedAt => dateTime().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get deviceId => text()();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Projects extends Table {
  @override
  String get tableName => 'projects';

  TextColumn get id => text()();
  TextColumn get workspaceId => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get color => text().withDefault(const Constant('#6366F1'))();
  TextColumn get status => text().withDefault(const Constant('active'))();
  DateTimeColumn get startAt => dateTime().nullable()();
  DateTimeColumn get dueAt => dateTime().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get deviceId => text()();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Task')
class Tasks extends Table {
  @override
  String get tableName => 'tasks';

  TextColumn get id => text()();
  TextColumn get workspaceId => text()();
  TextColumn get projectId => text().nullable()();
  TextColumn get parentTaskId => text().nullable()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('TODO'))();
  IntColumn get priority => integer().withDefault(const Constant(2))();
  IntColumn get progress => integer().withDefault(const Constant(0))();
  DateTimeColumn get startAt => dateTime().nullable()();
  DateTimeColumn get dueAt => dateTime().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  IntColumn get estimatedMinutes => integer().nullable()();
  IntColumn get actualMinutes => integer().withDefault(const Constant(0))();
  TextColumn get tags => text().withDefault(const Constant('[]'))(); // JSON array
  TextColumn get recurrenceRule => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get deviceId => text()();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ChecklistEntry')
class ChecklistItems extends Table {
  @override
  String get tableName => 'checklist_items';

  TextColumn get id => text()();
  TextColumn get workspaceId => text()();
  TextColumn get taskId => text()();
  TextColumn get title => text()();
  BoolColumn get isDone => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get deviceId => text()();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ProgressLog')
class TaskProgressLogs extends Table {
  @override
  String get tableName => 'task_progress_logs';

  TextColumn get id => text()();
  TextColumn get workspaceId => text()();
  TextColumn get taskId => text()();
  IntColumn get progressBefore => integer()();
  IntColumn get progressAfter => integer()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get occurredAt => dateTime()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get deviceId => text()();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Reminder')
class Reminders extends Table {
  @override
  String get tableName => 'reminders';

  TextColumn get id => text()();
  TextColumn get workspaceId => text()();
  TextColumn get entityType => text().withDefault(const Constant('CUSTOM'))();
  TextColumn get entityId => text().nullable()();
  TextColumn get title => text()();
  TextColumn get message => text().nullable()();
  DateTimeColumn get triggerAt => dateTime()();
  TextColumn get recurrenceRule => text().nullable()();
  DateTimeColumn get snoozeUntil => dateTime().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get firedAt => dateTime().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get deviceId => text()();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('CalendarEvent')
class CalendarEvents extends Table {
  @override
  String get tableName => 'calendar_events';

  TextColumn get id => text()();
  TextColumn get workspaceId => text()();
  TextColumn get title => text()();
  TextColumn get location => text().nullable()();
  DateTimeColumn get startAt => dateTime()();
  DateTimeColumn get endAt => dateTime()();
  BoolColumn get allDay => boolean().withDefault(const Constant(false))();
  TextColumn get recurrenceRule => text().nullable()();
  TextColumn get linkedTaskId => text().nullable()();
  TextColumn get note => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get deviceId => text()();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Wallet')
class Wallets extends Table {
  @override
  String get tableName => 'wallets';

  TextColumn get id => text()();
  TextColumn get workspaceId => text()();
  TextColumn get name => text()();
  TextColumn get type => text().withDefault(const Constant('CASH'))();
  IntColumn get initialBalance => integer().withDefault(const Constant(0))();
  TextColumn get currency => text().withDefault(const Constant('IDR'))();
  DateTimeColumn get archivedAt => dateTime().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get deviceId => text()();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Category')
class Categories extends Table {
  @override
  String get tableName => 'categories';

  TextColumn get id => text()();
  TextColumn get workspaceId => text()();
  TextColumn get name => text()();
  TextColumn get kind => text()(); // INCOME | EXPENSE
  TextColumn get parentId => text().nullable()();
  TextColumn get icon => text().withDefault(const Constant('label'))();
  TextColumn get color => text().withDefault(const Constant('#64748B'))();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get deviceId => text()();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Txn')
class Transactions extends Table {
  @override
  String get tableName => 'transactions';

  TextColumn get id => text()();
  TextColumn get workspaceId => text()();
  TextColumn get walletId => text()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get budgetId => text().nullable()();
  TextColumn get type => text()(); // INCOME | EXPENSE | TRANSFER
  IntColumn get amount => integer()();
  IntColumn get fee => integer().withDefault(const Constant(0))();
  TextColumn get transferGroupId => text().nullable()();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get note => text().nullable()();
  TextColumn get payee => text().nullable()();
  TextColumn get attachmentId => text().nullable()();
  BoolColumn get isReconciled => boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get deviceId => text()();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Budget')
class Budgets extends Table {
  @override
  String get tableName => 'budgets';

  TextColumn get id => text()();
  TextColumn get workspaceId => text()();
  TextColumn get categoryId => text()();
  TextColumn get name => text().nullable()();
  TextColumn get period => text().withDefault(const Constant('MONTHLY'))();
  IntColumn get amount => integer()();
  DateTimeColumn get startAt => dateTime()();
  DateTimeColumn get endAt => dateTime().nullable()();
  BoolColumn get rollover => boolean().withDefault(const Constant(false))();
  TextColumn get note => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get deviceId => text()();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Debt')
class Debts extends Table {
  @override
  String get tableName => 'debts';

  TextColumn get id => text()();
  TextColumn get workspaceId => text()();
  TextColumn get counterparty => text()();
  TextColumn get direction => text()(); // RECEIVABLE | PAYABLE
  TextColumn get category => text().nullable()(); // MORTGAGE | VEHICLE | BANK | PERSONAL | CREDIT_CARD
  TextColumn get assetId => text().nullable()();
  IntColumn get principal => integer()();
  IntColumn get remaining => integer()();
  IntColumn get monthlyInstallment => integer().nullable()();
  IntColumn get tenorMonths => integer().nullable()();
  TextColumn get contractNumber => text().nullable()();
  DateTimeColumn get dueAt => dateTime().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('open'))();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get deviceId => text()();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Asset')
class Assets extends Table {
  @override
  String get tableName => 'assets';

  TextColumn get id => text()();
  TextColumn get workspaceId => text()();
  TextColumn get name => text()();
  TextColumn get category => text().withDefault(const Constant('other'))();
  DateTimeColumn get purchaseAt => dateTime().nullable()();
  IntColumn get purchasePrice => integer().nullable()();
  IntColumn get currentValue => integer().withDefault(const Constant(0))();
  TextColumn get depreciationMethod => text().withDefault(const Constant('NONE'))();
  IntColumn get usefulLifeMonths => integer().nullable()();
  IntColumn get salvageValue => integer().nullable()();
  TextColumn get status => text().withDefault(const Constant('ACTIVE'))();
  TextColumn get serialNumber => text().nullable()();
  TextColumn get debtId => text().nullable()();
  TextColumn get attachments => text().nullable()();
  TextColumn get note => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get deviceId => text()();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('AssetValuation')
class AssetValuations extends Table {
  @override
  String get tableName => 'asset_valuations';

  TextColumn get id => text()();
  TextColumn get workspaceId => text()();
  TextColumn get assetId => text()();
  IntColumn get value => integer()();
  DateTimeColumn get valuedAt => dateTime()();
  TextColumn get source => text().withDefault(const Constant('MANUAL'))();
  TextColumn get note => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get deviceId => text()();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('AssetMaintenance')
class AssetMaintenances extends Table {
  @override
  String get tableName => 'asset_maintenances';

  TextColumn get id => text()();
  TextColumn get workspaceId => text()();
  TextColumn get assetId => text()();
  TextColumn get title => text()();
  IntColumn get cost => integer().withDefault(const Constant(0))();
  DateTimeColumn get performedAt => dateTime()();
  DateTimeColumn get nextDueAt => dateTime().nullable()();
  TextColumn get note => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get deviceId => text()();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('DocEntry')
class Documents extends Table {
  @override
  String get tableName => 'documents';

  TextColumn get id => text()();
  TextColumn get workspaceId => text()();
  TextColumn get title => text()();
  TextColumn get category => text().withDefault(const Constant('IDENTITY'))(); // IDENTITY | LEGAL | TAX | BUSINESS | OTHER
  TextColumn get docNumber => text().nullable()();
  TextColumn get holderName => text().nullable()();
  DateTimeColumn get issueDate => dateTime().nullable()();
  DateTimeColumn get expiryDate => dateTime().nullable()();
  TextColumn get attachments => text().nullable()();
  TextColumn get note => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get deviceId => text()();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Antrean operasi yang belum terkirim ke server (outbox pattern).
@DataClassName('OutboxOp')
class Outbox extends Table {
  @override
  String get tableName => 'outbox';

  TextColumn get opId => text()();
  TextColumn get entity => text()();
  TextColumn get entityId => text()();
  TextColumn get op => text()(); // upsert | delete
  TextColumn get payload => text()(); // JSON
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column> get primaryKey => {opId};
}

/// State sinkronisasi (cursor pull, waktu sync terakhir, user aktif).
@DataClassName('SyncMeta')
class SyncStates extends Table {
  @override
  String get tableName => 'sync_state';

  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
