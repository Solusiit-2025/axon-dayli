#!/usr/bin/env node
/**
 * Mengisi akun demo DailyPilot dengan data contoh yang realistis.
 *
 * Berguna untuk mencoba UI (terutama di browser) tanpa mengetik manual.
 *
 * Pemakaian:
 *   node scripts/seed-demo.mjs [baseUrl]
 *
 * Akun: demo@dailypilot.test / Demo12345
 * Skrip aman dijalankan berulang: jika akun sudah punya data, tidak menambah lagi.
 */

const BASE = process.argv[2] ?? process.env.API_URL ?? 'http://127.0.0.1:4000';
const EMAIL = 'demo@dailypilot.test';
const PASSWORD = 'Demo12345';

const id = () => crypto.randomUUID();
const now = Date.now();
const DAY = 86_400_000;

async function call(method, path, { token, body } = {}) {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  const text = await res.text();
  let json = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    json = { raw: text };
  }
  return { status: res.status, body: json };
}

function row(workspaceId, fields, version = 1) {
  return {
    id: id(),
    workspaceId,
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
    version,
    deviceId: 'seed-demo',
    ...fields,
  };
}

async function login() {
  const reg = await call('POST', '/auth/register', {
    body: { email: EMAIL, password: PASSWORD, name: 'Demo DailyPilot', deviceName: 'seed' },
  });
  if (reg.status === 201) {
    console.log('Akun demo dibuat.');
    return reg.body;
  }
  const res = await call('POST', '/auth/login', {
    body: { email: EMAIL, password: PASSWORD, deviceName: 'seed' },
  });
  if (res.status !== 200) {
    console.error('Gagal masuk akun demo:', res.status, JSON.stringify(res.body).slice(0, 300));
    process.exit(1);
  }
  console.log('Akun demo sudah ada, memakai yang lama.');
  return res.body;
}

async function main() {
  console.log(`Seed demo → ${BASE}`);

  const account = await login();
  const { accessToken, workspaces, categories, wallets } = account;

  const personal = workspaces.find((w) => w.type === 'PERSONAL');
  const company = workspaces.find((w) => w.type === 'COMPANY');

  const pull = await call('GET', '/sync/pull?cursor=0&limit=1', { token: accessToken });
  if ((pull.body?.cursor ?? 0) > 0) {
    const any = await call('GET', '/sync/pull?cursor=0&limit=500', { token: accessToken });
    if ((any.body?.changes ?? []).length > 0) {
      console.log('Akun demo sudah berisi data — tidak menambah apa pun.');
      finish();
      return;
    }
  }

  const categoriesOf = (ws, kind) =>
    categories.filter((c) => c.workspaceId === ws.id && c.kind === kind);
  const personalExpense = categoriesOf(personal, 'EXPENSE');
  const personalIncome = categoriesOf(personal, 'INCOME');
  const companyExpense = categoriesOf(company, 'EXPENSE');
  const personalWallet = wallets.find((w) => w.workspaceId === personal.id);
  const companyWallet = wallets.find((w) => w.workspaceId === company.id);

  const ops = [];
  const push = (entity, payload) =>
    ops.push({ opId: id(), entity, entityId: payload.id, op: 'upsert', payload });

  // ── Proyek & tugas (Pribadi) ──
  const projectId = id();
  push(
    'project',
    row(personal.id, {
      id: projectId,
      name: 'Rilis DailyPilot 1.0',
      description: 'Persiapan rilis aplikasi versi pertama.',
      color: '#4F46E5',
      status: 'active',
      startAt: now - 7 * DAY,
      dueAt: now + 14 * DAY,
    }),
  );

  const taskDesign = row(personal.id, {
    id: id(),
    projectId,
    parentTaskId: null,
    title: 'Rapikan desain halaman Keuangan',
    description: 'Kartu saldo, grafik kategori, dan daftar transaksi.',
    status: 'IN_PROGRESS',
    priority: 1,
    progress: 60,
    startAt: now - 2 * DAY,
    dueAt: now + DAY,
    completedAt: null,
    estimatedMinutes: 180,
    actualMinutes: 95,
    tags: ['desain', 'ui'],
    recurrenceRule: null,
  });
  push('task', taskDesign);

  const taskSync = row(personal.id, {
    id: id(),
    projectId,
    parentTaskId: null,
    title: 'Uji sinkronisasi dua perangkat',
    description: 'Pastikan konflik versi tidak menghilangkan data.',
    status: 'TODO',
    priority: 2,
    progress: 0,
    startAt: null,
    dueAt: now + 3 * DAY,
    completedAt: null,
    estimatedMinutes: 120,
    actualMinutes: 0,
    tags: ['uji'],
    recurrenceRule: null,
  });
  push('task', taskSync);

  push(
    'task',
    row(personal.id, {
      id: id(),
      projectId: null,
      parentTaskId: null,
      title: 'Olahraga pagi 30 menit',
      description: null,
      status: 'DONE',
      priority: 3,
      progress: 100,
      startAt: now - DAY,
      dueAt: now - DAY + 3600_000,
      completedAt: now - DAY + 1800_000,
      estimatedMinutes: 30,
      actualMinutes: 30,
      tags: ['kesehatan'],
      recurrenceRule: 'DAILY',
    }),
  );

  // Sub-tugas untuk task pertama.
  for (const [i, title] of [
    'Susun layout kartu saldo',
    'Buat grafik pengeluaran per kategori',
    'Uji mode gelap',
  ].entries()) {
    push(
      'checklistItem',
      row(personal.id, {
        id: id(),
        taskId: taskDesign.id,
        title,
        isDone: i < 2,
        sortOrder: i,
      }),
    );
  }

  push(
    'taskProgressLog',
    row(personal.id, {
      id: id(),
      taskId: taskDesign.id,
      progressBefore: 30,
      progressAfter: 60,
      note: 'Layout selesai, lanjut grafik.',
      occurredAt: now - 6 * 3600_000,
    }),
  );

  // ── Keuangan (Pribadi) ──
  const pick = (list, index) => list[index % list.length];
  const tx = (fields) =>
    row(personal.id, {
      id: id(),
      walletId: personalWallet.id,
      categoryId: null,
      amount: 0,
      fee: 0,
      transferGroupId: null,
      occurredAt: now,
      note: null,
      payee: null,
      attachmentId: null,
      isReconciled: false,
      ...fields,
    });

  push('transaction', tx({
    type: 'INCOME',
    categoryId: pick(personalIncome, 0).id,
    amount: 8_500_000,
    occurredAt: now - 3 * DAY,
    note: 'Gaji bulan ini',
    payee: 'Kantor',
    isReconciled: true,
  }));
  push('transaction', tx({
    type: 'EXPENSE',
    categoryId: pick(personalExpense, 0).id,
    amount: 125_000,
    fee: 2_500,
    occurredAt: now - 2 * DAY,
    note: 'Kopi & camilan',
    payee: 'Kopi Kenangan',
  }));
  push('transaction', tx({
    type: 'EXPENSE',
    categoryId: pick(personalExpense, 1).id,
    amount: 450_000,
    occurredAt: now - DAY,
    note: 'Belanja bulanan',
    payee: 'Indomaret',
  }));
  push('transaction', tx({
    type: 'EXPENSE',
    categoryId: pick(personalExpense, 2).id,
    amount: 250_000,
    occurredAt: now,
    note: 'Bensin & tol',
    payee: 'SPBU',
  }));

  push(
    'budget',
    row(personal.id, {
      id: id(),
      categoryId: pick(personalExpense, 0).id,
      period: 'MONTHLY',
      amount: 1_500_000,
      startAt: Date.UTC(new Date().getUTCFullYear(), new Date().getUTCMonth(), 1),
      endAt: null,
      rollover: false,
    }),
  );
  push(
    'budget',
    row(personal.id, {
      id: id(),
      categoryId: pick(personalExpense, 1).id,
      period: 'MONTHLY',
      amount: 3_000_000,
      startAt: Date.UTC(new Date().getUTCFullYear(), new Date().getUTCMonth(), 1),
      endAt: null,
      rollover: false,
    }),
  );

  push(
    'debt',
    row(personal.id, {
      id: id(),
      counterparty: 'Budi',
      direction: 'RECEIVABLE',
      principal: 750_000,
      remaining: 750_000,
      dueAt: now + 10 * DAY,
      note: 'Pinjam untuk servis motor',
      status: 'open',
    }),
  );
  push(
    'debt',
    row(personal.id, {
      id: id(),
      counterparty: 'Toko Elektronik Jaya',
      direction: 'PAYABLE',
      principal: 4_500_000,
      remaining: 3_000_000,
      dueAt: now + 20 * DAY,
      note: 'Cicilan kulkas',
      status: 'open',
    }),
  );

  // ── Aset (Pribadi & Perusahaan) ──
  const laptopAsset = row(company.id, {
    id: id(),
    name: 'Laptop Kerja ThinkPad',
    category: 'elektronik',
    purchaseAt: now - 200 * DAY,
    purchasePrice: 22_000_000,
    currentValue: 17_500_000,
    depreciationMethod: 'STRAIGHT_LINE',
    usefulLifeMonths: 36,
    salvageValue: 2_000_000,
    status: 'ACTIVE',
    serialNumber: 'TP-2026-0091',
    note: 'Inventaris kantor, dipakai tim operasional.',
  });
  push('asset', laptopAsset);

  push(
    'asset',
    row(company.id, {
      id: id(),
      name: 'Motor Operasional',
      category: 'kendaraan',
      purchaseAt: now - 500 * DAY,
      purchasePrice: 18_000_000,
      currentValue: 13_000_000,
      depreciationMethod: 'STRAIGHT_LINE',
      usefulLifeMonths: 60,
      salvageValue: 4_000_000,
      status: 'MAINTENANCE',
      serialNumber: 'B-1234-XYZ',
      note: 'Servis rutin bulan ini.',
    }),
  );

  push(
    'assetValuation',
    row(company.id, {
      id: id(),
      assetId: laptopAsset.id,
      value: 17_500_000,
      valuedAt: now - 10 * DAY,
      source: 'MANUAL',
      note: 'Harga pasar second.',
    }),
  );

  push(
    'assetMaintenance',
    row(company.id, {
      id: id(),
      assetId: laptopAsset.id,
      title: 'Bersihkan & ganti thermal paste',
      cost: 150_000,
      performedAt: now - 30 * DAY,
      nextDueAt: now + 150 * DAY,
      note: 'Suhu turun setelah perawatan.',
    }),
  );

  // ── Agenda & pengingat ──
  push(
    'calendarEvent',
    row(personal.id, {
      id: id(),
      title: 'Review progres mingguan',
      location: 'Google Meet',
      startAt: now + DAY + 3600_000,
      endAt: now + DAY + 2 * 3600_000,
      allDay: false,
      recurrenceRule: null,
      linkedTaskId: null,
      note: 'Bahas hambatan dan rencana minggu depan.',
    }),
  );

  push(
    'reminder',
    row(personal.id, {
      id: id(),
      entityType: 'TASK',
      entityId: taskSync.id,
      title: 'Mulai uji sinkronisasi',
      message: 'Siapkan dua perangkat dan akun uji.',
      triggerAt: now + DAY + 9 * 3600_000,
      recurrenceRule: null,
      snoozeUntil: null,
      isActive: true,
      firedAt: null,
    }),
  );

  const res = await call('POST', '/sync/push', { token: accessToken, body: { ops } });
  const results = res.body?.results ?? [];
  const applied = results.filter((r) => r.status === 'applied').length;
  const problems = results.filter((r) => r.status !== 'applied');

  console.log(`Push ${ops.length} operasi → ${applied} diterapkan.`);
  if (problems.length > 0) {
    console.log('Yang bermasalah:', JSON.stringify(problems).slice(0, 600));
  }

  finish();
}

function finish() {
  console.log(`
Akun demo:
  Email    : ${EMAIL}
  Password : ${PASSWORD}

Buka aplikasi (web: http://127.0.0.1:8080), masuk dengan akun di atas.
`);
}

main().catch((error) => {
  console.error('Seed gagal:', error);
  process.exit(1);
});
