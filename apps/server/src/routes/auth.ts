import { createHash, randomBytes, randomUUID } from 'node:crypto';
import bcrypt from 'bcryptjs';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { prisma } from '../lib/prisma.js';
import { env } from '../env.js';
import { AppError } from '../lib/errors.js';

const DEFAULT_CATEGORIES = {
  EXPENSE: [
    { name: 'Makan & Minum', icon: 'restaurant', color: '#F97316' },
    { name: 'Transport', icon: 'directions_car', color: '#0EA5E9' },
    { name: 'Tagihan', icon: 'receipt_long', color: '#8B5CF6' },
    { name: 'Belanja', icon: 'shopping_bag', color: '#EC4899' },
    { name: 'Kesehatan', icon: 'health_and_safety', color: '#EF4444' },
    { name: 'Hiburan', icon: 'movie', color: '#F59E0B' },
    { name: 'Operasional', icon: 'engineering', color: '#64748B' },
    { name: 'Lainnya', icon: 'more_horiz', color: '#94A3B8' },
  ],
  INCOME: [
    { name: 'Gaji', icon: 'payments', color: '#10B981' },
    { name: 'Bonus', icon: 'card_giftcard', color: '#22C55E' },
    { name: 'Pendapatan Jasa', icon: 'work', color: '#14B8A6' },
    { name: 'Lainnya', icon: 'add_circle', color: '#94A3B8' },
  ],
} as const;

export function hashToken(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}

export function createRefreshToken(): string {
  return randomBytes(32).toString('base64url');
}

export function signAccessToken(app: FastifyInstance, user: { id: string; email: string }): string {
  return app.jwt.sign({ sub: user.id, email: user.email }, { expiresIn: env.ACCESS_TOKEN_TTL });
}

async function issueRefreshToken(userId: string, deviceId?: string | null): Promise<string> {
  const token = createRefreshToken();
  const expiresAt = new Date(Date.now() + env.REFRESH_TOKEN_TTL_DAYS * 24 * 60 * 60 * 1000);
  await prisma.refreshToken.create({
    data: { userId, tokenHash: hashToken(token), deviceId: deviceId ?? null, expiresAt },
  });
  return token;
}

async function seedDefaults(workspaceId: string, company: boolean) {
  const categories = [
    ...DEFAULT_CATEGORIES.EXPENSE.map((c) => ({ ...c, kind: 'EXPENSE' as const })),
    ...DEFAULT_CATEGORIES.INCOME.map((c) => ({ ...c, kind: 'INCOME' as const })),
  ].filter((c) => (company ? true : c.name !== 'Operasional' && c.name !== 'Pendapatan Jasa'));

  await prisma.category.createMany({
    data: categories.map((c) => ({
      id: randomUUID(),
      workspaceId,
      name: c.name,
      kind: c.kind,
      icon: c.icon,
      color: c.color,
      createdAt: new Date(),
      updatedAt: new Date(),
      version: 1,
      deviceId: 'server',
    })),
  });

  await prisma.wallet.create({
    data: {
      id: randomUUID(),
      workspaceId,
      name: company ? 'Kas Perusahaan' : 'Tunai',
      type: company ? 'BANK' : 'CASH',
      initialBalance: 0n,
      createdAt: new Date(),
      updatedAt: new Date(),
      version: 1,
      deviceId: 'server',
    },
  });
}

/** Kategori & dompet ikut dikirim saat login agar perangkat baru langsung siap pakai. */
async function workspaceBundle(userId: string) {
  const [categories, wallets] = await Promise.all([
    prisma.category.findMany({ where: { workspace: { userId }, deletedAt: null } }),
    prisma.wallet.findMany({ where: { workspace: { userId }, deletedAt: null } }),
  ]);

  return {
    categories: categories.map((c) => ({
      id: c.id,
      workspaceId: c.workspaceId,
      name: c.name,
      kind: c.kind,
      parentId: c.parentId,
      icon: c.icon,
      color: c.color,
    })),
    wallets: wallets.map((w) => ({
      id: w.id,
      workspaceId: w.workspaceId,
      name: w.name,
      type: w.type,
      initialBalance: Number(w.initialBalance),
      currency: w.currency,
    })),
  };
}

const registerSchema = z.object({
  email: z.string().email().toLowerCase(),
  password: z.string().min(8, 'Password minimal 8 karakter'),
  name: z.string().min(1).max(80),
  deviceName: z.string().max(80).optional(),
});

const loginSchema = z.object({
  email: z.string().email().toLowerCase(),
  password: z.string().min(1),
  deviceName: z.string().max(80).optional(),
});

const refreshSchema = z.object({
  refreshToken: z.string().min(10),
});

export default async function authRoutes(app: FastifyInstance) {
  app.post('/auth/register', async (request, reply) => {
    const body = registerSchema.parse(request.body);

    const existing = await prisma.user.findUnique({ where: { email: body.email } });
    if (existing) throw AppError.conflict('Email sudah terdaftar');

    const passwordHash = await bcrypt.hash(body.password, 11);
    const user = await prisma.user.create({
      data: { email: body.email, name: body.name, passwordHash },
    });

    const personal = await prisma.workspace.create({
      data: {
        userId: user.id,
        type: 'PERSONAL',
        name: 'Pribadi',
        color: '#10B981',
        icon: 'person',
        deviceId: 'server',
      },
    });
    const company = await prisma.workspace.create({
      data: {
        userId: user.id,
        type: 'COMPANY',
        name: 'Perusahaan',
        color: '#2563EB',
        icon: 'business',
        deviceId: 'server',
      },
    });

    await seedDefaults(personal.id, false);
    await seedDefaults(company.id, true);

    const device = await prisma.device.create({
      data: { userId: user.id, name: body.deviceName ?? 'Android', platform: 'android' },
    });

    const refreshToken = await issueRefreshToken(user.id, device.id);

    return reply.code(201).send({
      user: { id: user.id, email: user.email, name: user.name, timezone: user.timezone, currency: user.currency },
      workspaces: [personal, company],
      ...(await workspaceBundle(user.id)),
      deviceId: device.id,
      accessToken: signAccessToken(app, user),
      refreshToken,
    });
  });

  app.post('/auth/login', async (request, reply) => {
    const body = loginSchema.parse(request.body);

    const user = await prisma.user.findUnique({ where: { email: body.email } });
    if (!user) throw AppError.unauthorized('Email atau password salah');

    const valid = await bcrypt.compare(body.password, user.passwordHash);
    if (!valid) throw AppError.unauthorized('Email atau password salah');

    const device = await prisma.device.create({
      data: { userId: user.id, name: body.deviceName ?? 'Android', platform: 'android' },
    });
    const refreshToken = await issueRefreshToken(user.id, device.id);
    const workspaces = await prisma.workspace.findMany({
      where: { userId: user.id, deletedAt: null },
      orderBy: { createdAt: 'asc' },
    });

    return reply.send({
      user: { id: user.id, email: user.email, name: user.name, timezone: user.timezone, currency: user.currency },
      workspaces,
      ...(await workspaceBundle(user.id)),
      deviceId: device.id,
      accessToken: signAccessToken(app, user),
      refreshToken,
    });
  });

  app.post('/auth/refresh', async (request, reply) => {
    const body = refreshSchema.parse(request.body);
    const tokenHash = hashToken(body.refreshToken);

    const stored = await prisma.refreshToken.findUnique({ where: { tokenHash } });
    if (!stored || stored.revokedAt || stored.expiresAt.getTime() < Date.now()) {
      throw AppError.unauthorized('Refresh token tidak valid atau sudah kedaluwarsa');
    }

    const user = await prisma.user.findUnique({ where: { id: stored.userId } });
    if (!user) throw AppError.unauthorized('Akun tidak ditemukan');

    // Rotasi: token lama dicabut, token baru diterbitkan.
    await prisma.refreshToken.update({
      where: { id: stored.id },
      data: { revokedAt: new Date() },
    });
    const refreshToken = await issueRefreshToken(user.id, stored.deviceId);
    const workspaces = await prisma.workspace.findMany({
      where: { userId: user.id, deletedAt: null },
      orderBy: { createdAt: 'asc' },
    });

    return reply.send({
      user: { id: user.id, email: user.email, name: user.name, timezone: user.timezone, currency: user.currency },
      workspaces,
      ...(await workspaceBundle(user.id)),
      deviceId: stored.deviceId,
      accessToken: signAccessToken(app, user),
      refreshToken,
    });
  });

  app.post('/auth/logout', { preHandler: [app.authenticate] }, async (request, reply) => {
    const body = refreshSchema.parse(request.body);
    await prisma.refreshToken.updateMany({
      where: { tokenHash: hashToken(body.refreshToken) },
      data: { revokedAt: new Date() },
    });
    return reply.send({ ok: true });
  });

  app.get('/auth/me', { preHandler: [app.authenticate] }, async (request) => {
    const userId = request.user.sub;
    const user = await prisma.user.findUnique({ where: { id: userId } });
    if (!user) throw AppError.unauthorized();

    const workspaces = await prisma.workspace.findMany({
      where: { userId, deletedAt: null },
      orderBy: { createdAt: 'asc' },
    });

    return {
      user: { id: user.id, email: user.email, name: user.name, timezone: user.timezone, currency: user.currency },
      workspaces,
      ...(await workspaceBundle(userId)),
    };
  });
}
