import 'dart:async';
import 'dart:convert';

import '../local/database.dart';
import '../remote/api_client.dart';

class SyncResult {
  const SyncResult({
    this.pushed = 0,
    this.pulled = 0,
    this.conflicts = 0,
    this.failed = 0,
    this.error,
    this.skipped = false,
  });

  final int pushed;
  final int pulled;
  final int conflicts;
  final int failed;
  final String? error;
  final bool skipped;

  bool get ok => error == null;

  String describe() {
    if (skipped) return 'Sinkronisasi sedang berjalan';
    if (error != null) return error!;
    if (pushed == 0 && pulled == 0) return 'Sudah tersinkron';
    return 'Terkirim $pushed · Diterima $pulled${conflicts > 0 ? ' · $conflicts konflik' : ''}';
  }
}

/// Satu operasi push beserta payload yang siap dikirim.
class _PushOp {
  _PushOp(this.opId, this.body);

  final String opId;
  final Map<String, Object?> body;

  /// Perkiraan ukuran byte di JSON (base64 mayoritas ASCII).
  late final int estimateBytes = jsonEncode(body).length;
}

/// Akumulator hasil push per batch.
class _PushTotals {
  _PushTotals({this.failed = 0, this.error});

  int applied = 0;
  int conflicts = 0;
  int failed;
  String? error;

  void add(_PushTotals other) {
    applied += other.applied;
    conflicts += other.conflicts;
    failed += other.failed;
    error ??= other.error;
  }

  SyncResult toResult() => SyncResult(
    pushed: applied + conflicts,
    conflicts: conflicts,
    failed: failed,
    error: error,
  );
}

/// Mesin sinkronisasi dua arah: push outbox lalu pull delta.
class SyncEngine {
  SyncEngine({required this.db, required this.api, this.onSessionExpired});

  final AppDatabase db;
  final ApiClient api;
  final void Function()? onSessionExpired;

  bool _running = false;
  DateTime? _lastSyncAt;

  DateTime? get lastSyncAt => _lastSyncAt;
  bool get isRunning => _running;

  Future<SyncResult> sync() async {
    if (_running) return const SyncResult(skipped: true);
    _running = true;

    try {
      final pushResult = await _push();
      if (pushResult.error != null) return pushResult;

      final pullResult = await _pull();
      _lastSyncAt = DateTime.now();

      return SyncResult(
        pushed: pushResult.pushed,
        pulled: pullResult.pulled,
        conflicts: pushResult.conflicts,
        failed: pushResult.failed,
        error: pullResult.error,
      );
    } on ApiException catch (e) {
      if (e.isUnauthorized) onSessionExpired?.call();
      return SyncResult(error: e.message);
    } catch (e) {
      return SyncResult(error: 'Sinkronisasi gagal: $e');
    } finally {
      _running = false;
    }
  }

  /// Ukuran maksimum satu request push. Sengaja di bawah 1 MB supaya tetap
  /// aman di belakang reverse proxy (nginx default `client_max_body_size 1m`).
  static const _maxPushBytes = 800 * 1024;
  static const _maxPushOps = 60;

  Future<SyncResult> _push() async {
    final ops = await db.pendingOps(limit: 200);
    if (ops.isEmpty) return const SyncResult();

    final entries = <_PushOp>[];
    for (final op in ops) {
      try {
        entries.add(
          _PushOp(op.opId, {
            'opId': op.opId,
            'entity': op.entity,
            'entityId': op.entityId,
            'op': op.op,
            'payload': jsonDecode(op.payload),
          }),
        );
      } catch (_) {
        // payload rusak: buang agar tidak menyumbat antrean
        await db.removeOps([op.opId]);
      }
    }

    if (entries.isEmpty) return const SyncResult();

    final totals = _PushTotals();
    for (final batch in _batchOps(entries)) {
      totals.add(await _sendBatch(batch));
    }

    return totals.toResult();
  }

  /// Memecah operasi menjadi batch kecil berdasarkan ukuran JSON.
  Iterable<List<_PushOp>> _batchOps(List<_PushOp> ops) sync* {
    var batch = <_PushOp>[];
    var bytes = 0;

    for (final op in ops) {
      final size = op.estimateBytes;
      final full =
          batch.isNotEmpty &&
          (bytes + size > _maxPushBytes || batch.length >= _maxPushOps);
      if (full) {
        yield batch;
        batch = [];
        bytes = 0;
      }
      batch.add(op);
      bytes += size;
    }

    if (batch.isNotEmpty) yield batch;
  }

  Future<_PushTotals> _sendBatch(List<_PushOp> batch) async {
    try {
      final res = await api.post('/sync/push', {
        'ops': [for (final op in batch) op.body],
      });
      final results = (res['results'] as List?)?.cast<Map>() ?? const [];

      final done = <String>[];
      final totals = _PushTotals();

      for (final r in results) {
        final opId = r['opId']?.toString();
        if (opId == null) continue;
        final status = r['status']?.toString();

        switch (status) {
          case 'applied':
            totals.applied++;
            done.add(opId);
          case 'conflict':
            // Server punya versi lebih baru; pull berikutnya akan menyamakan.
            totals.conflicts++;
            done.add(opId);
          case 'ignored':
            done.add(opId);
          default:
            totals.failed++;
            done.add(opId); // Buang dari outbox agar tidak menyumbat antrean
            await db.markOpFailed(opId, r['error']?.toString() ?? 'Gagal');
        }
      }

      // Operasi yang tidak muncul di respons tetap dibiarkan untuk dicoba lagi.
      await db.removeOps(done);
      return totals;
    } on ApiException catch (e) {
      if (e.statusCode != 413) rethrow;

      // Terlalu besar untuk server (mis. batas nginx). Pecah batch jadi dua.
      if (batch.length > 1) {
        final mid = batch.length ~/ 2;
        final first = await _sendBatch(batch.sublist(0, mid));
        final second = await _sendBatch(batch.sublist(mid));
        return first..add(second);
      }

      // Satu operasi saja tetap ditolak: tandai gagal agar terlihat oleh user.
      await db.markOpFailed(
        batch.single.opId,
        'Data terlalu besar untuk server (413)',
      );
      return _PushTotals(
        failed: 1,
        error:
            'Sebagian data terlalu besar untuk server. Kecilkan lampiran foto '
            'atau naikkan client_max_body_size di reverse proxy.',
      );
    }
  }

  Future<SyncResult> _pull() async {
    var cursor = BigInt.parse(await db.getMeta('lastPullCursor') ?? '0');
    var pulled = 0;

    for (var page = 0; page < 30; page++) {
      final res = await api.get(
        '/sync/pull',
        query: {'cursor': cursor.toString(), 'limit': '500'},
      );

      final changes =
          (res['changes'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      if (changes.isNotEmpty) {
        // Jangan timpa data yang masih menunggu dikirim (edit lokal terbaru).
        final pending = await db.pendingOps(limit: 3000);
        final pendingKeys = {
          for (final op in pending) '${op.entity}:${op.entityId}',
        };
        final filtered = changes
            .where(
              (c) =>
                  !pendingKeys.contains('${c['entity']}:${c['data']?['id']}'),
            )
            .toList();
        await db.applyRemoteChanges(filtered);
        pulled += filtered.length;
      }

      cursor = BigInt.parse(res['cursor']?.toString() ?? cursor.toString());
      await db.setMeta('lastPullCursor', cursor.toString());

      if (res['hasMore'] != true) break;
    }

    return SyncResult(pulled: pulled);
  }

  /// Hapus semua data lokal lalu tarik ulang dari server (perbaikan darurat).
  Future<SyncResult> resetAndPull() async {
    await db.wipeLocalData();
    return sync();
  }
}

/// Menjalankan sync dengan debounce agar edit beruntun hanya memicu satu sync.
class SyncScheduler {
  SyncScheduler(this.engine);

  final SyncEngine engine;
  Timer? _timer;
  final StreamController<SyncResult> _results = StreamController.broadcast();

  Stream<SyncResult> get results => _results.stream;

  void schedule({Duration delay = const Duration(seconds: 3)}) {
    _timer?.cancel();
    _timer = Timer(delay, () async {
      final result = await engine.sync();
      if (!_results.isClosed) _results.add(result);
    });
  }

  Future<SyncResult> now() async {
    _timer?.cancel();
    final result = await engine.sync();
    if (!_results.isClosed) _results.add(result);
    return result;
  }

  void dispose() {
    _timer?.cancel();
    _results.close();
  }
}
