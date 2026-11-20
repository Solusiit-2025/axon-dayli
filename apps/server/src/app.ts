import Fastify, { type FastifyInstance } from 'fastify';
import cors from '@fastify/cors';
import jwt from '@fastify/jwt';
import { ZodError } from 'zod';
import { Prisma } from '@prisma/client';
import { env } from './env.js';
import { AppError } from './lib/errors.js';
import { registerAuthDecorator } from './plugins/auth.js';
import authRoutes from './routes/auth.js';
import workspaceRoutes from './routes/workspaces.js';
import syncRoutes from './routes/sync.js';
import reportRoutes from './routes/reports.js';
import axonRoutes from './routes/axon.js';

export async function buildApp(): Promise<FastifyInstance> {
  const app = Fastify({
    logger:
      env.NODE_ENV === 'development'
        ? { transport: undefined, level: 'info' }
        : { level: 'warn' },
    // Lampiran foto dikirim sebagai base64 di dalam payload sync, jadi butuh
    // batas yang cukup besar. Klien memecah batch agar tetap aman.
    bodyLimit: 25 * 1024 * 1024,
  });

  await app.register(cors, {
    origin: env.CORS_ORIGIN === '*' ? true : env.CORS_ORIGIN.split(',').map((s) => s.trim()),
  });

  await app.register(jwt, {
    secret: env.JWT_SECRET,
    sign: { expiresIn: env.ACCESS_TOKEN_TTL },
  });

  registerAuthDecorator(app);

  app.setErrorHandler((error, _request, reply) => {
    if (error instanceof ZodError) {
      return reply.code(400).send({
        error: {
          code: 'VALIDATION_ERROR',
          message: 'Data yang dikirim tidak valid',
          details: error.issues.map((i) => ({ path: i.path.join('.'), message: i.message })),
        },
      });
    }

    if (error instanceof AppError) {
      return reply.code(error.statusCode).send({
        error: { code: error.code, message: error.message, details: error.details },
      });
    }

    if (error instanceof Prisma.PrismaClientKnownRequestError) {
      if (error.code === 'P2002') {
        return reply.code(409).send({ error: { code: 'CONFLICT', message: 'Data sudah ada' } });
      }
      if (error.code === 'P2025') {
        return reply.code(404).send({ error: { code: 'NOT_FOUND', message: 'Data tidak ditemukan' } });
      }
    }

    const statusCode = (error as { statusCode?: number }).statusCode ?? 500;
    if (statusCode >= 500) app.log.error(error);

    const message = error instanceof Error ? error.message : 'Request tidak dapat diproses';

    return reply.code(statusCode).send({
      error: {
        code: statusCode >= 500 ? 'INTERNAL_ERROR' : 'REQUEST_ERROR',
        message: statusCode >= 500 ? 'Terjadi kesalahan di server' : message,
      },
    });
  });

  app.setNotFoundHandler((_request, reply) => {
    reply.code(404).send({ error: { code: 'NOT_FOUND', message: 'Endpoint tidak ditemukan' } });
  });

  app.get('/health', async () => ({ ok: true, service: 'dailypilot-server', time: Date.now() }));

  await app.register(authRoutes);
  await app.register(workspaceRoutes);
  await app.register(syncRoutes);
  await app.register(reportRoutes);
  await app.register(axonRoutes);

  return app;
}
