import { buildApp } from './app.js';
import { env } from './env.js';
import { prisma } from './lib/prisma.js';

async function main() {
  const app = await buildApp();

  const shutdown = async (signal: string) => {
    app.log.info({ signal }, 'Mematikan server...');
    await app.close();
    await prisma.$disconnect();
    process.exit(0);
  };

  process.on('SIGINT', () => void shutdown('SIGINT'));
  process.on('SIGTERM', () => void shutdown('SIGTERM'));

  try {
    await prisma.$queryRaw`SELECT 1`;
    app.log.info('Koneksi database OK');
  } catch (err) {
    app.log.error({ err }, 'Tidak bisa terhubung ke database. Periksa DATABASE_URL di .env');
    process.exit(1);
  }

  await app.listen({ port: env.PORT, host: env.HOST });
  app.log.info(`Axon Dayli API berjalan di http://localhost:${env.PORT}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
