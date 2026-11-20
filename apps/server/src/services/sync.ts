import { prisma } from '../lib/prisma.js';
import { ENTITIES, type Row } from '../entities.js';

export type SyncOp = {
  opId: string;
  entity: string;
  entityId: string;
  op: 'upsert' | 'delete';
  payload: Row;
};

export type OpResult = {
  opId: string;
  status: 'applied' | 'conflict' | 'ignored' | 'error';
  serverVersion?: number;
  error?: string;
};

export type PullResult = {
  cursor: string;
  hasMore: boolean;
  changes: Array<{ entity: string; data: Row }>;
};

const MAX_BATCH = 200;

export function isBatchTooLarge(ops: unknown[]): boolean {
  return ops.length > MAX_BATCH;
}

export async function ownsWorkspace(
  userId: string,
  workspaceId: string,
  cache?: Map<string, boolean>,
): Promise<boolean> {
  if (cache?.has(workspaceId)) return cache.get(workspaceId)!;
  const ws = await prisma.workspace.findFirst({
    where: { id: workspaceId, userId, deletedAt: null },
    select: { id: true },
  });
  const ok = Boolean(ws);
  cache?.set(workspaceId, ok);
  return ok;
}

/** Menerapkan satu operasi secara atomik. */
async function applyOne(userId: string, op: SyncOp): Promise<OpResult> {
  const def = ENTITIES[op.entity];
  if (!def) {
    return { opId: op.opId, status: 'error', error: `Entitas '${op.entity}' tidak dikenal` };
  }

  const parsed = def.schema.safeParse(op.payload);
  if (!parsed.success) {
    const first = parsed.error.issues[0];
    return {
      opId: op.opId,
      status: 'error',
      error: first ? `${first.path.join('.')}: ${first.message}` : 'Payload tidak valid',
    };
  }
  const payload = parsed.data as Row;

  if (payload.id !== op.entityId) {
    return { opId: op.opId, status: 'error', error: 'entityId tidak cocok dengan payload.id' };
  }

  try {
    return await prisma.$transaction(async (tx) => {
      // Idempotensi: opId yang sama hanya boleh diproses sekali.
      const done = await tx.syncOpLog.findUnique({ where: { id: op.opId } });
      if (done) {
        return { opId: op.opId, status: (done.result as OpResult['status']) ?? 'ignored' };
      }

      const where = { id: payload.id } as const;
      const existing = await def.delegate(tx).findUnique({ where });

      if (existing && existing.workspaceId !== payload.workspaceId) {
        return { opId: op.opId, status: 'error', error: 'workspaceId tidak cocok dengan data di server' };
      }

      let result: OpResult;

      if (op.op === 'delete') {
        if (!existing) {
          result = { opId: op.opId, status: 'ignored' };
        } else if (existing.version > payload.version) {
          result = { opId: op.opId, status: 'conflict', serverVersion: existing.version };
        } else {
          const deletedAt = payload.deletedAt ? new Date(payload.deletedAt) : new Date();
          await def.delegate(tx).update({
            where,
            data: {
              deletedAt,
              updatedAt: new Date(payload.updatedAt),
              version: payload.version,
              deviceId: payload.deviceId,
            },
          });
          await tx.syncLog.create({
            data: {
              userId,
              workspaceId: payload.workspaceId,
              entity: op.entity,
              entityId: payload.id,
              deleted: true,
            },
          });
          result = { opId: op.opId, status: 'applied' };
        }
      } else if (existing && existing.version >= payload.version) {
        // Edit lama kalah (LWW): client harus pull untuk menyamakan versi.
        result = { opId: op.opId, status: 'conflict', serverVersion: existing.version };
      } else {
        if (existing) {
          await def.delegate(tx).update({ where, data: def.toUpdate(payload) });
        } else {
          await def.delegate(tx).create({ data: def.toRow(payload) });
        }
        await tx.syncLog.create({
          data: {
            userId,
            workspaceId: payload.workspaceId,
            entity: op.entity,
            entityId: payload.id,
            deleted: payload.deletedAt != null,
          },
        });
        result = { opId: op.opId, status: 'applied' };
      }

      await tx.syncOpLog.create({
        data: {
          id: op.opId,
          userId,
          workspaceId: payload.workspaceId,
          entity: op.entity,
          entityId: payload.id,
          op: op.op,
          result: result.status,
        },
      });

      return result;
    });
  } catch (err) {
    return {
      opId: op.opId,
      status: 'error',
      error: err instanceof Error ? err.message : 'Gagal menerapkan operasi',
    };
  }
}

export async function pushOps(userId: string, ops: SyncOp[]): Promise<OpResult[]> {
  if (ops.length > MAX_BATCH) {
    throw new Error(`Maksimal ${MAX_BATCH} operasi per batch, diterima ${ops.length}`);
  }

  const cache = new Map<string, boolean>();
  const results: OpResult[] = [];

  const userWorkspaces = await prisma.workspace.findMany({
    where: { userId, deletedAt: null },
    select: { id: true },
  });
  const validWsIds = new Set(userWorkspaces.map((w) => w.id));

  for (const op of ops) {
    let workspaceId = (op.payload?.workspaceId as string) ?? '';

    // Jika client mengirim workspaceId lokal/offline yang belum terdaftar di server,
    // petakan otomatis ke workspace pertama pengguna agar sync tetap berhasil.
    if (!validWsIds.has(workspaceId) && validWsIds.size > 0) {
      workspaceId = Array.from(validWsIds)[0]!;
      if (op.payload) {
        (op.payload as Record<string, unknown>).workspaceId = workspaceId;
      }
    }

    if (!workspaceId || !(await ownsWorkspace(userId, workspaceId, cache))) {
      results.push({ opId: op.opId, status: 'error', error: 'Workspace tidak ditemukan atau bukan milikmu' });
      continue;
    }
    results.push(await applyOne(userId, op));
  }

  return results;
}

export async function pullChanges(userId: string, cursor: bigint, limit = 500): Promise<PullResult> {
  const take = Math.min(Math.max(limit, 1), 1000);

  const logs = await prisma.syncLog.findMany({
    where: { userId, seq: { gt: cursor } },
    orderBy: { seq: 'asc' },
    take,
  });

  if (logs.length === 0) {
    return { cursor: cursor.toString(), hasMore: false, changes: [] };
  }

  const grouped = new Map<string, string[]>();
  for (const log of logs) {
    const list = grouped.get(log.entity) ?? [];
    list.push(log.entityId);
    grouped.set(log.entity, list);
  }

  const changesByKey = new Map<string, Row>();
  for (const [entity, ids] of grouped) {
    const def = ENTITIES[entity];
    if (!def) continue;
    const rows = await def.delegate(prisma).findMany({ where: { id: { in: ids } } });
    for (const row of rows) {
      changesByKey.set(`${entity}:${row.id}`, def.toWire(row));
    }
  }

  const changes: PullResult['changes'] = [];
  for (const log of logs) {
    const data = changesByKey.get(`${log.entity}:${log.entityId}`);
    if (data) changes.push({ entity: log.entity, data });
  }

  return {
    cursor: logs[logs.length - 1]!.seq.toString(),
    hasMore: logs.length === take,
    changes,
  };
}
