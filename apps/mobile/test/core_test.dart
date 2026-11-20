import 'package:daily_pilot/core/money.dart';
import 'package:daily_pilot/core/dates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatMoney', () {
    test('memformat rupiah tanpa desimal', () {
      expect(formatMoney(0), 'Rp0');
      expect(formatMoney(1500), 'Rp1.500');
      expect(formatMoney(1250000), 'Rp1.250.000');
    });

    test('format ringkas', () {
      expect(formatCompactMoney(1250000), 'Rp1,3 jt');
      expect(formatCompactMoney(250000), 'Rp250 rb');
    });
  });

  group('parseMoney', () {
    test('membaca input pengguna dengan pemisah ribuan', () {
      expect(parseMoney('1.250.000'), 1250000);
      expect(parseMoney('Rp 25.000'), 25000);
      expect(parseMoney(''), 0);
      expect(parseMoney('abc'), 0);
    });
  });

  group('formatMoneyInput', () {
    test('merapikan saat mengetik', () {
      expect(formatMoneyInput('1250000'), '1.250.000');
      expect(formatMoneyInput(''), '');
    });
  });

  group('tanggal', () {
    test('relativeDue memberi label yang mudah dibaca', () {
      final now = DateTime.now();
      expect(relativeDue(now), 'Hari ini');
      expect(relativeDue(now.add(const Duration(days: 1))), 'Besok');
    });

    test('isOverdue mengabaikan tugas selesai', () {
      final past = DateTime.now().subtract(const Duration(days: 2));
      expect(isOverdue(past, status: 'TODO'), isTrue);
      expect(isOverdue(past, status: 'DONE'), isFalse);
      expect(isOverdue(null, status: 'TODO'), isFalse);
    });
  });
}
