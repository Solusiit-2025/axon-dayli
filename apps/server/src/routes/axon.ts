import type { FastifyPluginAsync } from 'fastify';
import { env } from '../env.js';

export const axonRoutes: FastifyPluginAsync = async (app) => {
  const getAxonHeaders = () => ({
    'Content-Type': 'application/json',
    'x-api-key': env.AXON_WEB_API_KEY || '',
  });

  app.get('/api/axon/ping', { preHandler: [app.authenticate] }, async (_req, reply) => {
    try {
      const res = await fetch(`${env.AXON_WEB_BASE_URL}/api/integration/ping`, {
        headers: getAxonHeaders(),
      });
      const data = await res.json();
      return reply.send(data);
    } catch (e) {
      return reply.code(502).send({ error: { message: `Gagal terhubung ke Axon Web: ${e}` } });
    }
  });

  app.get('/api/axon/banks', { preHandler: [app.authenticate] }, async (_req, reply) => {
    try {
      const res = await fetch(`${env.AXON_WEB_BASE_URL}/api/integration/banks`, {
        headers: getAxonHeaders(),
      });
      const data = await res.json();
      return reply.send(data);
    } catch (e) {
      return reply.code(502).send({ error: { message: `Gagal mengambil daftar bank: ${e}` } });
    }
  });

  app.get('/api/axon/invoices', { preHandler: [app.authenticate] }, async (req, reply) => {
    const query = req.query as Record<string, string>;
    const params = new URLSearchParams(query).toString();
    try {
      const url = `${env.AXON_WEB_BASE_URL}/api/integration/invoices${params ? `?${params}` : ''}`;
      const res = await fetch(url, {
        headers: getAxonHeaders(),
      });
      const data = await res.json();
      return reply.send(data);
    } catch (e) {
      return reply.code(502).send({ error: { message: `Gagal mengambil daftar invoice: ${e}` } });
    }
  });

  app.get('/api/axon/invoices/:id', { preHandler: [app.authenticate] }, async (req, reply) => {
    const { id } = req.params as { id: string };
    try {
      const res = await fetch(`${env.AXON_WEB_BASE_URL}/api/integration/invoices/${id}`, {
        headers: getAxonHeaders(),
      });
      const data = await res.json();
      return reply.send(data);
    } catch (e) {
      return reply.code(502).send({ error: { message: `Gagal mengambil detail invoice: ${e}` } });
    }
  });

  app.post('/api/axon/invoices/:id/payments', { preHandler: [app.authenticate] }, async (req, reply) => {
    const { id } = req.params as { id: string };
    try {
      const res = await fetch(`${env.AXON_WEB_BASE_URL}/api/integration/invoices/${id}/payments`, {
        method: 'POST',
        headers: getAxonHeaders(),
        body: JSON.stringify(req.body),
      });
      const data = await res.json();
      return reply.code(res.status).send(data);
    } catch (e) {
      return reply.code(502).send({ error: { message: `Gagal mengirim pembayaran invoice: ${e}` } });
    }
  });
};

export default axonRoutes;
