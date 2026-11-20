import 'dart:convert';

import 'package:drift/drift.dart';

import 'database.dart';

/// Konversi antara payload wire (Map, epoch millis) dan baris database lokal.
///
/// Kunci payload memakai camelCase dan identik dengan skema Prisma di server.

DateTime _dt(Object? v) => DateTime.fromMillisecondsSinceEpoch((v as num).toInt());
DateTime? _dtN(Object? v) => v == null ? null : _dt(v);
int _ms(DateTime d) => d.millisecondsSinceEpoch;

List<String> _tags(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List) return decoded.map((e) => e.toString()).toList();
  } catch (_) {}
  return const [];
}

// ───────────────────────────── Workspace ─────────────────────────────

Map<String, Object?> workspaceToWire(Workspace w) => {
      'id': w.id,
      'workspaceId': w.id,
      'type': w.type,
      'name': w.name,
      'color': w.color,
      'icon': w.icon,
      'archivedAt': w.archivedAt == null ? null : _ms(w.archivedAt!),
      'createdAt': _ms(w.createdAt),
      'updatedAt': _ms(w.updatedAt),
      'deletedAt': w.deletedAt == null ? null : _ms(w.deletedAt!),
      'version': w.version,
      'deviceId': w.deviceId,
    };

// ───────────────────────────── Project ─────────────────────────────

Map<String, Object?> projectToWire(Project p) => {
      'id': p.id,
      'workspaceId': p.workspaceId,
      'name': p.name,
      'description': p.description,
      'color': p.color,
      'status': p.status,
      'startAt': p.startAt == null ? null : _ms(p.startAt!),
      'dueAt': p.dueAt == null ? null : _ms(p.dueAt!),
      'createdAt': _ms(p.createdAt),
      'updatedAt': _ms(p.updatedAt),
      'deletedAt': p.deletedAt == null ? null : _ms(p.deletedAt!),
      'version': p.version,
      'deviceId': p.deviceId,
    };

ProjectsCompanion projectFromWire(Map<String, dynamic> w) => ProjectsCompanion(
      id: Value(w['id'] as String),
      workspaceId: Value(w['workspaceId'] as String),
      name: Value(w['name'] as String),
      description: Value(w['description'] as String?),
      color: Value((w['color'] as String?) ?? '#6366F1'),
      status: Value((w['status'] as String?) ?? 'active'),
      startAt: Value(_dtN(w['startAt'])),
      dueAt: Value(_dtN(w['dueAt'])),
      createdAt: Value(_dt(w['createdAt'])),
      updatedAt: Value(_dt(w['updatedAt'])),
      deletedAt: Value(_dtN(w['deletedAt'])),
      version: Value((w['version'] as num?)?.toInt() ?? 1),
      deviceId: Value(w['deviceId'] as String),
      syncedAt: Value(DateTime.now()),
    );

// ───────────────────────────── Task ─────────────────────────────

Map<String, Object?> taskToWire(Task t) => {
      'id': t.id,
      'workspaceId': t.workspaceId,
      'projectId': t.projectId,
      'parentTaskId': t.parentTaskId,
      'title': t.title,
      'description': t.description,
      'status': t.status,
      'priority': t.priority,
      'progress': t.progress,
      'startAt': t.startAt == null ? null : _ms(t.startAt!),
      'dueAt': t.dueAt == null ? null : _ms(t.dueAt!),
      'completedAt': t.completedAt == null ? null : _ms(t.completedAt!),
      'estimatedMinutes': t.estimatedMinutes,
      'actualMinutes': t.actualMinutes,
      'tags': _tags(t.tags),
      'recurrenceRule': t.recurrenceRule,
      'createdAt': _ms(t.createdAt),
      'updatedAt': _ms(t.updatedAt),
      'deletedAt': t.deletedAt == null ? null : _ms(t.deletedAt!),
      'version': t.version,
      'deviceId': t.deviceId,
    };

TasksCompanion taskFromWire(Map<String, dynamic> w) => TasksCompanion(
      id: Value(w['id'] as String),
      workspaceId: Value(w['workspaceId'] as String),
      projectId: Value(w['projectId'] as String?),
      parentTaskId: Value(w['parentTaskId'] as String?),
      title: Value(w['title'] as String),
      description: Value(w['description'] as String?),
      status: Value((w['status'] as String?) ?? 'TODO'),
      priority: Value((w['priority'] as num?)?.toInt() ?? 2),
      progress: Value((w['progress'] as num?)?.toInt() ?? 0),
      startAt: Value(_dtN(w['startAt'])),
      dueAt: Value(_dtN(w['dueAt'])),
      completedAt: Value(_dtN(w['completedAt'])),
      estimatedMinutes: Value((w['estimatedMinutes'] as num?)?.toInt()),
      actualMinutes: Value((w['actualMinutes'] as num?)?.toInt() ?? 0),
      tags: Value(jsonEncode(w['tags'] ?? const <String>[])),
      recurrenceRule: Value(w['recurrenceRule'] as String?),
      createdAt: Value(_dt(w['createdAt'])),
      updatedAt: Value(_dt(w['updatedAt'])),
      deletedAt: Value(_dtN(w['deletedAt'])),
      version: Value((w['version'] as num?)?.toInt() ?? 1),
      deviceId: Value(w['deviceId'] as String),
      syncedAt: Value(DateTime.now()),
    );

// ───────────────────────────── Checklist ─────────────────────────────

Map<String, Object?> checklistToWire(ChecklistEntry c) => {
      'id': c.id,
      'workspaceId': c.workspaceId,
      'taskId': c.taskId,
      'title': c.title,
      'isDone': c.isDone,
      'sortOrder': c.sortOrder,
      'createdAt': _ms(c.createdAt),
      'updatedAt': _ms(c.updatedAt),
      'deletedAt': c.deletedAt == null ? null : _ms(c.deletedAt!),
      'version': c.version,
      'deviceId': c.deviceId,
    };

ChecklistItemsCompanion checklistFromWire(Map<String, dynamic> w) => ChecklistItemsCompanion(
      id: Value(w['id'] as String),
      workspaceId: Value(w['workspaceId'] as String),
      taskId: Value(w['taskId'] as String),
      title: Value(w['title'] as String),
      isDone: Value((w['isDone'] as bool?) ?? false),
      sortOrder: Value((w['sortOrder'] as num?)?.toInt() ?? 0),
      createdAt: Value(_dt(w['createdAt'])),
      updatedAt: Value(_dt(w['updatedAt'])),
      deletedAt: Value(_dtN(w['deletedAt'])),
      version: Value((w['version'] as num?)?.toInt() ?? 1),
      deviceId: Value(w['deviceId'] as String),
      syncedAt: Value(DateTime.now()),
    );

// ───────────────────────── Progress log ─────────────────────────

Map<String, Object?> progressLogToWire(ProgressLog p) => {
      'id': p.id,
      'workspaceId': p.workspaceId,
      'taskId': p.taskId,
      'progressBefore': p.progressBefore,
      'progressAfter': p.progressAfter,
      'note': p.note,
      'occurredAt': _ms(p.occurredAt),
      'createdAt': _ms(p.createdAt),
      'updatedAt': _ms(p.updatedAt),
      'deletedAt': p.deletedAt == null ? null : _ms(p.deletedAt!),
      'version': p.version,
      'deviceId': p.deviceId,
    };

TaskProgressLogsCompanion progressLogFromWire(Map<String, dynamic> w) => TaskProgressLogsCompanion(
      id: Value(w['id'] as String),
      workspaceId: Value(w['workspaceId'] as String),
      taskId: Value(w['taskId'] as String),
      progressBefore: Value((w['progressBefore'] as num).toInt()),
      progressAfter: Value((w['progressAfter'] as num).toInt()),
      note: Value(w['note'] as String?),
      occurredAt: Value(_dt(w['occurredAt'])),
      createdAt: Value(_dt(w['createdAt'])),
      updatedAt: Value(_dt(w['updatedAt'])),
      deletedAt: Value(_dtN(w['deletedAt'])),
      version: Value((w['version'] as num?)?.toInt() ?? 1),
      deviceId: Value(w['deviceId'] as String),
      syncedAt: Value(DateTime.now()),
    );

// ───────────────────────────── Reminder ─────────────────────────────

Map<String, Object?> reminderToWire(Reminder r) => {
      'id': r.id,
      'workspaceId': r.workspaceId,
      'entityType': r.entityType,
      'entityId': r.entityId,
      'title': r.title,
      'message': r.message,
      'triggerAt': _ms(r.triggerAt),
      'recurrenceRule': r.recurrenceRule,
      'snoozeUntil': r.snoozeUntil == null ? null : _ms(r.snoozeUntil!),
      'isActive': r.isActive,
      'firedAt': r.firedAt == null ? null : _ms(r.firedAt!),
      'createdAt': _ms(r.createdAt),
      'updatedAt': _ms(r.updatedAt),
      'deletedAt': r.deletedAt == null ? null : _ms(r.deletedAt!),
      'version': r.version,
      'deviceId': r.deviceId,
    };

RemindersCompanion reminderFromWire(Map<String, dynamic> w) => RemindersCompanion(
      id: Value(w['id'] as String),
      workspaceId: Value(w['workspaceId'] as String),
      entityType: Value((w['entityType'] as String?) ?? 'CUSTOM'),
      entityId: Value(w['entityId'] as String?),
      title: Value(w['title'] as String),
      message: Value(w['message'] as String?),
      triggerAt: Value(_dt(w['triggerAt'])),
      recurrenceRule: Value(w['recurrenceRule'] as String?),
      snoozeUntil: Value(_dtN(w['snoozeUntil'])),
      isActive: Value((w['isActive'] as bool?) ?? true),
      firedAt: Value(_dtN(w['firedAt'])),
      createdAt: Value(_dt(w['createdAt'])),
      updatedAt: Value(_dt(w['updatedAt'])),
      deletedAt: Value(_dtN(w['deletedAt'])),
      version: Value((w['version'] as num?)?.toInt() ?? 1),
      deviceId: Value(w['deviceId'] as String),
      syncedAt: Value(DateTime.now()),
    );

// ───────────────────────── Calendar event ─────────────────────────

Map<String, Object?> calendarEventToWire(CalendarEvent e) => {
      'id': e.id,
      'workspaceId': e.workspaceId,
      'title': e.title,
      'location': e.location,
      'startAt': _ms(e.startAt),
      'endAt': _ms(e.endAt),
      'allDay': e.allDay,
      'recurrenceRule': e.recurrenceRule,
      'linkedTaskId': e.linkedTaskId,
      'note': e.note,
      'createdAt': _ms(e.createdAt),
      'updatedAt': _ms(e.updatedAt),
      'deletedAt': e.deletedAt == null ? null : _ms(e.deletedAt!),
      'version': e.version,
      'deviceId': e.deviceId,
    };

CalendarEventsCompanion calendarEventFromWire(Map<String, dynamic> w) => CalendarEventsCompanion(
      id: Value(w['id'] as String),
      workspaceId: Value(w['workspaceId'] as String),
      title: Value(w['title'] as String),
      location: Value(w['location'] as String?),
      startAt: Value(_dt(w['startAt'])),
      endAt: Value(_dt(w['endAt'])),
      allDay: Value((w['allDay'] as bool?) ?? false),
      recurrenceRule: Value(w['recurrenceRule'] as String?),
      linkedTaskId: Value(w['linkedTaskId'] as String?),
      note: Value(w['note'] as String?),
      createdAt: Value(_dt(w['createdAt'])),
      updatedAt: Value(_dt(w['updatedAt'])),
      deletedAt: Value(_dtN(w['deletedAt'])),
      version: Value((w['version'] as num?)?.toInt() ?? 1),
      deviceId: Value(w['deviceId'] as String),
      syncedAt: Value(DateTime.now()),
    );

// ───────────────────────────── Wallet ─────────────────────────────

Map<String, Object?> walletToWire(Wallet w) => {
      'id': w.id,
      'workspaceId': w.workspaceId,
      'name': w.name,
      'type': w.type,
      'initialBalance': w.initialBalance,
      'currency': w.currency,
      'archivedAt': w.archivedAt == null ? null : _ms(w.archivedAt!),
      'createdAt': _ms(w.createdAt),
      'updatedAt': _ms(w.updatedAt),
      'deletedAt': w.deletedAt == null ? null : _ms(w.deletedAt!),
      'version': w.version,
      'deviceId': w.deviceId,
    };

WalletsCompanion walletFromWire(Map<String, dynamic> w) => WalletsCompanion(
      id: Value(w['id'] as String),
      workspaceId: Value(w['workspaceId'] as String),
      name: Value(w['name'] as String),
      type: Value((w['type'] as String?) ?? 'CASH'),
      initialBalance: Value((w['initialBalance'] as num?)?.toInt() ?? 0),
      currency: Value((w['currency'] as String?) ?? 'IDR'),
      archivedAt: Value(_dtN(w['archivedAt'])),
      createdAt: Value(_dt(w['createdAt'])),
      updatedAt: Value(_dt(w['updatedAt'])),
      deletedAt: Value(_dtN(w['deletedAt'])),
      version: Value((w['version'] as num?)?.toInt() ?? 1),
      deviceId: Value(w['deviceId'] as String),
      syncedAt: Value(DateTime.now()),
    );

// ───────────────────────────── Category ─────────────────────────────

Map<String, Object?> categoryToWire(Category c) => {
      'id': c.id,
      'workspaceId': c.workspaceId,
      'name': c.name,
      'kind': c.kind,
      'parentId': c.parentId,
      'icon': c.icon,
      'color': c.color,
      'createdAt': _ms(c.createdAt),
      'updatedAt': _ms(c.updatedAt),
      'deletedAt': c.deletedAt == null ? null : _ms(c.deletedAt!),
      'version': c.version,
      'deviceId': c.deviceId,
    };

CategoriesCompanion categoryFromWire(Map<String, dynamic> w) => CategoriesCompanion(
      id: Value(w['id'] as String),
      workspaceId: Value(w['workspaceId'] as String),
      name: Value(w['name'] as String),
      kind: Value(w['kind'] as String),
      parentId: Value(w['parentId'] as String?),
      icon: Value((w['icon'] as String?) ?? 'label'),
      color: Value((w['color'] as String?) ?? '#64748B'),
      createdAt: Value(_dt(w['createdAt'])),
      updatedAt: Value(_dt(w['updatedAt'])),
      deletedAt: Value(_dtN(w['deletedAt'])),
      version: Value((w['version'] as num?)?.toInt() ?? 1),
      deviceId: Value(w['deviceId'] as String),
      syncedAt: Value(DateTime.now()),
    );

// ───────────────────────────── Transaction ─────────────────────────────

Map<String, Object?> transactionToWire(Txn t) => {
      'id': t.id,
      'workspaceId': t.workspaceId,
      'walletId': t.walletId,
      'categoryId': t.categoryId,
      'budgetId': t.budgetId,
      'type': t.type,
      'amount': t.amount,
      'fee': t.fee,
      'transferGroupId': t.transferGroupId,
      'occurredAt': _ms(t.occurredAt),
      'note': t.note,
      'payee': t.payee,
      'attachmentId': t.attachmentId,
      'isReconciled': t.isReconciled,
      'createdAt': _ms(t.createdAt),
      'updatedAt': _ms(t.updatedAt),
      'deletedAt': t.deletedAt == null ? null : _ms(t.deletedAt!),
      'version': t.version,
      'deviceId': t.deviceId,
    };

TransactionsCompanion transactionFromWire(Map<String, dynamic> w) => TransactionsCompanion(
      id: Value(w['id'] as String),
      workspaceId: Value(w['workspaceId'] as String),
      walletId: Value(w['walletId'] as String),
      categoryId: Value(w['categoryId'] as String?),
      budgetId: Value(w['budgetId'] as String?),
      type: Value(w['type'] as String),
      amount: Value((w['amount'] as num).toInt()),
      fee: Value((w['fee'] as num?)?.toInt() ?? 0),
      transferGroupId: Value(w['transferGroupId'] as String?),
      occurredAt: Value(_dt(w['occurredAt'])),
      note: Value(w['note'] as String?),
      payee: Value(w['payee'] as String?),
      attachmentId: Value(w['attachmentId'] as String?),
      isReconciled: Value((w['isReconciled'] as bool?) ?? false),
      createdAt: Value(_dt(w['createdAt'])),
      updatedAt: Value(_dt(w['updatedAt'])),
      deletedAt: Value(_dtN(w['deletedAt'])),
      version: Value((w['version'] as num?)?.toInt() ?? 1),
      deviceId: Value(w['deviceId'] as String),
      syncedAt: Value(DateTime.now()),
    );

// ───────────────────────────── Budget ─────────────────────────────

Map<String, Object?> budgetToWire(Budget b) => {
      'id': b.id,
      'workspaceId': b.workspaceId,
      'categoryId': b.categoryId,
      'name': b.name,
      'period': b.period,
      'amount': b.amount,
      'startAt': _ms(b.startAt),
      'endAt': b.endAt == null ? null : _ms(b.endAt!),
      'rollover': b.rollover,
      'note': b.note,
      'createdAt': _ms(b.createdAt),
      'updatedAt': _ms(b.updatedAt),
      'deletedAt': b.deletedAt == null ? null : _ms(b.deletedAt!),
      'version': b.version,
      'deviceId': b.deviceId,
    };

BudgetsCompanion budgetFromWire(Map<String, dynamic> w) => BudgetsCompanion(
      id: Value(w['id'] as String),
      workspaceId: Value(w['workspaceId'] as String),
      categoryId: Value(w['categoryId'] as String),
      name: Value(w['name'] as String?),
      period: Value((w['period'] as String?) ?? 'MONTHLY'),
      amount: Value((w['amount'] as num).toInt()),
      startAt: Value(_dt(w['startAt'])),
      endAt: Value(_dtN(w['endAt'])),
      rollover: Value((w['rollover'] as bool?) ?? false),
      note: Value(w['note'] as String?),
      createdAt: Value(_dt(w['createdAt'])),
      updatedAt: Value(_dt(w['updatedAt'])),
      deletedAt: Value(_dtN(w['deletedAt'])),
      version: Value((w['version'] as num?)?.toInt() ?? 1),
      deviceId: Value(w['deviceId'] as String),
      syncedAt: Value(DateTime.now()),
    );

// ───────────────────────────── Debt ─────────────────────────────

Map<String, Object?> debtToWire(Debt d) => {
      'id': d.id,
      'workspaceId': d.workspaceId,
      'counterparty': d.counterparty,
      'direction': d.direction,
      'category': d.category,
      'assetId': d.assetId,
      'principal': d.principal,
      'remaining': d.remaining,
      'monthlyInstallment': d.monthlyInstallment,
      'tenorMonths': d.tenorMonths,
      'contractNumber': d.contractNumber,
      'dueAt': d.dueAt == null ? null : _ms(d.dueAt!),
      'note': d.note,
      'status': d.status,
      'createdAt': _ms(d.createdAt),
      'updatedAt': _ms(d.updatedAt),
      'deletedAt': d.deletedAt == null ? null : _ms(d.deletedAt!),
      'version': d.version,
      'deviceId': d.deviceId,
    };

DebtsCompanion debtFromWire(Map<String, dynamic> w) => DebtsCompanion(
      id: Value(w['id'] as String),
      workspaceId: Value(w['workspaceId'] as String),
      counterparty: Value(w['counterparty'] as String),
      direction: Value(w['direction'] as String),
      category: Value(w['category'] as String?),
      assetId: Value(w['assetId'] as String?),
      principal: Value((w['principal'] as num).toInt()),
      remaining: Value((w['remaining'] as num).toInt()),
      monthlyInstallment: Value((w['monthlyInstallment'] as num?)?.toInt()),
      tenorMonths: Value((w['tenorMonths'] as num?)?.toInt()),
      contractNumber: Value(w['contractNumber'] as String?),
      dueAt: Value(_dtN(w['dueAt'])),
      note: Value(w['note'] as String?),
      status: Value((w['status'] as String?) ?? 'open'),
      createdAt: Value(_dt(w['createdAt'])),
      updatedAt: Value(_dt(w['updatedAt'])),
      deletedAt: Value(_dtN(w['deletedAt'])),
      version: Value((w['version'] as num?)?.toInt() ?? 1),
      deviceId: Value(w['deviceId'] as String),
      syncedAt: Value(DateTime.now()),
    );

// ───────────────────────────── Asset ─────────────────────────────

Map<String, Object?> assetToWire(Asset a) => {
      'id': a.id,
      'workspaceId': a.workspaceId,
      'name': a.name,
      'category': a.category,
      'purchaseAt': a.purchaseAt == null ? null : _ms(a.purchaseAt!),
      'purchasePrice': a.purchasePrice,
      'currentValue': a.currentValue,
      'depreciationMethod': a.depreciationMethod,
      'usefulLifeMonths': a.usefulLifeMonths,
      'salvageValue': a.salvageValue,
      'status': a.status,
      'serialNumber': a.serialNumber,
      'debtId': a.debtId,
      'attachments': a.attachments,
      'note': a.note,
      'createdAt': _ms(a.createdAt),
      'updatedAt': _ms(a.updatedAt),
      'deletedAt': a.deletedAt == null ? null : _ms(a.deletedAt!),
      'version': a.version,
      'deviceId': a.deviceId,
    };

AssetsCompanion assetFromWire(Map<String, dynamic> w) => AssetsCompanion(
      id: Value(w['id'] as String),
      workspaceId: Value(w['workspaceId'] as String),
      name: Value(w['name'] as String),
      category: Value((w['category'] as String?) ?? 'other'),
      purchaseAt: Value(_dtN(w['purchaseAt'])),
      purchasePrice: Value((w['purchasePrice'] as num?)?.toInt()),
      currentValue: Value((w['currentValue'] as num?)?.toInt() ?? 0),
      depreciationMethod: Value((w['depreciationMethod'] as String?) ?? 'NONE'),
      usefulLifeMonths: Value((w['usefulLifeMonths'] as num?)?.toInt()),
      salvageValue: Value((w['salvageValue'] as num?)?.toInt()),
      status: Value((w['status'] as String?) ?? 'ACTIVE'),
      serialNumber: Value(w['serialNumber'] as String?),
      debtId: Value(w['debtId'] as String?),
      attachments: Value(w['attachments'] as String?),
      note: Value(w['note'] as String?),
      createdAt: Value(_dt(w['createdAt'])),
      updatedAt: Value(_dt(w['updatedAt'])),
      deletedAt: Value(_dtN(w['deletedAt'])),
      version: Value((w['version'] as num?)?.toInt() ?? 1),
      deviceId: Value(w['deviceId'] as String),
      syncedAt: Value(DateTime.now()),
    );

// ───────────────────────── Asset valuation ─────────────────────────

Map<String, Object?> assetValuationToWire(AssetValuation v) => {
      'id': v.id,
      'workspaceId': v.workspaceId,
      'assetId': v.assetId,
      'value': v.value,
      'valuedAt': _ms(v.valuedAt),
      'source': v.source,
      'note': v.note,
      'createdAt': _ms(v.createdAt),
      'updatedAt': _ms(v.updatedAt),
      'deletedAt': v.deletedAt == null ? null : _ms(v.deletedAt!),
      'version': v.version,
      'deviceId': v.deviceId,
    };

AssetValuationsCompanion assetValuationFromWire(Map<String, dynamic> w) => AssetValuationsCompanion(
      id: Value(w['id'] as String),
      workspaceId: Value(w['workspaceId'] as String),
      assetId: Value(w['assetId'] as String),
      value: Value((w['value'] as num).toInt()),
      valuedAt: Value(_dt(w['valuedAt'])),
      source: Value((w['source'] as String?) ?? 'MANUAL'),
      note: Value(w['note'] as String?),
      createdAt: Value(_dt(w['createdAt'])),
      updatedAt: Value(_dt(w['updatedAt'])),
      deletedAt: Value(_dtN(w['deletedAt'])),
      version: Value((w['version'] as num?)?.toInt() ?? 1),
      deviceId: Value(w['deviceId'] as String),
      syncedAt: Value(DateTime.now()),
    );

// ──────────────────────── Asset maintenance ────────────────────────

Map<String, Object?> assetMaintenanceToWire(AssetMaintenance m) => {
      'id': m.id,
      'workspaceId': m.workspaceId,
      'assetId': m.assetId,
      'title': m.title,
      'cost': m.cost,
      'performedAt': _ms(m.performedAt),
      'nextDueAt': m.nextDueAt == null ? null : _ms(m.nextDueAt!),
      'note': m.note,
      'createdAt': _ms(m.createdAt),
      'updatedAt': _ms(m.updatedAt),
      'deletedAt': m.deletedAt == null ? null : _ms(m.deletedAt!),
      'version': m.version,
      'deviceId': m.deviceId,
    };

AssetMaintenancesCompanion assetMaintenanceFromWire(Map<String, dynamic> w) => AssetMaintenancesCompanion(
      id: Value(w['id'] as String),
      workspaceId: Value(w['workspaceId'] as String),
      assetId: Value(w['assetId'] as String),
      title: Value(w['title'] as String),
      cost: Value((w['cost'] as num?)?.toInt() ?? 0),
      performedAt: Value(_dt(w['performedAt'])),
      nextDueAt: Value(_dtN(w['nextDueAt'])),
      note: Value(w['note'] as String?),
      createdAt: Value(_dt(w['createdAt'])),
      updatedAt: Value(_dt(w['updatedAt'])),
      deletedAt: Value(_dtN(w['deletedAt'])),
      version: Value((w['version'] as num?)?.toInt() ?? 1),
      deviceId: Value(w['deviceId'] as String),
      syncedAt: Value(DateTime.now()),
    );

// ──────────────────────── Document ────────────────────────

Map<String, Object?> documentToWire(DocEntry d) => {
      'id': d.id,
      'workspaceId': d.workspaceId,
      'title': d.title,
      'category': d.category,
      'docNumber': d.docNumber,
      'holderName': d.holderName,
      'issueDate': d.issueDate == null ? null : _ms(d.issueDate!),
      'expiryDate': d.expiryDate == null ? null : _ms(d.expiryDate!),
      'attachments': d.attachments,
      'note': d.note,
      'createdAt': _ms(d.createdAt),
      'updatedAt': _ms(d.updatedAt),
      'deletedAt': d.deletedAt == null ? null : _ms(d.deletedAt!),
      'version': d.version,
      'deviceId': d.deviceId,
    };

DocumentsCompanion documentFromWire(Map<String, dynamic> w) => DocumentsCompanion(
      id: Value(w['id'] as String),
      workspaceId: Value(w['workspaceId'] as String),
      title: Value(w['title'] as String),
      category: Value((w['category'] as String?) ?? 'IDENTITY'),
      docNumber: Value(w['docNumber'] as String?),
      holderName: Value(w['holderName'] as String?),
      issueDate: Value(_dtN(w['issueDate'])),
      expiryDate: Value(_dtN(w['expiryDate'])),
      attachments: Value(w['attachments'] as String?),
      note: Value(w['note'] as String?),
      createdAt: Value(_dt(w['createdAt'])),
      updatedAt: Value(_dt(w['updatedAt'])),
      deletedAt: Value(_dtN(w['deletedAt'])),
      version: Value((w['version'] as num?)?.toInt() ?? 1),
      deviceId: Value(w['deviceId'] as String),
      syncedAt: Value(DateTime.now()),
    );
