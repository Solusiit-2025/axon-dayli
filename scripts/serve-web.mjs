#!/usr/bin/env node
/**
 * Server statis sederhana untuk hasil `flutter build web`.
 *
 * Pemakaian:
 *   node scripts/serve-web.mjs [port]
 *
 * Catatan: aplikasi web memakai IndexedDB untuk database lokal dan
 * flutter_secure_storage, yang butuh secure context. localhost/127.0.0.1
 * dianggap aman oleh browser.
 */

import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { extname, join, normalize, resolve } from 'node:path';

const port = Number(process.argv[2] ?? process.env.PORT ?? 8080);
const root = resolve(import.meta.dirname, '..', 'apps', 'mobile', 'build', 'web');

const types = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.wasm': 'application/wasm',
  '.css': 'text/css; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.map': 'application/json; charset=utf-8',
};

try {
  await stat(join(root, 'index.html'));
} catch {
  console.error(`Belum ada hasil build di:\n  ${root}\n\nJalankan dulu:  cd apps\\mobile && flutter build web`);
  process.exit(1);
}

const server = createServer(async (req, res) => {
  try {
    const url = new URL(req.url ?? '/', `http://${req.headers.host}`);
    let pathname = decodeURIComponent(url.pathname);

    // Cegah path traversal.
    const filePath = normalize(join(root, pathname));
    if (!filePath.startsWith(root)) {
      res.writeHead(403).end('Forbidden');
      return;
    }

    let target = filePath;
    try {
      const info = await stat(target);
      if (info.isDirectory()) target = join(target, 'index.html');
    } catch {
      // Rute Flutter (deep link) → kirim index.html.
      target = join(root, 'index.html');
    }

    const body = await readFile(target);
    res.writeHead(200, {
      'Content-Type': types[extname(target).toLowerCase()] ?? 'application/octet-stream',
      'Cache-Control': 'no-cache',
    });
    res.end(body);
  } catch (error) {
    console.error('Gagal melayani', req.url, error.message);
    res.writeHead(500).end('Internal error');
  }
});

server.listen(port, '127.0.0.1', () => {
  console.log(`Axon Dayli web siap di http://127.0.0.1:${port}`);
  console.log('Pastikan API berjalan di http://127.0.0.1:4000 (apps/server: npm run dev).');
});
