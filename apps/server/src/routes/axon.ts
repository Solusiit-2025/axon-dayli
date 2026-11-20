import type { FastifyPluginAsync } from 'fastify';
import { env } from '../env.js';

export const axonRoutes: FastifyPluginAsync = async (app) => {
  const getAxonHeaders = () => ({
    'Content-Type': 'application/json',
    'x-api-key': env.AXON_WEB_API_KEY || '',
  });

  const getBaseUrl = () => {
    let url = env.AXON_WEB_BASE_URL || 'http://127.0.0.1:3000';
    return url.replace(/\/$/, '');
  };

  app.get('/api/axon/ping', { preHandler: [app.authenticate] }, async (_req, reply) => {
    const baseUrl = getBaseUrl();
    if (!env.AXON_WEB_API_KEY) {
      return reply.code(500).send({
        error: { message: 'AXON_WEB_API_KEY belum diisi pada file .env server DailyPilot' },
      });
    }

    try {
      const res = await fetch(`${baseUrl}/api/integration/ping`, {
        headers: getAxonHeaders(),
      });
      const text = await res.text();
      let data: any;
      try {
        data = JSON.parse(text);
      } catch (_) {
        return reply.code(res.status).send({ error: { message: `Response Axon Web bukan JSON (${res.status}): ${text}` } });
      }

      if (!res.ok) {
        return reply.code(res.status).send({ error: { message: data.message || `Axon Web HTTP ${res.status}` } });
      }

      return reply.send(data);
    } catch (e: any) {
      return reply.code(502).send({
        error: { message: `Gagal terhubung ke Axon Web (${baseUrl}): ${e?.message || e}` },
      });
    }
  });

  app.get('/api/axon/banks', { preHandler: [app.authenticate] }, async (_req, reply) => {
    const baseUrl = getBaseUrl();
    try {
      const res = await fetch(`${baseUrl}/api/integration/banks`, {
        headers: getAxonHeaders(),
      });
      const text = await res.text();
      let data: any;
      try { data = JSON.parse(text); } catch (_) {
        return reply.code(res.status).send({ error: { message: `Axon Web HTTP ${res.status}: ${text}` } });
      }
      if (!res.ok) {
        return reply.code(res.status).send({ error: { message: data.message || `HTTP ${res.status}` } });
      }
      return reply.send(data);
    } catch (e: any) {
      return reply.code(502).send({ error: { message: `Gagal mengambil bank (${baseUrl}): ${e?.message || e}` } });
    }
  });

  app.get('/api/axon/invoices', { preHandler: [app.authenticate] }, async (req, reply) => {
    const baseUrl = getBaseUrl();
    const query = req.query as Record<string, string>;
    const params = new URLSearchParams(query).toString();
    try {
      const url = `${baseUrl}/api/integration/invoices${params ? `?${params}` : ''}`;
      const res = await fetch(url, {
        headers: getAxonHeaders(),
      });
      const text = await res.text();
      let data: any;
      try { data = JSON.parse(text); } catch (_) {
        return reply.code(res.status).send({ error: { message: `Axon Web HTTP ${res.status}: ${text}` } });
      }
      if (!res.ok) {
        return reply.code(res.status).send({ error: { message: data.message || `HTTP ${res.status}` } });
      }
      return reply.send(data);
    } catch (e: any) {
      return reply.code(502).send({ error: { message: `Gagal mengambil invoice (${baseUrl}): ${e?.message || e}` } });
    }
  });

  app.get('/api/axon/invoices/:id', { preHandler: [app.authenticate] }, async (req, reply) => {
    const baseUrl = getBaseUrl();
    const { id } = req.params as { id: string };
    try {
      const res = await fetch(`${baseUrl}/api/integration/invoices/${id}`, {
        headers: getAxonHeaders(),
      });
      const text = await res.text();
      let data: any;
      try { data = JSON.parse(text); } catch (_) {
        return reply.code(res.status).send({ error: { message: `Axon Web HTTP ${res.status}: ${text}` } });
      }
      if (!res.ok) {
        return reply.code(res.status).send({ error: { message: data.message || `HTTP ${res.status}` } });
      }
      return reply.send(data);
    } catch (e: any) {
      return reply.code(502).send({ error: { message: `Gagal mengambil detail invoice (${baseUrl}): ${e?.message || e}` } });
    }
  });

  app.post('/api/axon/invoices/:id/payments', { preHandler: [app.authenticate] }, async (req, reply) => {
    const baseUrl = getBaseUrl();
    const { id } = req.params as { id: string };
    try {
      const res = await fetch(`${baseUrl}/api/integration/invoices/${id}/payments`, {
        method: 'POST',
        headers: getAxonHeaders(),
        body: JSON.stringify(req.body),
      });
      const text = await res.text();
      let data: any;
      try { data = JSON.parse(text); } catch (_) {
        return reply.code(res.status).send({ error: { message: `Axon Web HTTP ${res.status}: ${text}` } });
      }
      return reply.code(res.status).send(data);
    } catch (e: any) {
      return reply.code(502).send({ error: { message: `Gagal mengirim pembayaran (${baseUrl}): ${e?.message || e}` } });
    }
  });
};

export default axonRoutes;
