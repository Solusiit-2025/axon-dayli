import 'dart:convert';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../data/local/database.dart';
import 'dates.dart';

/// Service Pembuat Laporan PDF Berkas Dokumen Resmi Berkualitas Tinggi.
class DocumentPdfExporter {
  static Future<void> exportAndShareDocumentPdf(DocEntry doc) async {
    final pdfBytes = await generateDocumentPdfBytes(doc);
    final filename = '${doc.title.replaceAll(RegExp(r'[^\w\s\-]'), '_')}_Report.pdf';
    await Printing.sharePdf(bytes: pdfBytes, filename: filename);
  }

  static Future<void> printDocumentPdf(DocEntry doc) async {
    final pdfBytes = await generateDocumentPdfBytes(doc);
    await Printing.layoutPdf(
      onLayout: (format) async => pdfBytes,
      name: '${doc.title}_Report',
    );
  }

  static Future<Uint8List> generateDocumentPdfBytes(DocEntry doc) async {
    final pdf = pw.Document();

    // Parse attachments (Foto & Scan)
    final attachmentsList = _parseAttachments(doc.attachments);
    final imageWidgets = <pw.Widget>[];

    for (var i = 0; i < attachmentsList.length; i++) {
      final raw = attachmentsList[i];
      if (raw.startsWith('data:image')) {
        try {
          final base64Part = raw.split(',').last;
          final bytes = base64Decode(base64Part);
          final image = pw.MemoryImage(bytes);

          imageWidgets.add(
            pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 16),
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400, width: 1),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                color: PdfColors.white,
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Foto / Scan Berkas #${i + 1} (Tampak Jelas / Resolusi Tinggi)',
                    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Center(
                    child: pw.Image(
                      image,
                      fit: pw.BoxFit.contain,
                      height: 380,
                    ),
                  ),
                ],
              ),
            ),
          );
        } catch (_) {}
      }
    }

    final isExpired = doc.expiryDate != null && doc.expiryDate!.isBefore(DateTime.now());
    final statusText = doc.expiryDate == null
        ? 'BERLAKU SEUMUR HIDUP'
        : (isExpired ? 'KADALUARSA (EXPIRED)' : 'MASIH BERLAKU');

    final statusColor = doc.expiryDate == null
        ? PdfColors.green700
        : (isExpired ? PdfColors.red700 : PdfColors.green700);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          // Header Banner Resmi
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: const pw.BoxDecoration(
              color: PdfColors.indigo900,
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'BRANKAS DOKUMEN RESMI',
                      style: pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Axon Dayli Enterprise Document Vault — Laporan Lembar Berkas',
                      style: const pw.TextStyle(color: PdfColors.indigo100, fontSize: 10),
                    ),
                  ],
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.indigo700,
                    borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
                  ),
                  child: pw.Text(
                    'TERVERIFIKASI',
                    style: pw.TextStyle(color: PdfColors.white, fontSize: 10, fontWeight: pw.FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 20),

          // Judul Dokumen & Status
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      doc.title,
                      style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.grey900),
                    ),
                    if (doc.holderName != null && doc.holderName!.isNotEmpty) ...[
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Atas Nama / Pemilik: ${doc.holderName}',
                        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900),
                      ),
                    ],
                  ],
                ),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: statusColor, width: 1.5),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                ),
                child: pw.Text(
                  statusText,
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: statusColor),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Divider(color: PdfColors.grey300),
          pw.SizedBox(height: 14),

          // Tabel Detail Spesifikasi Dokumen
          pw.Text('Rincian Detail Berkas', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800)),
          pw.SizedBox(height: 8),

          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.8),
            children: [
              _buildTableRow('Nomor Dokumen / NIK / NPWP', doc.docNumber ?? '-', isBold: true),
              _buildTableRow('Kategori Berkas', _categoryLabel(doc.category)),
              _buildTableRow('Nama Pemilik / Atas Nama', doc.holderName ?? '-'),
              _buildTableRow('Tanggal Terbit / Dikeluarkan', doc.issueDate != null ? formatDate(doc.issueDate!) : '-'),
              _buildTableRow('Masa Berlaku / Expired Date', doc.expiryDate != null ? formatDate(doc.expiryDate!) : 'Seumur Hidup'),
              _buildTableRow('Catatan Tambahan / Lokasi', doc.note ?? '-'),
              _buildTableRow('Jumlah Lampiran Berkas', '${attachmentsList.length} Foto / Scan'),
              _buildTableRow('Waktu Cetak Laporan PDF', formatDateFull(DateTime.now())),
            ],
          ),
          pw.SizedBox(height: 24),

          // Foto / Scan Lampiran (Di-render Tampak Jelas & Besar)
          if (imageWidgets.isNotEmpty) ...[
            pw.Text('Lampiran Foto & Scan Berkas (Tampak Jelas)', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900)),
            pw.SizedBox(height: 10),
            ...imageWidgets,
          ],

          pw.SizedBox(height: 20),
          pw.Divider(color: PdfColors.grey300),
          pw.SizedBox(height: 8),

          // Footer Timestamp
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Axon Dayli Vault — Dokumen Tersimpan secara Aman & Terenkripsi', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
              pw.Text('Halaman 1 dari 1', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
            ],
          ),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.TableRow _buildTableRow(String label, String value, {bool isBold = false}) {
    return pw.TableRow(
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.all(8),
          child: pw.Text(label, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(8),
          child: pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: isBold ? PdfColors.indigo900 : PdfColors.grey900,
            ),
          ),
        ),
      ],
    );
  }

  static List<String> _parseAttachments(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.map((e) => e.toString()).toList();
    } catch (_) {}
    return [raw];
  }

  static String _categoryLabel(String cat) {
    switch (cat) {
      case 'IDENTITY':
        return 'Identitas & Kependudukan (KTP, KK, SIM, Paspor)';
      case 'LEGAL':
        return 'Properti & Legalitas (Sertifikat, Akta, PBB)';
      case 'VEHICLE':
        return 'Kendaraan & Otomotif (STNK, BPKB, Faktur)';
      case 'TAX':
        return 'Perpajakan & Keuangan (NPWP, SPT, Polis)';
      case 'BUSINESS':
        return 'Hukum & Perusahaan (NIB, SIUP, Kontrak)';
      case 'EDUCATION':
        return 'Pendidikan & Karir (Ijazah, Sertifikat)';
      default:
        return 'Lainnya';
    }
  }
}
