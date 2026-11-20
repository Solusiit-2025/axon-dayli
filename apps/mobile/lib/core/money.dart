import 'package:intl/intl.dart';

final NumberFormat _rupiah = NumberFormat.currency(
  locale: 'id_ID',
  symbol: 'Rp',
  decimalDigits: 0,
);

final NumberFormat _plain = NumberFormat.decimalPattern('id_ID');

/// Rp1.250.000
String formatMoney(int amount) => _rupiah.format(amount).replaceAll('Rp ', 'Rp');

/// 1.250.000
String formatNumber(num value) => _plain.format(value);

/// Rp1,2 jt / Rp250 rb — untuk kartu ringkasan yang sempit.
String formatCompactMoney(int amount) {
  final abs = amount.abs();
  final sign = amount < 0 ? '-' : '';
  if (abs >= 1000000000) {
    return '${sign}Rp${_trim(abs / 1000000000)} M';
  }
  if (abs >= 1000000) {
    return '${sign}Rp${_trim(abs / 1000000)} jt';
  }
  if (abs >= 1000) {
    return '${sign}Rp${_trim(abs / 1000)} rb';
  }
  return '$sign${formatMoney(abs)}';
}

String _trim(double value) {
  final rounded = (value * 10).round() / 10;
  return rounded == rounded.roundToDouble()
      ? rounded.toStringAsFixed(0)
      : rounded.toStringAsFixed(1).replaceAll('.', ',');
}

/// Membaca input pengguna: "1.250.000" / "1250000" / "Rp 1.250.000" → 1250000
int parseMoney(String input) {
  final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return 0;
  return int.tryParse(digits) ?? 0;
}

/// Format saat mengetik: 1250000 → 1.250.000
String formatMoneyInput(String raw) {
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return '';
  final value = int.tryParse(digits);
  if (value == null) return '';
  return _plain.format(value);
}
