#!/usr/bin/env node
/**
 * Smoke test end-to-end DailyPilot API.
 *
 * Menguji alur nyata yang dipakai aplikasi:
 *   1. register  → workspace, kategori, dompet awal ikut dibuat
 *   2. login     → sesi kedua (perangkat lain)
 *   3. push      → buat project, tugas, transaksi, aset
 *   4. push      → edit tugas (versi naik) & idempotensi opId
 *   5. push      → versi basi harus ditolak (conflict)
 *   6. push      → workspace orang lain harus ditolak
 *   7. pull      → semua perubahan terkirim balik, cursor maju
 *
 * Pemakaian:  node scripts/smoke-test.mjs [baseUrl]
 */

const BASE = process.argv[2] ?? process.env.API_URL ?? 'http://127.0.0.1:4000';

let passed = 0;
let failed = 0;

function check(name, condition, detail = '') {
  if (condition) {
    passed++;
    console.log(`  \x1b[32m✓\x1b[0m ${name}`);
  } else {
    failed++;
    console.log(`  \x1b[31m✗\x1b[0m ${name}${detail ? `\n      → ${detail}` : ''}`);
  }
}

function section(title) {
  console.log(`\n\x1b[1m${title}\x1b[0m`);
}

async function call(method, path, { token, body } = {}) {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });

  let json = null;
  const text = await res.text();
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    json = { raw: text };
  }
  return { status: res.status, body: json };
}

async function waitForServer(retries = 40) {
  for (let i = 0; i < retries; i++) {
    try {
      const res = await fetch(`${BASE}/health`);
      if (res.ok) return true;
    } catch {
      /* belum siap */
    }
    await new Promise((r) => setTimeout(r, 500));
  }
  return false;
}

const id = () => crypto.randomUUID();
const now = Date.now();

function basePayload(entityId, workspaceId, extra = {}, version = 1) {
  return {
    id: entityId,
    workspaceId,
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
    version,
    deviceId: 'smoke-test',
    ...extra,
  };
}

async function main() {
  console.log(`\n\x1b[36mDailyPilot smoke test\x1b[0m → ${BASE}`);

  section('0. Ketersediaan server');
  const up = await waitForServer();
  check('server merespons /health', up, 'server tidak pernah siap');
  if (!up) {
    console.log('\nPastikan `npm run dev` berjalan di apps/server.\n');
    process.exit(1);
  }

  section('1. Registrasi');
  const email = `smoke+${Date.now()}@dailypilot.test`;
  const password = 'rahasia12345';

  const reg = await call('POST', '/auth/register', {
    body: { email, password, name: 'Smoke Tester', deviceName: 'smoke' },
  });

  check('register → 201', reg.status === 201, JSON.stringify(reg.body).slice(0, 300));
  if (reg.status !== 201) process.exit(1);

  const { accessToken, refreshToken, workspaces, categories, wallets, user } = reg.body;

  check('mendapat accessToken', typeof accessToken === 'string' && accessToken.length > 20);
  check('mendapat refreshToken', typeof refreshToken === 'string');
  check('dua workspace (Pribadi + Perusahaan)', workspaces?.length === 2, `dapat ${workspaces?.length}`);
  check(
    'workspace bertipe PERSONAL & COMPANY',
    workspaces?.some((w) => w.type === 'PERSONAL') && workspaces?.some((w) => w.type === 'COMPANY'),
  );
  check('kategori default dibuat', (categories?.length ?? 0) >= 8, `dapat ${categories?.length}`);
  check('dompet default dibuat', (wallets?.length ?? 0) >= 2, `dapat ${wallets?.length}`);

  const personal = workspaces.find((w) => w.type === 'PERSONAL');
  const company = workspaces.find((w) => w.type === 'COMPANY');

  check(
    'kategori workspace terpisah',
    categories.every((c) => c.workspaceId === personal.id || c.workspaceId === company.id),
  );

  section('2. Login di perangkat lain');
  const login = await call('POST', '/auth/login', {
    body: { email, password, deviceName: 'device-kedua' },
  });
  check('login → 200', login.status === 200, JSON.stringify(login.body).slice(0, 200));
  check('login mengembalikan kategori', (login.body?.categories?.length ?? 0) >= 8);
  check('login mengembalikan dompet', (login.body?.wallets?.length ?? 0) >= 2);

  const token = login.body?.accessToken ?? accessToken;

  const badLogin = await call('POST', '/auth/login', { body: { email, password: 'salah-sekali' } });
  check('password salah ditolak 401', badLogin.status === 401, `status ${badLogin.status}`);

  section('3. Push data baru');
  const projectId = id();
  const taskId = id();
  const txId = id();
  const assetId = id();
  const walletId = wallets.find((w) => w.workspaceId === personal.id).id;
  const categoryId = categories.find((c) => c.workspaceId === personal.id && c.kind === 'EXPENSE').id;

  const project = basePayload(projectId, personal.id, {
    name: 'Rilis v1.0',
    description: 'Persiapan rilis DailyPilot',
    color: '#6366F1',
    status: 'active',
    startAt: now,
    dueAt: now + 7 * 86_400_000,
  });

  const task = basePayload(taskId, personal.id, {
    projectId,
    parentTaskId: null,
    title: 'Uji sinkronisasi offline',
    description: null,
    status: 'IN_PROGRESS',
    priority: 1,
    progress: 40,
    startAt: null,
    dueAt: now + 86_400_000,
    completedAt: null,
    estimatedMinutes: 90,
    actualMinutes: 25,
    tags: ['uji', 'sinkron'],
    recurrenceRule: null,
  });

  const transaction = basePayload(txId, personal.id, {
    walletId,
    categoryId,
    type: 'EXPENSE',
    amount: 125_000,
    fee: 2_500,
    transferGroupId: null,
    occurredAt: now,
    note: 'Kopi & snack',
    payee: 'Kopi Kenangan',
    attachmentId: null,
    isReconciled: false,
  });

  const asset = basePayload(assetId, company.id, {
    name: 'Laptop Kantor',
    category: 'electronics',
    purchaseAt: now - 90 * 86_400_000,
    purchasePrice: 18_000_000,
    currentValue: 15_500_000,
    depreciationMethod: 'STRAIGHT_LINE',
    usefulLifeMonths: 36,
    salvageValue: 2_000_000,
    status: 'ACTIVE',
    serialNumber: 'SN-12345',
    note: null,
  });

  const push = await call('POST', '/sync/push', {
    token,
    body: {
      ops: [
        { opId: id(), entity: 'project', entityId: projectId, op: 'upsert', payload: project },
        { opId: id(), entity: 'task', entityId: taskId, op: 'upsert', payload: task },
        { opId: id(), entity: 'transaction', entityId: txId, op: 'upsert', payload: transaction },
        { opId: id(), entity: 'asset', entityId: assetId, op: 'upsert', payload: asset },
      ],
    },
  });

  check('push → 200', push.status === 200, JSON.stringify(push.body).slice(0, 300));
  const results = push.body?.results ?? [];
  check('4 operasi diterapkan', results.filter((r) => r.status === 'applied').length === 4,
    JSON.stringify(results));

  section('4. Idempotensi & optimistic concurrency');
  const dupOpId = id();
  const dupBody = {
    ops: [{ opId: dupOpId, entity: 'task', entityId: id(), op: 'upsert',
      payload: basePayload(id(), personal.id, {
        projectId: null, parentTaskId: null, title: 'Tugas duplikat', description: null,
        status: 'TODO', priority: 2, progress: 0, startAt: null, dueAt: null,
        completedAt: null, estimatedMinutes: null, actualMinutes: 0, tags: [],
        recurrenceRule: null,
      }) }],
  };
  // payload.id harus sama dengan entityId, jadi susun ulang
  const dupTaskId = id();
  dupBody.ops[0].entityId = dupTaskId;
  dupBody.ops[0].payload.id = dupTaskId;

  const first = await call('POST', '/sync/push', { token, body: dupBody });
  const second = await call('POST', '/sync/push', { token, body: dupBody });
  check('push pertama applied', first.body?.results?.[0]?.status === 'applied');
  check('push ulang dengan opId sama tidak diterapkan lagi',
    second.body?.results?.[0]?.status === 'applied' || second.body?.results?.[0]?.status === 'ignored',
    JSON.stringify(second.body?.results));

  const stale = { ...task, updatedAt: now + 1, version: 1 };
  const staleRes = await call('POST', '/sync/push', {
    token,
    body: { ops: [{ opId: id(), entity: 'task', entityId: taskId, op: 'upsert', payload: stale }] },
  });
  check('versi basi ditolak sebagai conflict',
    staleRes.body?.results?.[0]?.status === 'conflict',
    JSON.stringify(staleRes.body?.results));

  const goodEdit = { ...task, updatedAt: now + 2, version: 2, progress: 80, title: 'Uji sinkronisasi (revisi)' };
  const editRes = await call('POST', '/sync/push', {
    token,
    body: { ops: [{ opId: id(), entity: 'task', entityId: taskId, op: 'upsert', payload: goodEdit }] },
  });
  check('versi baru diterima', editRes.body?.results?.[0]?.status === 'applied',
    JSON.stringify(editRes.body?.results));

  section('5. Isolasi data (lintas pengguna)');
  const other = await call('POST', '/auth/register', {
    body: { email: `smoke2+${Date.now()}@dailypilot.test`, password, name: 'Penyusup' },
  });
  const otherToken = other.body?.accessToken;
  const intrude = await call('POST', '/sync/push', {
    token: otherToken,
    body: {
      ops: [{
        opId: id(), entity: 'task', entityId: id(), op: 'upsert',
        payload: basePayload(id(), personal.id, {
          projectId: null, parentTaskId: null, title: 'Nyusup', description: null,
          status: 'TODO', priority: 2, progress: 0, startAt: null, dueAt: null,
          completedAt: null, estimatedMinutes: null, actualMinutes: 0, tags: [],
          recurrenceRule: null,
        }),
      }],
    },
  });
  check('menulis ke workspace orang lain ditolak',
    intrude.body?.results?.[0]?.status === 'error',
    JSON.stringify(intrude.body?.results));

  section('6. Pull (delta)');
  const pull = await call('GET', '/sync/pull?cursor=0&limit=500', { token });
  check('pull → 200', pull.status === 200, JSON.stringify(pull.body).slice(0, 200));
  const changes = pull.body?.changes ?? [];
  check('pull mengembalikan perubahan', changes.length > 0, `dapat ${changes.length}`);
  check('pull berisi entitas task', changes.some((c) => c.entity === 'task'));
  check('pull berisi entitas transaction', changes.some((c) => c.entity === 'transaction'));
  check('pull berisi entitas asset', changes.some((c) => c.entity === 'asset'));

  const pulledTask = changes.filter((c) => c.entity === 'task' && c.data.id === taskId).pop();
  check('pull membawa versi terbaru task', pulledTask?.data?.version === 2,
    `version ${pulledTask?.data?.version}`);
  check('uang dikirim sebagai number', typeof pulledTask === 'object' &&
    typeof changes.find((c) => c.entity === 'transaction')?.data?.amount === 'number');

  const cursor = Number(pull.body?.cursor ?? 0);
  check('cursor pull berupa angka', Number.isFinite(cursor) && cursor > 0, `cursor ${pull.body?.cursor}`);

  const pullAgain = await call('GET', `/sync/pull?cursor=${cursor}`, { token });
  check('pull kedua tanpa perubahan baru', (pullAgain.body?.changes?.length ?? -1) === 0,
    `dapat ${pullAgain.body?.changes?.length}`);

  section('7. Laporan server');
  const report = await call(
    'GET',
    `/reports/summary?workspaceId=${personal.id}&from=${Date.now() - 86_400_000}&to=${Date.now() + 86_400_000}`,
    { token },
  );
  check('reports/summary → 200', report.status === 200, JSON.stringify(report.body).slice(0, 200));
  check('pengeluaran terhitung (125000 + 2500 fee)', report.body?.expense === 127_500,
    `expense ${report.body?.expense}`);

  section('8. Penghapusan (tombstone)');
  const delRes = await call('POST', '/sync/push', {
    token,
    body: {
      ops: [{
        opId: id(), entity: 'task', entityId: taskId, op: 'delete',
        payload: { ...goodEdit, version: 3, deletedAt: Date.now(), updatedAt: Date.now() },
      }],
    },
  });
  check('hapus task diterima', delRes.body?.results?.[0]?.status === 'applied',
    JSON.stringify(delRes.body?.results));

  const afterDelete = await call('GET', `/sync/pull?cursor=${cursor}`, { token });
  const deletedTask = (afterDelete.body?.changes ?? [])
    .filter((c) => c.entity === 'task' && c.data.id === taskId)
    .pop();
  check('pull mengirim deletedAt terisi', deletedTask?.data?.deletedAt != null,
    JSON.stringify(deletedTask?.data?.deletedAt));

  section('9. Refresh token');
  const refreshed = await call('POST', '/auth/refresh', { body: { refreshToken } });
  check('refresh → 200', refreshed.status === 200, JSON.stringify(refreshed.body).slice(0, 200));
  check('mendapat access token baru', typeof refreshed.body?.accessToken === 'string');

  const reuse = await call('POST', '/auth/refresh', { body: { refreshToken } });
  check('refresh token lama tidak bisa dipakai ulang', reuse.status === 401, `status ${reuse.status}`);

  console.log(`\n\x1b[1mHasil:\x1b[0m ${passed} lulus, ${failed} gagal\n`);
  process.exit(failed === 0 ? 0 : 1);
}

main().catch((err) => {
  console.error('\nSmoke test gagal:', err);
  process.exit(1);
});
