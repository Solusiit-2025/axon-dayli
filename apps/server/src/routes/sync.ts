import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { prisma } from '../lib/prisma.js';
import { pullChanges, pushOps, type SyncOp } from '../services/sync.js';

const opSchema = z.object({
  opId: z.string().min(1).max(64),
  entity: z.string().min(1).max(40),
  entityId: z.string().min(1).max(64),
  op: z.enum(['upsert', 'delete']),
  payload: z.record(z.unknown()),
});

const pushSchema = z.object({
  ops: z.array(opSchema).max(200),
});

const pullSchema = z.object({
  cursor: z.string().regex(/^\d+$/).default('0'),
  limit: z.coerce.number().int().min(1).max(1000).default(500),
});

export default async function syncRoutes(app: FastifyInstance) {
  app.addHook('preHandler', app.authenticate);

  app.post('/sync/push', async (request) => {
    const body = pushSchema.parse(request.body);
    if (body.ops.length === 0) return { results: [], serverTime: Date.now() };

    const results = await pushOps(request.user.sub, body.ops as SyncOp[]);
    return { results, serverTime: Date.now() };
  });

  app.get('/sync/pull', async (request) => {
    const query = pullSchema.parse(request.query);
    const result = await pullChanges(request.user.sub, BigInt(query.cursor), query.limit);
    return { ...result, serverTime: Date.now() };
  });

  app.get('/sync/status', async (request) => {
    const last = await prisma.syncLog.findFirst({
      where: { userId: request.user.sub },
      orderBy: { seq: 'desc' },
      select: { seq: true },
    });
    const totalChanges = await prisma.syncLog.count({ where: { userId: request.user.sub } });
    return {
      latestCursor: last ? last.seq.toString() : '0',
      totalChanges,
      serverTime: Date.now(),
    };
  });
}
