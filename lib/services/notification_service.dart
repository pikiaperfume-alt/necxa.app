import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import '../models/notification_model.dart';
import 'local_db_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  final LocalDbService _localDb = LocalDbService();

  Future<void> init() async {
    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Handle notification tap
        debugPrint('Notification clicked: ${response.payload}');
      },
    );
  }

  Future<void> requestPermissions() async {
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidImplementation?.requestNotificationsPermission();
  }

  Future<void> showNotification(AppNotification notif) async {
    // 1. Show System Notification
    const AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'necxa_main_channel',
      'Necxa Notifications',
      channelDescription: 'Main notification channel for Necxa',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
    );
    const NotificationDetails platformChannelSpecifics = NotificationDetails(android: androidPlatformChannelSpecifics);
    
    await flutterLocalNotificationsPlugin.show(
      notif.id.hashCode,
      notif.title,
      notif.body,
      platformChannelSpecifics,
      payload: notif.payload,
    );

    // 2. Save to Local DB for offline access
    await _localDb.saveNotification(notif.toMap());
  }

  Future<void> simulateNotification(String type, String title, String body) async {
    final notif = AppNotification(
      id: 'notif_${DateTime.now().millisecondsSinceEpoch}',
      type: type,
      title: title,
      body: body,
      createdAt: DateTime.now(),
    );
    await showNotification(notif);
  }
}
