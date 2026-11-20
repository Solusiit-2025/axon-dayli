import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Layanan notifikasi lokal untuk pengingat kegiatan.
///
/// Catatan desain:
///  - Pengingat dijadwalkan di perangkat, jadi tetap berbunyi walau offline.
///  - Waktu selalu dikirim sebagai instant (DateTime lokal), lalu dikonversi
///    ke zona perangkat. Offset zona dibekukan saat start agar konsisten
///    untuk pengingat berulang (Indonesia tidak memakai DST).
///  - Id notifikasi diturunkan dari id pengingat supaya bisa dibatalkan
///    tanpa menyimpan pemetaan tambahan.
class NotificationsService {
  NotificationsService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  bool _ready = false;
  bool? _granted;

  /// ID kanal. Jangan diubah setelah rilis — kanal Android bersifat permanen.
  /// v2: importance maksimum + suara lewat jalur alarm, agar berbunyi walau
  /// HP dalam mode senyap (kanal lama bersifat immutable).
  static const _channelId = 'axon_dayli_reminders_v2';
  static const _channelName = 'Pengingat kegiatan';
  static const _channelDescription =
      'Notifikasi jadwal kegiatan, tenggat tugas, dan agenda dari Axon Dayli.';

  /// Dipanggil saat pengguna mengetuk notifikasi. Payload berisi id entitas.
  void Function(String payload)? _onTap;
  String? _pendingPayload;

  set onNotificationTap(void Function(String payload)? handler) {
    _onTap = handler;
    final pending = _pendingPayload;
    if (pending != null && handler != null) {
      _pendingPayload = null;
      handler(pending);
    }
  }

  Future<void> init() async {
    if (_ready) return;

    tzdata.initializeTimeZones();
    // PENTING: jangan membuat lokasi zona kustom (mis. "DeviceLocal").
    // Plugin Android memvalidasi nama zona lewat ZoneId.of(), sehingga nama
    // kustom memicu "Unknown time-zone ID" dan penjadwalan gagal total.
    // UTC aman: instant tetap benar karena plugin menggabungkan wall-clock
    // UTC dengan nama zona "UTC".
    tz.setLocalLocation(tz.UTC);

    const android = AndroidInitializationSettings('@drawable/ic_notification');
    const settings = InitializationSettings(android: android);

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          _onTap?.call(payload);
        }
      },
    );

    // App dibuka dari notifikasi (mis. setelah proses dimatikan sistem).
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      final payload = launch?.notificationResponse?.payload;
      if (payload != null && payload.isNotEmpty) {
        if (_onTap != null) {
          _onTap!(payload);
        } else {
          _pendingPayload = payload;
        }
      }
    }

    _ready = true;
  }

  /// Apakah sistem mengizinkan alarm tepat waktu (Android 12+).
  Future<bool> exactAlarmsAllowed() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    try {
      return await android?.canScheduleExactNotifications() ?? true;
    } catch (_) {
      return false;
    }
  }

  /// Meminta izin "Alarm & pengingat" (membuka pengaturan sistem).
  Future<bool> requestExactAlarmsPermission() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    try {
      await android?.requestExactAlarmsPermission();
    } catch (error) {
      debugPrint('Gagal meminta izin alarm tepat waktu: $error');
    }
    return exactAlarmsAllowed();
  }

  /// Meminta izin notifikasi (Android 13+). Aman dipanggil berulang.
  Future<bool> ensurePermission() async {
    if (_granted != null) return _granted!;
    await init();

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    try {
      final granted = await android?.requestNotificationsPermission();
      _granted = granted ?? true;
    } catch (error) {
      debugPrint('Gagal meminta izin notifikasi: $error');
      _granted = false;
    }
    return _granted!;
  }

  /// Menjadwalkan satu pengingat. Melewati jadwal yang sudah lewat.
  Future<void> schedule({
    required String reminderId,
    required String title,
    String? body,
    required DateTime triggerAt,
    String? recurrenceRule,
    String? payload,
  }) async {
    await init();

    final when = _nextOccurrence(triggerAt, recurrenceRule);
    if (when == null) {
      await cancel(reminderId);
      return;
    }

    final components = _componentsFor(recurrenceRule);

    // Pilih mode exact bila diizinkan sistem, supaya bunyi tepat waktu.
    // Kalau tidak diizinkan (Android 14+ sering menolak exact), pakai inexact.
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    var mode = AndroidScheduleMode.inexactAllowWhileIdle;
    try {
      if (await android?.canScheduleExactNotifications() ?? false) {
        mode = AndroidScheduleMode.exactAllowWhileIdle;
      }
    } catch (_) {
      // Tetap pakai inexact bila pengecekan gagal.
    }

    // Wall-clockwall time disesuaikan tepat dengan jam & menit lokal HP.
    final scheduled = tz.TZDateTime(
      tz.UTC,
      when.year,
      when.month,
      when.day,
      when.hour,
      when.minute,
      when.second,
    );

    Future<void> dispatch(AndroidScheduleMode scheduleMode, {bool fullScreen = false}) {
      return _plugin.zonedSchedule(
        notificationId(reminderId),
        title,
        body,
        scheduled,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.max,
            priority: Priority.max,
            icon: 'ic_notification',
            category: AndroidNotificationCategory.reminder,
            visibility: NotificationVisibility.public,
            fullScreenIntent: fullScreen,
            audioAttributesUsage: AudioAttributesUsage.alarm,
            styleInformation: body == null || body.isEmpty
                ? null
                : BigTextStyleInformation(body),
            ticker: title,
          ),
        ),
        androidScheduleMode: scheduleMode,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: components,
        payload: payload,
      );
    }

    try {
      await dispatch(mode, fullScreen: false);
    } on PlatformException catch (error) {
      if (mode == AndroidScheduleMode.inexactAllowWhileIdle) rethrow;
      debugPrint('Exact alarm ditolak (${error.code}), memakai inexact.');
      await dispatch(AndroidScheduleMode.inexactAllowWhileIdle, fullScreen: false);
    } catch (e) {
      try {
        await dispatch(AndroidScheduleMode.inexactAllowWhileIdle, fullScreen: false);
      } catch (err) {
        debugPrint('Gagal menjadwalkan notifikasi: $err');
      }
    }
  }

  Future<void> cancel(String reminderId) async {
    await init();
    await _plugin.cancel(notificationId(reminderId));
  }

  Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
  }

  /// Menjadwalkan ulang semua pengingat aktif (dipanggil saat app dibuka).
  Future<void> rescheduleAll(Iterable<ReminderSchedule> reminders) async {
    await init();
    for (final reminder in reminders) {
      if (!reminder.isActive) {
        await cancel(reminder.id);
        continue;
      }
      await schedule(
        reminderId: reminder.id,
        title: reminder.title,
        body: reminder.message,
        triggerAt: reminder.snoozeUntil ?? reminder.triggerAt,
        recurrenceRule: reminder.recurrenceRule,
        payload: reminder.entityId,
      );
    }
  }

  /// Menghitung kemunculan berikutnya; null jika tidak ada lagi.
  DateTime? _nextOccurrence(DateTime base, String? rule) {
    final now = DateTime.now();
    if (!base.isBefore(now)) return base;
    if (rule == null || rule.isEmpty) return null;

    switch (rule) {
      case 'DAILY':
        var next = base;
        while (next.isBefore(now)) {
          next = next.add(const Duration(days: 1));
        }
        return next;
      case 'WEEKLY':
        var next = base;
        while (next.isBefore(now)) {
          next = next.add(const Duration(days: 7));
        }
        return next;
      default:
        return null;
    }
  }

  DateTimeComponents? _componentsFor(String? rule) {
    switch (rule) {
      case 'DAILY':
        return DateTimeComponents.time;
      case 'WEEKLY':
        return DateTimeComponents.dayOfWeekAndTime;
      default:
        return null;
    }
  }

  /// Id notifikasi Android harus int 32-bit positif dan stabil.
  static int notificationId(String key) {
    var hash = 0x811C9DC5;
    for (final unit in key.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash & 0x7FFFFFFF;
  }
}

/// Bentuk minimal yang dibutuhkan penjadwal (memisahkan lapisan data & UI).
class ReminderSchedule {
  const ReminderSchedule({
    required this.id,
    required this.title,
    required this.triggerAt,
    this.message,
    this.recurrenceRule,
    this.snoozeUntil,
    this.entityId,
    this.isActive = true,
  });

  final String id;
  final String title;
  final String? message;
  final DateTime triggerAt;
  final DateTime? snoozeUntil;
  final String? recurrenceRule;
  final String? entityId;
  final bool isActive;
}
