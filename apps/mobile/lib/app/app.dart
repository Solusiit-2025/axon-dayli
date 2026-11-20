import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/theme.dart';
import 'providers.dart';
import 'router.dart';

class AxonDayliApp extends ConsumerWidget {
  const AxonDayliApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final workspace = ref.watch(currentWorkspaceProvider);
    final accent = workspace == null ? null : workspaceColor(workspace.type);

    return MaterialApp.router(
      title: 'Axon Dayli',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      themeMode: ThemeMode.system,
      theme: buildAppTheme(brightness: Brightness.light, accent: accent),
      darkTheme: buildAppTheme(brightness: Brightness.dark, accent: accent),
      builder: (context, child) {
        return ShadTheme(
          data: ShadThemeData(
            brightness: Theme.of(context).brightness,
            colorScheme: Theme.of(context).brightness == Brightness.dark
                ? const ShadSlateColorScheme.dark()
                : const ShadSlateColorScheme.light(),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
