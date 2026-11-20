import { z } from 'zod';

/**
 * Registry entitas yang ikut sinkronisasi.
 *
 * Aturan penting:
 *  - Semua tanggal dikirim sebagai epoch millisecond (number).
 *  - Semua uang dikirim sebagai number (Rupiah utuh) dan disimpan sebagai BigInt.
 *  - Setiap entitas membawa `version` untuk optimistic concurrency.
 */

export type Row = Record<string, any>;

type FieldKind =
  | 'string'
  | 'string?'
  | 'int'
  | 'int?'
  | 'bool'
  | 'date'
  | 'date?'
  | 'bigint'
  | 'bigint?'
  | 'string[]'
  | `enum:${string}`;

type Delegate = {
  findUnique(args: any): Promise<Row | null>;
  findMany(args: any): Promise<Row[]>;
  create(args: any): Promise<Row>;
  update(args: any): Promise<Row>;
  count?(args: any): Promise<number>;
};

function zodFor(kind: FieldKind): z.ZodTypeAny {
  if (kind.startsWith('enum:')) {
    const values = kind.slice(5).split('|') as [string, ...string[]];
    return z.enum(values);
  }
  switch (kind) {
    case 'string':
      return z.string();
    case 'string?':
      return z.string().nullish().transform((v) => v ?? null);
    case 'int':
      return z.number().int();
    case 'int?':
      return z.number().int().nullish().transform((v) => v ?? null);
    case 'bool':
      return z.boolean();
    case 'date':
      return z.number().int();
    case 'date?':
      return z.number().int().nullish().transform((v) => v ?? null);
    case 'bigint':
      return z
        .union([z.number(), z.string().regex(/^\d+$/)])
        .transform((v) => (typeof v === 'string' ? Number(v) : Math.trunc(v)));
    case 'bigint?':
      return z
        .union([z.number(), z.string().regex(/^\d+$/), z.null()])
        .nullish()
        .transform((v) => (v == null ? null : typeof v === 'string' ? Number(v) : Math.trunc(v)));
    case 'string[]':
      return z.array(z.string());
    default:
      return z.unknown();
  }
}

function toDb(kind: FieldKind, value: unknown): unknown {
  if (kind.startsWith('enum:')) return value;
  switch (kind) {
    case 'date':
    case 'date?':
      return value == null ? null : new Date(value as number);
    case 'bigint':
    case 'bigint?':
      return value == null ? null : BigInt(Math.trunc(value as number));
    case 'int?':
    case 'string?':
      return value ?? null;
    default:
      return value;
  }
}

function toWire(kind: FieldKind, value: unknown): unknown {
  if (kind.startsWith('enum:')) return value;
  switch (kind) {
    case 'date':
    case 'date?':
      return value == null ? null : (value as Date).getTime();
    case 'bigint':
    case 'bigint?':
      return value == null ? null : Number(value as bigint);
    default:
      return value;
  }
}

const baseShape = {
  id: z.string().min(1).max(64),
  workspaceId: z.string().min(1).max(64),
  createdAt: z.number().int(),
  updatedAt: z.number().int(),
  deletedAt: z.number().int().nullish().transform((v) => v ?? null),
  version: z.number().int().min(1),
  deviceId: z.string().min(1).max(128),
};

export type EntityDef = {
  key: string;
  fields: Record<string, FieldKind>;
  schema: z.ZodTypeAny;
  delegate: (db: any) => Delegate;
  /** Payload wire → row siap create */
  toRow: (payload: Row) => Row;
  /** Payload wire → row siap update (tanpa id/workspaceId/createdAt) */
  toUpdate: (payload: Row) => Row;
  /** Row DB → payload wire */
  toWire: (row: Row) => Row;
};

function defineEntity(
  key: string,
  fields: Record<string, FieldKind>,
  delegate: (db: any) => Delegate,
): EntityDef {
  const shape: Record<string, z.ZodTypeAny> = { ...baseShape };
  for (const [name, kind] of Object.entries(fields)) {
    shape[name] = zodFor(kind);
  }

  return {
    key,
    fields,
    schema: z.object(shape),
    delegate,
    toRow(payload: Row) {
      const row: Row = {
        id: payload.id,
        workspaceId: payload.workspaceId,
        createdAt: new Date(payload.createdAt),
        updatedAt: new Date(payload.updatedAt),
        deletedAt: payload.deletedAt == null ? null : new Date(payload.deletedAt),
        version: payload.version,
        deviceId: payload.deviceId,
      };
      for (const [name, kind] of Object.entries(fields)) {
        row[name] = toDb(kind, payload[name]);
      }
      return row;
    },
    toUpdate(payload: Row) {
      const row: Row = {
        updatedAt: new Date(payload.updatedAt),
        deletedAt: payload.deletedAt == null ? null : new Date(payload.deletedAt),
        version: payload.version,
        deviceId: payload.deviceId,
      };
      for (const [name, kind] of Object.entries(fields)) {
        row[name] = toDb(kind, payload[name]);
      }
      return row;
    },
    toWire(row: Row) {
      const out: Row = {
        id: row.id,
        workspaceId: row.workspaceId,
        createdAt: (row.createdAt as Date).getTime(),
        updatedAt: (row.updatedAt as Date).getTime(),
        deletedAt: row.deletedAt ? (row.deletedAt as Date).getTime() : null,
        version: row.version,
        deviceId: row.deviceId,
      };
      for (const [name, kind] of Object.entries(fields)) {
        out[name] = toWire(kind, row[name]);
      }
      return out;
    },
  };
}

export const ENTITIES: Record<string, EntityDef> = {
  project: defineEntity(
    'project',
    {
      name: 'string',
      description: 'string?',
      color: 'string',
      status: 'string',
      startAt: 'date?',
      dueAt: 'date?',
    },
    (db) => db.project,
  ),

  task: defineEntity(
    'task',
    {
      projectId: 'string?',
      parentTaskId: 'string?',
      title: 'string',
      description: 'string?',
      status: 'enum:TODO|IN_PROGRESS|BLOCKED|DONE|CANCELLED',
      priority: 'int',
      progress: 'int',
      startAt: 'date?',
      dueAt: 'date?',
      completedAt: 'date?',
      estimatedMinutes: 'int?',
      actualMinutes: 'int',
      tags: 'string[]',
      recurrenceRule: 'string?',
    },
    (db) => db.task,
  ),

  checklistItem: defineEntity(
    'checklistItem',
    {
      taskId: 'string',
      title: 'string',
      isDone: 'bool',
      sortOrder: 'int',
    },
    (db) => db.checklistItem,
  ),

  taskProgressLog: defineEntity(
    'taskProgressLog',
    {
      taskId: 'string',
      progressBefore: 'int',
      progressAfter: 'int',
      note: 'string?',
      occurredAt: 'date',
    },
    (db) => db.taskProgressLog,
  ),

  reminder: defineEntity(
    'reminder',
    {
      entityType: 'enum:TASK|EVENT|TRANSACTION|BUDGET|CUSTOM',
      entityId: 'string?',
      title: 'string',
      message: 'string?',
      triggerAt: 'date',
      recurrenceRule: 'string?',
      snoozeUntil: 'date?',
      isActive: 'bool',
      firedAt: 'date?',
    },
    (db) => db.reminder,
  ),

  calendarEvent: defineEntity(
    'calendarEvent',
    {
      title: 'string',
      location: 'string?',
      startAt: 'date',
      endAt: 'date',
      allDay: 'bool',
      recurrenceRule: 'string?',
      linkedTaskId: 'string?',
      note: 'string?',
    },
    (db) => db.calendarEvent,
  ),

  wallet: defineEntity(
    'wallet',
    {
      name: 'string',
      type: 'enum:CASH|BANK|EWALLET|CREDIT',
      initialBalance: 'bigint',
      currency: 'string',
      archivedAt: 'date?',
    },
    (db) => db.wallet,
  ),

  category: defineEntity(
    'category',
    {
      name: 'string',
      kind: 'enum:INCOME|EXPENSE',
      parentId: 'string?',
      icon: 'string',
      color: 'string',
    },
    (db) => db.category,
  ),

  transaction: defineEntity(
    'transaction',
    {
      walletId: 'string',
      categoryId: 'string?',
      budgetId: 'string?',
      type: 'enum:INCOME|EXPENSE|TRANSFER',
      amount: 'bigint',
      fee: 'bigint',
      transferGroupId: 'string?',
      occurredAt: 'date',
      note: 'string?',
      payee: 'string?',
      attachmentId: 'string?',
      isReconciled: 'bool',
    },
    (db) => db.transaction,
  ),

  budget: defineEntity(
    'budget',
    {
      categoryId: 'string',
      name: 'string?',
      period: 'enum:WEEKLY|MONTHLY|CUSTOM',
      amount: 'bigint',
      startAt: 'date',
      endAt: 'date?',
      rollover: 'bool',
      note: 'string?',
    },
    (db) => db.budget,
  ),

  debt: defineEntity(
    'debt',
    {
      counterparty: 'string',
      direction: 'enum:RECEIVABLE|PAYABLE',
      category: 'string?',
      assetId: 'string?',
      principal: 'bigint',
      remaining: 'bigint',
      monthlyInstallment: 'bigint?',
      tenorMonths: 'int?',
      contractNumber: 'string?',
      dueAt: 'date?',
      note: 'string?',
      status: 'string',
    },
    (db) => db.debt,
  ),

  asset: defineEntity(
    'asset',
    {
      name: 'string',
      category: 'string',
      purchaseAt: 'date?',
      purchasePrice: 'bigint?',
      currentValue: 'bigint',
      depreciationMethod: 'enum:NONE|STRAIGHT_LINE|DECLINING',
      usefulLifeMonths: 'int?',
      salvageValue: 'bigint?',
      status: 'enum:ACTIVE|MAINTENANCE|SOLD|LOST',
      serialNumber: 'string?',
      debtId: 'string?',
      attachments: 'string?',
      note: 'string?',
    },
    (db) => db.asset,
  ),

  assetValuation: defineEntity(
    'assetValuation',
    {
      assetId: 'string',
      value: 'bigint',
      valuedAt: 'date',
      source: 'enum:MANUAL|AUTO_DEPRECIATION',
      note: 'string?',
    },
    (db) => db.assetValuation,
  ),

  assetMaintenance: defineEntity(
    'assetMaintenance',
    {
      assetId: 'string',
      title: 'string',
      cost: 'bigint',
      performedAt: 'date',
      nextDueAt: 'date?',
      note: 'string?',
    },
    (db) => db.assetMaintenance,
  ),

  document: defineEntity(
    'document',
    {
      title: 'string',
      category: 'string',
      docNumber: 'string?',
      holderName: 'string?',
      issueDate: 'date?',
      expiryDate: 'date?',
      attachments: 'string?',
      note: 'string?',
    },
    (db) => db.document,
  ),

  attachment: defineEntity(
    'attachment',
    {
      ownerType: 'enum:TASK|TRANSACTION|ASSET|EVENT',
      ownerId: 'string',
      fileName: 'string',
      mimeType: 'string',
      sizeBytes: 'int',
      remoteUrl: 'string?',
      checksum: 'string?',
    },
    (db) => db.attachment,
  ),
};

export const ENTITY_KEYS = Object.keys(ENTITIES);

/** Hanya field milik entitas ini yang diterima; field asing dibuang. */
export function pickKnownFields(def: EntityDef, row: Row): Row {
  const out: Row = { id: row.id };
  for (const name of Object.keys(def.fields)) out[name] = row[name];
  return out;
}
