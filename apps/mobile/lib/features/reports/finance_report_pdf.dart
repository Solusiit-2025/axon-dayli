import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/local/database.dart';

const _indigo = PdfColor.fromInt(0xFF4F46E5);
const _green = PdfColor.fromInt(0xFF059669);
const _red = PdfColor.fromInt(0xFFDC2626);
const _slate = PdfColor.fromInt(0xFF334155);
const _muted = PdfColor.fromInt(0xFF64748B);
const _line = PdfColor.fromInt(0xFFE2E8F0);
const _soft = PdfColor.fromInt(0xFFF8FAFC);

/// Data yang dibutuhkan untuk menyusun laporan PDF.
class FinanceReportData {
  const FinanceReportData({
    required this.month,
    required this.workspaceName,
    required this.income,
    required this.expense,
    required this.net,
    required this.totalBalance,
    required this.transactions,
    required this.expenseByCategory,
    required this.incomeByCategory,
    required this.categoryMap,
    required this.balances,
    required this.budgets,
    required this.spentMap,
    required this.debts,
    required this.monthlyTrend,
  });

  final DateTime month;
  final String workspaceName;
  final int income;
  final int expense;
  final int net;
  final int totalBalance;
  final List<Txn> transactions;
  final Map<String, int> expenseByCategory;
  final Map<String, int> incomeByCategory;
  final Map<String, Category> categoryMap;
  final List<WalletBalance> balances;
  final List<Budget> budgets;
  final Map<String, int> spentMap;
  final List<Debt> debts;

  /// key: "yyyy-MM", value: [pemasukan, pengeluaran]
  final Map<String, List<int>> monthlyTrend;
}

String _money(int value) => formatMoney(value).replaceAll('Rp', 'Rp ');

String _categoryName(FinanceReportData d, String? id) {
  if (id == null || id.isEmpty) return 'Tanpa kategori';
  return d.categoryMap[id]?.name ?? 'Tanpa kategori';
}

Future<pw.Document> buildFinanceReportPdf(FinanceReportData d) async {
  final doc = pw.Document(
    title: 'Laporan Keuangan ${formatMonthYear(d.month)}',
    author: 'Axon Dayli',
  );

  final savingsRate = d.income <= 0 ? 0.0 : (d.income - d.expense) / d.income;
  final payable = d.debts.where((x) => x.direction == 'PAYABLE' && x.remaining > 0).fold<int>(0, (s, x) => s + x.remaining);
  final receivable = d.debts.where((x) => x.direction == 'RECEIVABLE' && x.remaining > 0).fold<int>(0, (s, x) => s + x.remaining);

  final incomes = d.transactions.where((t) => t.type == 'INCOME').toList()..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
  final expenses = d.transactions.where((t) => t.type == 'EXPENSE').toList()..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

  final trendKeys = d.monthlyTrend.keys.toList()..sort();

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 40),
      header: (context) => _header(d),
      footer: (context) => _footer(context),
      build: (context) => [
        pw.SizedBox(height: 8),
        _summaryCards(d, savingsRate),
        pw.SizedBox(height: 16),
        _sectionTitle('Arus Kas ${formatMonthYear(d.month)}'),
        _kvTable([
          ['Pemasukan', _money(d.income), _green],
          ['Pengeluaran', _money(d.expense), _red],
          ['Selisih bersih', _money(d.net), d.net >= 0 ? _green : _red],
          ['Tingkat tabungan', '${(savingsRate * 100).toStringAsFixed(1)}%', _slate],
          ['Saldo total dompet', _money(d.totalBalance), _slate],
        ]),
        if (trendKeys.isNotEmpty) ...[
          pw.SizedBox(height: 16),
          _sectionTitle('Arus Kas 6 Bulan Terakhir'),
          _trendTable(d, trendKeys),
        ],
        pw.SizedBox(height: 16),
        _sectionTitle('Pengeluaran per Kategori'),
        _categoryTable(d, d.expenseByCategory, d.expense, true),
        if (d.incomeByCategory.isNotEmpty) ...[
          pw.SizedBox(height: 16),
          _sectionTitle('Pemasukan per Kategori'),
          _categoryTable(d, d.incomeByCategory, d.income, false),
        ],
        if (d.budgets.isNotEmpty) ...[
          pw.SizedBox(height: 16),
          _sectionTitle('Anggaran vs Realisasi'),
          _budgetTable(d),
        ],
        pw.SizedBox(height: 16),
        _sectionTitle('Utang & Piutang'),
        _kvTable([
          ['Piutang (orang utang ke kita)', _money(receivable), _green],
          ['Utang (kita utang ke orang)', _money(payable), _red],
          ['Posisi bersih', _money(receivable - payable), receivable - payable >= 0 ? _green : _red],
        ]),
        if (d.balances.isNotEmpty) ...[
          pw.SizedBox(height: 16),
          _sectionTitle('Saldo per Dompet'),
          pw.TableHelper.fromTextArray(
            headers: const ['Dompet', 'Saldo'],
            data: [
              for (final b in d.balances) [b.name, _money(b.balance)],
              ['Total', _money(d.totalBalance)],
            ],
            headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: _slate),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignments: {1: pw.Alignment.centerRight},
            border: pw.TableBorder.symmetric(inside: const pw.BorderSide(color: _line, width: 0.5)),
            headerAlignment: pw.Alignment.centerLeft,
          ),
        ],
        pw.SizedBox(height: 20),
        _sectionTitle('Rincian Transaksi ${formatMonthYear(d.month)}'),
        pw.Text(
          'Pemasukan ${incomes.length} transaksi | Pengeluaran ${expenses.length} transaksi',
          style: const pw.TextStyle(fontSize: 8.5, color: _muted),
        ),
        pw.SizedBox(height: 8),
        if (incomes.isNotEmpty) ...[
          pw.Text('PEMASUKAN', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _green)),
          pw.SizedBox(height: 4),
          _transactionTable(d, incomes, _green),
          pw.SizedBox(height: 12),
        ],
        if (expenses.isNotEmpty) ...[
          pw.Text('PENGELUARAN', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _red)),
          pw.SizedBox(height: 4),
          _transactionTable(d, expenses, _red),
        ],
      ],
    ),
  );

  return doc;
}

pw.Widget _header(FinanceReportData d) {
  return pw.Container(
    padding: const pw.EdgeInsets.only(bottom: 10),
    decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _line, width: 1))),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Container(
          width: 30,
          height: 30,
          decoration: pw.BoxDecoration(color: _indigo, borderRadius: pw.BorderRadius.circular(7)),
          alignment: pw.Alignment.center,
          child: pw.Text('A', style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 18)),
        ),
        pw.SizedBox(width: 10),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('AXON DAYLI', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _indigo, letterSpacing: 1)),
              pw.Text('Laporan Keuangan - ${d.workspaceName}', style: const pw.TextStyle(fontSize: 8.5, color: _muted)),
            ],
          ),
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(formatMonthYear(d.month), style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _slate)),
            pw.Text('Dicetak ${formatDate(DateTime.now())}', style: const pw.TextStyle(fontSize: 8, color: _muted)),
          ],
        ),
      ],
    ),
  );
}

pw.Widget _footer(pw.Context context) {
  return pw.Container(
    padding: const pw.EdgeInsets.only(top: 6),
    decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _line, width: 1))),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text('Axon Dayli - Laporan Keuangan', style: const pw.TextStyle(fontSize: 8, color: _muted)),
        pw.Text('Halaman ${context.pageNumber} dari ${context.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: _muted)),
      ],
    ),
  );
}

pw.Widget _sectionTitle(String text) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 6),
    child: pw.Text(text, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _slate)),
  );
}

pw.Widget _summaryCards(FinanceReportData d, double savingsRate) {
  pw.Widget card(String label, String value, PdfColor color) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(9),
        decoration: pw.BoxDecoration(
          color: _soft,
          borderRadius: pw.BorderRadius.circular(6),
          border: pw.Border.all(color: _line, width: 0.6),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label, style: const pw.TextStyle(fontSize: 7.5, color: _muted)),
            pw.SizedBox(height: 4),
            pw.Text(value, style: pw.TextStyle(fontSize: 11.5, fontWeight: pw.FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }

  return pw.Row(
    children: [
      card('Pemasukan', _money(d.income), _green),
      pw.SizedBox(width: 6),
      card('Pengeluaran', _money(d.expense), _red),
      pw.SizedBox(width: 6),
      card('Selisih', _money(d.net), d.net >= 0 ? _green : _red),
      pw.SizedBox(width: 6),
      card('Tabungan', '${(savingsRate * 100).toStringAsFixed(1)}%', _indigo),
    ],
  );
}

pw.Widget _kvTable(List<List<Object>> rows) {
  return pw.Table(
    columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(2)},
    children: [
      for (final r in rows)
        pw.TableRow(
          decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _line, width: 0.5))),
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 2),
              child: pw.Text(r[0] as String, style: const pw.TextStyle(fontSize: 9, color: _slate)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 2),
              child: pw.Text(
                r[1] as String,
                textAlign: pw.TextAlign.right,
                style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: (r.length > 2 ? r[2] : _slate) as PdfColor),
              ),
            ),
          ],
        ),
    ],
  );
}

pw.Widget _trendTable(FinanceReportData d, List<String> keys) {
  final rows = <List<String>>[];
  for (final k in keys) {
    final parts = k.split('-');
    final label = '${parts[1]}/${parts[0]}';
    final v = d.monthlyTrend[k]!;
    rows.add([label, _money(v[0]), _money(v[1]), _money(v[0] - v[1])]);
  }
  return pw.TableHelper.fromTextArray(
    headers: const ['Bulan', 'Pemasukan', 'Pengeluaran', 'Selisih'],
    data: rows,
    headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
    headerDecoration: const pw.BoxDecoration(color: _indigo),
    cellStyle: const pw.TextStyle(fontSize: 8.5),
    cellAlignments: {1: pw.Alignment.centerRight, 2: pw.Alignment.centerRight, 3: pw.Alignment.centerRight},
    border: pw.TableBorder.symmetric(inside: const pw.BorderSide(color: _line, width: 0.5)),
    headerAlignment: pw.Alignment.centerLeft,
  );
}

pw.Widget _categoryTable(FinanceReportData d, Map<String, int> data, int total, bool expense) {
  final entries = data.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  if (entries.isEmpty) {
    return pw.Text('Belum ada data.', style: const pw.TextStyle(fontSize: 8.5, color: _muted));
  }
  return pw.TableHelper.fromTextArray(
    headers: const ['Kategori', 'Jumlah', 'Porsi'],
    data: [
      for (final e in entries)
        [_categoryName(d, e.key), _money(e.value), '${(e.value / (total == 0 ? 1 : total) * 100).toStringAsFixed(1)}%'],
    ],
    headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
    headerDecoration: pw.BoxDecoration(color: expense ? _red : _green),
    cellStyle: const pw.TextStyle(fontSize: 8.5),
    cellAlignments: {1: pw.Alignment.centerRight, 2: pw.Alignment.centerRight},
    border: pw.TableBorder.symmetric(inside: const pw.BorderSide(color: _line, width: 0.5)),
    headerAlignment: pw.Alignment.centerLeft,
  );
}

pw.Widget _budgetTable(FinanceReportData d) {
  final rows = <List<String>>[];
  for (final b in d.budgets) {
    final spent = d.spentMap[b.categoryId] ?? 0;
    final over = spent > b.amount;
    rows.add([
      _categoryName(d, b.categoryId),
      _money(b.amount),
      _money(spent),
      over ? 'Lewat ${_money(spent - b.amount)}' : 'Sisa ${_money(b.amount - spent)}',
    ]);
  }
  return pw.TableHelper.fromTextArray(
    headers: const ['Kategori', 'Anggaran', 'Terpakai', 'Status'],
    data: rows,
    headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
    headerDecoration: const pw.BoxDecoration(color: _slate),
    cellStyle: const pw.TextStyle(fontSize: 8.5),
    cellAlignments: {1: pw.Alignment.centerRight, 2: pw.Alignment.centerRight},
    border: pw.TableBorder.symmetric(inside: const pw.BorderSide(color: _line, width: 0.5)),
    headerAlignment: pw.Alignment.centerLeft,
  );
}

pw.Widget _transactionTable(FinanceReportData d, List<Txn> items, PdfColor color) {
  return pw.TableHelper.fromTextArray(
    headers: const ['Tanggal', 'Keterangan', 'Kategori', 'Nominal'],
    data: [
      for (final t in items)
        [
          formatDateShort(t.occurredAt),
          (t.note?.isNotEmpty == true ? t.note! : (t.payee?.isNotEmpty == true ? t.payee! : '-')),
          _categoryName(d, t.categoryId),
          _money(t.amount),
        ],
    ],
    headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
    headerDecoration: pw.BoxDecoration(color: color),
    cellStyle: const pw.TextStyle(fontSize: 8.5),
    cellAlignments: {3: pw.Alignment.centerRight},
    border: pw.TableBorder.symmetric(inside: const pw.BorderSide(color: _line, width: 0.5)),
    headerAlignment: pw.Alignment.centerLeft,
    columnWidths: const {
      0: pw.FlexColumnWidth(1.4),
      1: pw.FlexColumnWidth(3.4),
      2: pw.FlexColumnWidth(2),
      3: pw.FlexColumnWidth(1.8),
    },
  );
}

/// Membuka dialog cetak / simpan PDF.
Future<void> printFinanceReport(FinanceReportData data) async {
  final doc = await buildFinanceReportPdf(data);
  await Printing.layoutPdf(
    name: 'Laporan-Keuangan-${data.month.year}-${data.month.month.toString().padLeft(2, '0')}',
    onLayout: (format) async => doc.save(),
  );
}
