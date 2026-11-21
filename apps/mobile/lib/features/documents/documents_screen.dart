import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../app/providers.dart';
import '../../core/dates.dart';
import '../../core/pdf_exporter.dart';
import '../../core/theme.dart';
import '../../data/local/database.dart';
import '../common/widgets.dart';
import 'document_editor.dart';

final docViewModeProvider = StateProvider<String>((ref) => 'CARD');

class DocumentsScreen extends ConsumerWidget {
  const DocumentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final documents = ref.watch(documentsProvider).valueOrNull ?? const <DocEntry>[];
    final selectedCategory = ref.watch(docCategoryFilterProvider);
    final search = ref.watch(docSearchProvider);
    final viewMode = ref.watch(docViewModeProvider);
    final workspace = ref.watch(currentWorkspaceProvider);
    final isCompany = workspace?.type == 'COMPANY';

    final categories = <String, String>{
      'ALL': 'Semua',
      'IDENTITY': 'Identitas (KTP, KK, SIM)',
      'LEGAL': 'Properti (Sertifikat, AJB)',
      'VEHICLE': 'Kendaraan (STNK, BPKB)',
      'TAX': 'Pajak & NPWP',
      'BUSINESS': 'Hukum & Company NIB',
      'EDUCATION': 'Ijazah & Karir',
      'OTHER': 'Lainnya',
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(isCompany ? 'Dokumen Legal Perusahaan' : 'Brankas Dokumen Pribadi'),
        actions: [
          IconButton(
            tooltip: viewMode == 'TABLE' ? 'Tampilan Kartu' : 'Tampilan Tabel Data',
            icon: Icon(
              viewMode == 'TABLE' ? Icons.grid_view_rounded : Icons.table_chart_outlined,
            ),
            onPressed: () {
              ref.read(docViewModeProvider.notifier).state = viewMode == 'TABLE' ? 'CARD' : 'TABLE';
            },
          ),
          IconButton(
            onPressed: () => showDocumentEditor(context, ref),
            icon: const Icon(Icons.add),
            tooltip: 'Tambah Dokumen',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          // Banner Ringkasan Dokumen
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Card(
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    colors: [
                      (isCompany ? kCompanyColor : kPersonalColor).withValues(alpha: 0.14),
                      theme.colorScheme.surface,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: (isCompany ? kCompanyColor : kPersonalColor).withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isCompany ? Icons.gavel_rounded : Icons.folder_shared_rounded,
                        size: 26,
                        color: isCompany ? kCompanyColor : kPersonalColor,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isCompany ? 'Brankas Legal & Akta Notaris' : 'Brankas Identitas & Dokumen',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${documents.length} Berkas tersimpan secara aman & offline',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Search Bar & Filter Chips
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: [
                ShadInput(
                  placeholder: const Text('Cari NIK, NPWP, Akta, atau Nama Pemilik...'),
                  leading: const Icon(Icons.search, size: 18),
                  onChanged: (val) => ref.read(docSearchProvider.notifier).state = val,
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 38,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final entry in categories.entries) ...[
                        ChoiceChip(
                          selected: selectedCategory == entry.key,
                          onSelected: (_) => ref.read(docCategoryFilterProvider.notifier).state = entry.key,
                          label: Text(entry.value, style: const TextStyle(fontSize: 11.5)),
                        ),
                        const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          if (documents.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
              child: Card(
                child: EmptyState(
                  icon: Icons.folder_outlined,
                  title: 'Belum ada dokumen',
                  message: search.isNotEmpty
                      ? 'Tidak ada dokumen yang sesuai kata kunci.'
                      : 'Simpan KTP, KK, Buku Nikah, Akta Notaris, NPWP, atau NIB di brankas aman ini.',
                  action: FilledButton.tonalIcon(
                    onPressed: () => showDocumentEditor(context, ref),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Simpan Dokumen'),
                  ),
                ),
              ),
            )
          else if (viewMode == 'TABLE')
            _DocumentTableView(documents: documents)
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  for (final doc in documents) ...[
                    const SizedBox(height: 8),
                    _DocumentCard(doc: doc),
                  ],
                ],
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showDocumentEditor(context, ref),
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('Simpan Berkas'),
      ),
    );
  }
}

class _DocumentCard extends ConsumerWidget {
  const _DocumentCard({required this.doc});

  final DocEntry doc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final attachmentsList = _parseAttachments(doc.attachments);
    final catColor = _colorForCategory(doc.category);

    final isExpired = doc.expiryDate != null && doc.expiryDate!.isBefore(DateTime.now());
    final diffDays = doc.expiryDate != null ? doc.expiryDate!.difference(DateTime.now()).inDays : 999;

    Color expiryColor;
    String expiryLabel;

    if (doc.expiryDate == null) {
      expiryColor = const Color(0xFF059669);
      expiryLabel = 'Seumur Hidup';
    } else if (isExpired) {
      expiryColor = Colors.red.shade700;
      expiryLabel = 'Kadaluarsa';
    } else if (diffDays <= 30) {
      expiryColor = Colors.orange.shade800;
      expiryLabel = '$diffDays hr lagi';
    } else {
      expiryColor = const Color(0xFF059669);
      expiryLabel = formatDate(doc.expiryDate!);
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: InkWell(
        onTap: () => showDocumentEditor(context, ref, existing: doc),
        child: Column(
          children: [
            // Top Color Accent Line
            Container(height: 3.5, color: catColor),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: catColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(_iconForCategory(doc.category), size: 22, color: catColor),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              doc.title,
                              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, letterSpacing: -0.2),
                            ),
                            if (doc.holderName?.isNotEmpty == true) ...[
                              const SizedBox(height: 2),
                              Text(
                                'a.n ${doc.holderName}',
                                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: theme.colorScheme.primary),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: expiryColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          expiryLabel,
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: expiryColor),
                        ),
                      ),
                    ],
                  ),

                  if (doc.docNumber?.isNotEmpty == true) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.tag_rounded, size: 14, color: Colors.grey),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              doc.docNumber!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, fontFamily: 'monospace'),
                            ),
                          ),
                          InkWell(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: doc.docNumber!));
                              showAppSnack(context, 'Nomor "${doc.docNumber}" disalin!');
                            },
                            child: Row(
                              children: [
                                Icon(Icons.copy_rounded, size: 12, color: theme.colorScheme.primary),
                                const SizedBox(width: 3),
                                Text('Salin', style: TextStyle(fontSize: 10.5, color: theme.colorScheme.primary, fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (doc.issueDate != null)
                        Text('Terbit: ${formatDate(doc.issueDate!)}', style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                      const Spacer(),
                      if (attachmentsList.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.photo_library_outlined, size: 12, color: theme.colorScheme.primary),
                              const SizedBox(width: 4),
                              Text(
                                '${attachmentsList.length} Berkas',
                                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: theme.colorScheme.primary),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(width: 8),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        tooltip: 'Cetak / Share PDF Report Dokumen',
                        icon: const Icon(Icons.picture_as_pdf_outlined, size: 20, color: Color(0xFFDC2626)),
                        onPressed: () => DocumentPdfExporter.exportAndShareDocumentPdf(doc),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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

  static IconData _iconForCategory(String cat) {
    switch (cat) {
      case 'IDENTITY':
        return Icons.badge_outlined;
      case 'LEGAL':
        return Icons.gavel_outlined;
      case 'TAX':
        return Icons.receipt_long_outlined;
      case 'BUSINESS':
        return Icons.business_center_outlined;
      default:
        return Icons.description_outlined;
    }
  }

  static Color _colorForCategory(String cat) {
    switch (cat) {
      case 'IDENTITY':
        return const Color(0xFF2563EB);
      case 'LEGAL':
        return const Color(0xFF7C3AED);
      case 'VEHICLE':
        return const Color(0xFFD97706);
      case 'TAX':
        return const Color(0xFF059669);
      case 'BUSINESS':
        return const Color(0xFFDC2626);
      case 'EDUCATION':
        return const Color(0xFF0284C7);
      default:
        return const Color(0xFF64748B);
    }
  }
}

class _DocumentTableView extends ConsumerWidget {
  const _DocumentTableView({required this.documents});

  final List<DocEntry> documents;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.dividerColor),
          ),
          child: DataTable(
            columnSpacing: 14,
            headingRowHeight: 40,
            dataRowMaxHeight: 60,
            headingRowColor: WidgetStatePropertyAll(theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)),
            columns: const [
              DataColumn(label: Text('DOKUMEN & AN', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800))),
              DataColumn(label: Text('NOMOR INDEKS / SURAT', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800))),
              DataColumn(label: Text('MASA BERLAKU / EXP', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800))),
              DataColumn(label: Text('BERKAS', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800))),
              DataColumn(label: Text('AKSI', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800))),
            ],
            rows: [
              for (final doc in documents)
                DataRow(
                  onSelectChanged: (_) => showDocumentEditor(context, ref, existing: doc),
                  cells: [
                    DataCell(
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: _DocumentCard._colorForCategory(doc.category).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(_DocumentCard._iconForCategory(doc.category), size: 16, color: _DocumentCard._colorForCategory(doc.category)),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(doc.title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                              if (doc.holderName?.isNotEmpty == true)
                                Text('a.n ${doc.holderName}', style: TextStyle(fontSize: 10.5, color: theme.colorScheme.onSurfaceVariant)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    DataCell(
                      doc.docNumber?.isNotEmpty == true
                          ? Row(
                              children: [
                                Text(doc.docNumber!, style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace', fontWeight: FontWeight.w700)),
                                const SizedBox(width: 4),
                                InkWell(
                                  onTap: () {
                                    Clipboard.setData(ClipboardData(text: doc.docNumber!));
                                    showAppSnack(context, 'Nomor "${doc.docNumber}" disalin!');
                                  },
                                  child: Icon(Icons.copy, size: 12, color: theme.colorScheme.primary),
                                ),
                              ],
                            )
                          : const Text('-', style: TextStyle(fontSize: 11)),
                    ),
                    DataCell(
                      _buildExpiryBadge(doc, theme),
                    ),
                    DataCell(
                      Row(
                        children: [
                          Icon(Icons.photo_library_outlined, size: 14, color: theme.colorScheme.primary),
                          const SizedBox(width: 4),
                          Text('${_DocumentCard._parseAttachments(doc.attachments).length} Berkas', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: theme.colorScheme.primary)),
                        ],
                      ),
                    ),
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Cetak / Share PDF Report',
                            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18, color: Color(0xFFDC2626)),
                            onPressed: () => DocumentPdfExporter.exportAndShareDocumentPdf(doc),
                          ),
                          IconButton(
                            tooltip: 'Edit Dokumen',
                            icon: const Icon(Icons.edit_outlined, size: 16),
                            onPressed: () => showDocumentEditor(context, ref, existing: doc),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpiryBadge(DocEntry doc, ThemeData theme) {
    if (doc.expiryDate == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF059669).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text('Seumur Hidup', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF059669))),
      );
    }

    final isExpired = doc.expiryDate!.isBefore(DateTime.now());
    final diffDays = doc.expiryDate!.difference(DateTime.now()).inDays;

    Color color;
    String label;

    if (isExpired) {
      color = Colors.red.shade700;
      label = 'Kadaluarsa';
    } else if (diffDays <= 30) {
      color = Colors.orange.shade800;
      label = 'Exp $diffDays hr lagi';
    } else {
      color = const Color(0xFF059669);
      label = formatDate(doc.expiryDate!);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }
}
