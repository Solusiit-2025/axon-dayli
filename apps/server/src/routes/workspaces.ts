import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { prisma } from '../lib/prisma.js';
import { AppError } from '../lib/errors.js';

const createSchema = z.object({
  type: z.enum(['PERSONAL', 'COMPANY']),
  name: z.string().min(1).max(60),
  color: z.string().regex(/^#[0-9A-Fa-f]{6}$/).default('#2563EB'),
  icon: z.string().max(40).default('briefcase'),
});

const updateSchema = z.object({
  name: z.string().min(1).max(60).optional(),
  color: z.string().regex(/^#[0-9A-Fa-f]{6}$/).optional(),
  icon: z.string().max(40).optional(),
  archived: z.boolean().optional(),
});

export default async function workspaceRoutes(app: FastifyInstance) {
  app.addHook('preHandler', app.authenticate);

  app.get('/workspaces', async (request) => {
    const workspaces = await prisma.workspace.findMany({
      where: { userId: request.user.sub, deletedAt: null },
      orderBy: { createdAt: 'asc' },
    });
    return { workspaces };
  });

  app.post('/workspaces', async (request, reply) => {
    const body = createSchema.parse(request.body);
    const workspace = await prisma.workspace.create({
      data: {
        userId: request.user.sub,
        type: body.type,
        name: body.name,
        color: body.color,
        icon: body.icon,
        deviceId: 'server',
      },
    });
    return reply.code(201).send({ workspace });
  });

  app.patch('/workspaces/:id', async (request) => {
    const { id } = z.object({ id: z.string() }).parse(request.params);
    const body = updateSchema.parse(request.body);

    const existing = await prisma.workspace.findFirst({ where: { id, userId: request.user.sub } });
    if (!existing) throw AppError.notFound('Workspace tidak ditemukan');

    const workspace = await prisma.workspace.update({
      where: { id },
      data: {
        name: body.name,
        color: body.color,
        icon: body.icon,
        archivedAt: body.archived === undefined ? undefined : body.archived ? new Date() : null,
        version: { increment: 1 },
      },
    });
    return { workspace };
  });

  app.delete('/workspaces/:id', async (request) => {
    const { id } = z.object({ id: z.string() }).parse(request.params);
    const existing = await prisma.workspace.findFirst({ where: { id, userId: request.user.sub } });
    if (!existing) throw AppError.notFound('Workspace tidak ditemukan');

    const total = await prisma.workspace.count({ where: { userId: request.user.sub, deletedAt: null } });
    if (total <= 1) throw AppError.badRequest('Minimal harus ada satu workspace');

    await prisma.workspace.update({
      where: { id },
      data: { deletedAt: new Date(), version: { increment: 1 } },
    });
    return { ok: true };
  });
}
