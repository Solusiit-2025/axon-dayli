import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../app/providers.dart';
import '../../core/dates.dart';
import '../../core/theme.dart';
import '../../data/local/database.dart';
import '../common/widgets.dart';
import 'document_editor.dart';

class DocumentsScreen extends ConsumerWidget {
  const DocumentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final documents = ref.watch(documentsProvider).valueOrNull ?? const <DocEntry>[];
    final selectedCategory = ref.watch(docCategoryFilterProvider);
    final search = ref.watch(docSearchProvider);
    final workspace = ref.watch(currentWorkspaceProvider);
    final isCompany = workspace?.type == 'COMPANY';

    final categories = <String, String>{
      'ALL': 'Semua',
      'IDENTITY': 'Identitas (KTP, KK)',
      'LEGAL': 'Akta & Notaris',
      'TAX': 'Pajak (NPWP)',
      'BUSINESS': 'Usaha (NIB, SIUP)',
      'OTHER': 'Lainnya',
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(isCompany ? 'Dokumen Legal Perusahaan' : 'Brankas Dokumen Pribadi'),
        actions: [
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

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showDocumentEditor(context, ref, existing: doc),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _colorForCategory(doc.category).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(_iconForCategory(doc.category), size: 20, color: _colorForCategory(doc.category)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          doc.title,
                          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                        ),
                        if (doc.holderName?.isNotEmpty == true)
                          Text(
                            'a.n ${doc.holderName}',
                            style: TextStyle(fontSize: 11.5, color: theme.colorScheme.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: () => showDocumentEditor(context, ref, existing: doc),
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
                      Text(
                        'No: ${doc.docNumber!}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, fontFamily: 'monospace'),
                      ),
                      const Spacer(),
                      InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: doc.docNumber!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Nomor "${doc.docNumber}" berhasil disalin!'),
                              duration: const Duration(milliseconds: 1500),
                            ),
                          );
                        },
                        child: Row(
                          children: [
                            Icon(Icons.copy, size: 12, color: theme.colorScheme.primary),
                            const SizedBox(width: 3),
                            Text('Salin', style: TextStyle(fontSize: 10.5, color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 10),
              Row(
                children: [
                  if (doc.issueDate != null)
                    Text(
                      'Terbit: ${formatDate(doc.issueDate!)}',
                      style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                    ),
                  if (doc.issueDate != null && doc.expiryDate != null)
                    const Text(' · ', style: TextStyle(fontSize: 11)),
                  if (doc.expiryDate != null)
                    Text(
                      'Exp: ${formatDate(doc.expiryDate!)}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: doc.expiryDate!.isBefore(DateTime.now()) ? Colors.red.shade700 : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  const Spacer(),
                  if (attachmentsList.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.photo_library_outlined, size: 12, color: theme.colorScheme.primary),
                          const SizedBox(width: 4),
                          Text(
                            '${attachmentsList.length} Foto Berkas',
                            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: theme.colorScheme.primary),
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
      case 'TAX':
        return const Color(0xFF059669);
      case 'BUSINESS':
        return const Color(0xFFD97706);
      default:
        return const Color(0xFF64748B);
    }
  }
}
