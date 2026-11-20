import 'package:flutter/material.dart';

/// Palet & tema Axon Dayli.
///
/// Setiap workspace punya warna aksen sendiri supaya konteks
/// "Pribadi vs Perusahaan" selalu terlihat. Desain dibuat ringkas dan
/// profesional: tipografi kompak, radius konsisten, dan kontras yang nyaman.

const Color kPersonalColor = Color(0xFF10B981);
const Color kCompanyColor = Color(0xFF2563EB);
const Color kDanger = Color(0xFFDC2626);
const Color kIncome = Color(0xFF059669);
const Color kExpense = Color(0xFFDC2626);

const double kRadius = 14;

ThemeData buildAppTheme({required Brightness brightness, Color? accent}) {
  final seed = accent ?? const Color(0xFF4F46E5);
  final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);

  final isLight = brightness == Brightness.light;
  final surface = isLight ? const Color(0xFFF6F7F9) : const Color(0xFF0B1220);
  final card = isLight ? Colors.white : const Color(0xFF141C2B);
  final border = isLight ? const Color(0xFFE5E7EB) : const Color(0xFF1F2A3C);

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: surface,
    visualDensity: VisualDensity.compact,
  );

  final textTheme = base.textTheme
      .apply(bodyColor: scheme.onSurface)
      .copyWith(
        titleLarge: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
          color: scheme.onSurface,
        ),
        titleMedium: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
          color: scheme.onSurface,
        ),
        titleSmall: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
          color: scheme.onSurface,
        ),
        bodyLarge: TextStyle(fontSize: 14.5, color: scheme.onSurface),
        bodyMedium: TextStyle(fontSize: 13, color: scheme.onSurface),
        bodySmall: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
        labelLarge: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
        labelMedium: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: scheme.onSurfaceVariant,
        ),
      );

  return base.copyWith(
    textTheme: textTheme,
    cardTheme: CardThemeData(
      color: card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadius),
        side: BorderSide(color: border),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      centerTitle: false,
      scrolledUnderElevation: 0,
      toolbarHeight: 56,
      titleTextStyle: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: scheme.onSurface,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: card,
      indicatorColor: scheme.primary.withValues(alpha: 0.12),
      elevation: 0,
      height: 62,
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isLight ? const Color(0xFFF1F2F4) : const Color(0xFF1B2434),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      hintStyle: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
      labelStyle: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.primary, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kDanger, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kDanger, width: 1.4),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      side: BorderSide.none,
      backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      selectedColor: scheme.primary.withValues(alpha: 0.14),
      labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    ),
    dividerTheme: DividerThemeData(
      color: border,
      thickness: 1,
      space: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      contentTextStyle: const TextStyle(fontSize: 13),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      dense: true,
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? scheme.onPrimary : null,
      ),
    ),
    radioTheme: RadioThemeData(visualDensity: VisualDensity.compact),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      visualDensity: VisualDensity.compact,
    ),
  );
}

/// Warna aksen sesuai tipe workspace.
Color workspaceColor(String type) => type == 'COMPANY' ? kCompanyColor : kPersonalColor;

Color statusColor(String status) {
  switch (status) {
    case 'DONE':
      return const Color(0xFF059669);
    case 'IN_PROGRESS':
      return const Color(0xFF2563EB);
    case 'BLOCKED':
      return const Color(0xFFDC2626);
    case 'CANCELLED':
      return const Color(0xFF64748B);
    default:
      return const Color(0xFFF59E0B);
  }
}

String statusLabel(String status) {
  switch (status) {
    case 'IN_PROGRESS':
      return 'Dikerjakan';
    case 'BLOCKED':
      return 'Terbentur';
    case 'DONE':
      return 'Selesai';
    case 'CANCELLED':
      return 'Dibatalkan';
    default:
      return 'Belum mulai';
  }
}

String priorityLabel(int priority) {
  switch (priority) {
    case 1:
      return 'Mendesak';
    case 2:
      return 'Normal';
    case 3:
      return 'Rendah';
    default:
      return 'Santai';
  }
}

Color priorityColor(int priority) {
  switch (priority) {
    case 1:
      return const Color(0xFFDC2626);
    case 2:
      return const Color(0xFFF59E0B);
    case 3:
      return const Color(0xFF0EA5E9);
    default:
      return const Color(0xFF94A3B8);
  }
}
