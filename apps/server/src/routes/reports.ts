import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { prisma } from '../lib/prisma.js';
import { AppError } from '../lib/errors.js';
import { ownsWorkspace } from '../services/sync.js';

const summarySchema = z.object({
  workspaceId: z.string().min(1),
  from: z.coerce.number().int(),
  to: z.coerce.number().int(),
});

export default async function reportRoutes(app: FastifyInstance) {
  app.addHook('preHandler', app.authenticate);

  /**
   * Ringkasan keuangan + aset untuk satu workspace.
   * Catatan: aplikasi menghitung laporan dari data lokal; endpoint ini dipakai
   * untuk perangkat baru / verifikasi silang.
   */
  app.get('/reports/summary', async (request) => {
    const q = summarySchema.parse(request.query);
    const userId = request.user.sub;

    if (!(await ownsWorkspace(userId, q.workspaceId))) {
      throw AppError.notFound('Workspace tidak ditemukan');
    }

    const from = new Date(q.from);
    const to = new Date(q.to);

    const [periodTx, allTx, wallets, assets] = await Promise.all([
      prisma.transaction.findMany({
        where: {
          workspaceId: q.workspaceId,
          deletedAt: null,
          occurredAt: { gte: from, lte: to },
        },
        select: { type: true, amount: true, fee: true, categoryId: true },
      }),
      prisma.transaction.findMany({
        where: { workspaceId: q.workspaceId, deletedAt: null },
        select: { walletId: true, type: true, amount: true, fee: true },
      }),
      prisma.wallet.findMany({
        where: { workspaceId: q.workspaceId, deletedAt: null },
        select: { id: true, name: true, type: true, initialBalance: true },
      }),
      prisma.asset.findMany({
        where: { workspaceId: q.workspaceId, deletedAt: null, status: 'ACTIVE' },
        select: { currentValue: true },
      }),
    ]);

    let income = 0;
    let expense = 0;
    const byCategory = new Map<string, number>();

    for (const tx of periodTx) {
      const amount = Number(tx.amount);
      const fee = Number(tx.fee);
      if (tx.type === 'INCOME') income += amount;
      else if (tx.type === 'EXPENSE') expense += amount + fee;
      else continue;
      if (tx.categoryId) {
        const key = `${tx.type}:${tx.categoryId}`;
        byCategory.set(key, (byCategory.get(key) ?? 0) + amount);
      }
    }

    const balances = wallets.map((w) => {
      const rows = allTx.filter((t) => t.walletId === w.id);
      let balance = Number(w.initialBalance);
      for (const t of rows) {
        const amount = Number(t.amount);
        const fee = Number(t.fee);
        if (t.type === 'INCOME') balance += amount;
        else if (t.type === 'EXPENSE') balance -= amount + fee;
        else balance -= amount + fee; // transfer keluar dari wallet ini
      }
      return { walletId: w.id, name: w.name, type: w.type, balance };
    });

    const assetTotal = assets.reduce((sum, a) => sum + Number(a.currentValue), 0);

    return {
      workspaceId: q.workspaceId,
      period: { from: q.from, to: q.to },
      income,
      expense,
      net: income - expense,
      byCategory: [...byCategory.entries()].map(([key, amount]) => {
        const [type, categoryId] = key.split(':');
        return { type, categoryId, amount };
      }),
      walletBalances: balances,
      totalBalance: balances.reduce((sum, b) => sum + b.balance, 0),
      assetTotal,
    };
  });
}
