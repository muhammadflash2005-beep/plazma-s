import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UpdateNotificationService {
  UpdateNotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static const _lastNotifiedVersionKey = 'last_notified_update_version';
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized || kIsWeb || !Platform.isAndroid) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    try {
      await _plugin.initialize(settings: settings);
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        'plazma_s_updates',
        'Plazma S updates',
        description: 'Notifications when a new Plazma S version is available',
        importance: Importance.high,
      ));
      await android?.requestNotificationsPermission();
      _initialized = true;
    } catch (_) {
      // A denied notification permission must never prevent the app from starting.
    }
  }

  static Future<void> showUpdateAvailable(String version) async {
    if (kIsWeb || !Platform.isAndroid) return;
    if (!_initialized) await initialize();
    if (!_initialized) return;
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getString(_lastNotifiedVersionKey) == version) return;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'plazma_s_updates',
        'Plazma S updates',
        channelDescription: 'Notifications when a new Plazma S version is available',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.status,
        icon: '@mipmap/ic_launcher',
        styleInformation: BigTextStyleInformation(
          'A newer version is ready. Open Plazma S and go to Me → Settings → App updates to download and install it.',
        ),
      ),
    );
    await _plugin.show(
      id: 724,
      title: 'Plazma S update available',
      body: 'Version $version is ready to download.',
      notificationDetails: details,
      payload: version,
    );
    await preferences.setString(_lastNotifiedVersionKey, version);
  }
}
