import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/common/widgets.dart';
import 'providers.dart';

/// Menjalankan sinkronisasi manual sambil menampilkan status di AppBar.
Future<void> runSync(BuildContext context, WidgetRef ref) async {
  final notifier = ref.read(syncStatusProvider.notifier);
  notifier.state = 'Menyinkronkan…';
  try {
    final result = await ref.read(syncSchedulerProvider).now();
    if (context.mounted) {
      showAppSnack(context, result.describe(), error: !result.ok);
    }
  } finally {
    notifier.state = null;
  }
}
