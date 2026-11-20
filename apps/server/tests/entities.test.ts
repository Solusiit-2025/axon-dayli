import { describe, expect, it } from 'vitest';
import { ENTITIES, ENTITY_KEYS } from '../src/entities.js';

const now = Date.now();

const taskPayload = {
  id: '01J00000000000000000000001',
  workspaceId: '01J00000000000000000000002',
  createdAt: now,
  updatedAt: now,
  deletedAt: null,
  version: 1,
  deviceId: 'device-1',
  projectId: null,
  parentTaskId: null,
  title: 'Kirim laporan',
  description: null,
  status: 'TODO',
  priority: 2,
  progress: 0,
  startAt: null,
  dueAt: now + 86_400_000,
  completedAt: null,
  estimatedMinutes: 60,
  actualMinutes: 0,
  tags: ['kerja'],
  recurrenceRule: null,
};

describe('registry entitas', () => {
  it('mendaftarkan semua entitas yang dipakai aplikasi', () => {
    expect(ENTITY_KEYS).toEqual(
      expect.arrayContaining([
        'task',
        'transaction',
        'wallet',
        'asset',
        'assetValuation',
        'reminder',
        'calendarEvent',
      ]),
    );
  });

  it('menolak payload tanpa field wajib', () => {
    const result = ENTITIES.task!.schema.safeParse({ ...taskPayload, title: undefined });
    expect(result.success).toBe(false);
  });

  it('menolak status di luar enum', () => {
    const result = ENTITIES.task!.schema.safeParse({ ...taskPayload, status: 'SELESAI' });
    expect(result.success).toBe(false);
  });

  it('mengisi default opsional menjadi null', () => {
    const parsed = ENTITIES.task!.schema.parse(taskPayload) as Record<string, unknown>;
    expect(parsed.description).toBeNull();
    expect(parsed.deletedAt).toBeNull();
  });
});

describe('konversi tipe', () => {
  it('mengubah epoch millis menjadi Date dan kembali', () => {
    const parsed = ENTITIES.task!.schema.parse(taskPayload) as Record<string, unknown>;
    const row = ENTITIES.task!.toRow(parsed);

    expect(row.createdAt).toBeInstanceOf(Date);
    expect((row.createdAt as Date).getTime()).toBe(now);

    const wire = ENTITIES.task!.toWire(row);
    expect(wire.createdAt).toBe(now);
    expect(wire.deletedAt).toBeNull();
  });

  it('menyimpan uang sebagai BigInt dan mengirimnya sebagai number', () => {
    const payload = {
      id: 'tx-1',
      workspaceId: 'ws-1',
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
      version: 1,
      deviceId: 'device-1',
      walletId: 'w-1',
      categoryId: null,
      type: 'EXPENSE',
      amount: 1_250_000,
      fee: 6_500,
      transferGroupId: null,
      occurredAt: now,
      note: null,
      payee: null,
      attachmentId: null,
      isReconciled: false,
    };

    const parsed = ENTITIES.transaction!.schema.parse(payload) as Record<string, unknown>;
    const row = ENTITIES.transaction!.toRow(parsed);

    expect(row.amount).toBe(1250000n);
    expect(typeof row.amount).toBe('bigint');

    const wire = ENTITIES.transaction!.toWire(row);
    expect(wire.amount).toBe(1250000);
    expect(JSON.stringify(wire)).toContain('1250000');
  });

  it('menerima nominal dalam bentuk string angka', () => {
    const parsed = ENTITIES.wallet!.schema.parse({
      id: 'w-1',
      workspaceId: 'ws-1',
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
      version: 1,
      deviceId: 'd',
      name: 'Tunai',
      type: 'CASH',
      initialBalance: '500000',
      currency: 'IDR',
      archivedAt: null,
    }) as Record<string, unknown>;

    expect(parsed.initialBalance).toBe(500000);
  });
});
