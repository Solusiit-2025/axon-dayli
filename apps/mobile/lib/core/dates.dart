import 'package:intl/intl.dart';

final DateFormat _dateShort = DateFormat('d MMM', 'id_ID');
final DateFormat _dateMedium = DateFormat('d MMM yyyy', 'id_ID');
final DateFormat _dateFull = DateFormat('EEEE, d MMMM yyyy', 'id_ID');
final DateFormat _time = DateFormat('HH:mm', 'id_ID');
final DateFormat _dayMonth = DateFormat('MMM yyyy', 'id_ID');

String formatDateShort(DateTime d) => _dateShort.format(d);
String formatDate(DateTime d) => _dateMedium.format(d);
String formatDateFull(DateTime d) => _dateFull.format(d);
String formatTime(DateTime d) => _time.format(d);
String formatMonthYear(DateTime d) => _dayMonth.format(d);

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

bool isToday(DateTime d) => isSameDay(d, DateTime.now());

DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime startOfMonth(DateTime d) => DateTime(d.year, d.month, 1);

DateTime endOfMonth(DateTime d) => DateTime(d.year, d.month + 1, 1);

DateTime addMonths(DateTime d, int months) => DateTime(d.year, d.month + months, d.day);

/// "Hari ini", "Besok", "3 hari lagi", "Terlambat 2 hari"
String relativeDue(DateTime due) {
  final now = DateTime.now();
  final today = startOfDay(now);
  final target = startOfDay(due);
  final diff = target.difference(today).inDays;

  if (diff == 0) return 'Hari ini';
  if (diff == 1) return 'Besok';
  if (diff == -1) return 'Terlambat 1 hari';
  if (diff < -1) return 'Terlambat ${diff.abs()} hari';
  if (diff < 7) return '$diff hari lagi';
  return formatDateShort(due);
}

bool isOverdue(DateTime? due, {String? status}) {
  if (due == null) return false;
  if (status == 'DONE' || status == 'CANCELLED') return false;
  return due.isBefore(DateTime.now());
}

/// Rentang minggu (Senin–Minggu) yang memuat [d].
(DateTime, DateTime) weekRange(DateTime d) {
  final monday = startOfDay(d).subtract(Duration(days: d.weekday - 1));
  return (monday, monday.add(const Duration(days: 7)));
}

/// Rentang bulan yang memuat [d].
(DateTime, DateTime) monthRange(DateTime d) {
  return (startOfMonth(d), endOfMonth(d));
}
