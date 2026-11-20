import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/local/database.dart';
import '../common/widgets.dart';
import 'asset_editor.dart';

class AssetsScreen extends ConsumerWidget {
  const AssetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final assets = ref.watch(assetsProvider).valueOrNull ?? const <Asset>[];
    final total = ref.watch(assetTotalProvider);
    final workspace = ref.watch(currentWorkspaceProvider);
    final isCompany = workspace?.type == 'COMPANY';

    final active = assets.where((a) => a.status == 'ACTIVE').toList();
    final others = assets.where((a) => a.status != 'ACTIVE').toList();

    final byCategory = <String, List<Asset>>{};
    for (final a in active) {
      byCategory.putIfAbsent(a.category, () => []).add(a);
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        isCompany ? Icons.business_rounded : Icons.person_rounded,
                        size: 15,
                        color: isCompany ? kCompanyColor : kPersonalColor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isCompany ? 'Aset Perusahaan' : 'Aset Pribadi',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: isCompany ? kCompanyColor : kPersonalColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    formatMoney(total),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.8),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${active.length} aset aktif${others.isEmpty ? '' : ' · ${others.length} lainnya'}',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),

        if (assets.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Card(
              child: EmptyState(
                icon: Icons.inventory_2_outlined,
                title: 'Belum ada aset',
                message: 'Catat kendaraan, properti, atau peralatan untuk memantau nilainya.',
                action: FilledButton.tonal(
                  onPressed: () => showAssetEditor(context, ref),
                  child: const Text('Tambah aset'),
                ),
              ),
            ),
          )
        else ...[
          for (final entry in byCategory.entries) ...[
            SectionHeader(
              title: assetCategories[entry.key] ?? entry.key,
              action: Text(
                formatCompactMoney(entry.value.fold<int>(0, (s, a) => s + a.currentValue)),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                child: Column(
                  children: [
                    for (var i = 0; i < entry.value.length; i++) ...[
                      if (i > 0) const Divider(height: 1, indent: 52),
                      ListTile(
                        leading: CircleAvatar(
                          radius: 17,
                          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
                          child: Icon(
                            _iconFor(entry.key),
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        title: Text(
                          entry.value[i].name,
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                        ),
                        subtitle: Row(
                          children: [
                            if (entry.value[i].attachments?.isNotEmpty == true) ...[
                              Icon(Icons.photo_library_outlined, size: 12, color: theme.colorScheme.primary),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              _statusLabel(entry.value[i].status),
                              style: TextStyle(
                                fontSize: 11,
                                color: entry.value[i].status == 'ACTIVE'
                                    ? theme.colorScheme.onSurfaceVariant
                                    : kDanger,
                              ),
                            ),
                          ],
                        ),
                        trailing: MoneyText(entry.value[i].currentValue, fontSize: 13, bold: true),
                        onTap: () => context.push('/asset/${entry.value[i].id}'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
          if (others.isNotEmpty) ...[
            const SectionHeader(title: 'Tidak aktif'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                child: Column(
                  children: [
                    for (var i = 0; i < others.length; i++) ...[
                      if (i > 0) const Divider(height: 1, indent: 52),
                      ListTile(
                        leading: Icon(Icons.archive_outlined, size: 18, color: theme.colorScheme.outline),
                        title: Text(
                          others[i].name,
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(_statusLabel(others[i].status), style: const TextStyle(fontSize: 11)),
                        trailing: MoneyText(
                          others[i].currentValue,
                          fontSize: 13,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        onTap: () => context.push('/asset/${others[i].id}'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }

  static IconData _iconFor(String category) {
    switch (category) {
      case 'vehicle':
        return Icons.directions_car_outlined;
      case 'property':
        return Icons.home_outlined;
      case 'electronics':
        return Icons.devices_outlined;
      case 'investment':
        return Icons.trending_up;
      case 'equipment':
        return Icons.handyman_outlined;
      default:
        return Icons.inventory_2_outlined;
    }
  }

  static String _statusLabel(String status) {
    switch (status) {
      case 'MAINTENANCE':
        return 'Dalam perawatan';
      case 'SOLD':
        return 'Sudah terjual';
      case 'LOST':
        return 'Hilang';
      default:
        return 'Aktif';
    }
  }
}
