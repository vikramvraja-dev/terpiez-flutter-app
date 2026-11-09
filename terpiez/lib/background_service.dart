import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_helper.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'terpiez_background_channel', // id
    'Terpiez Background Service', // title
    description: 'Running in the background to find Terpiez',
    importance: Importance.low,
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart, // Your background isolate function
      autoStart: true,
      isForegroundMode: true,
      
      notificationChannelId: 'terpiez_background_channel', 
      initialNotificationTitle: 'Terpiez',
      initialNotificationContent: 'Scanning for nearby Terpiez...',
      foregroundServiceNotificationId: 888, 
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}


@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  await NotificationHelper.initializeBackground();

  String? lastNotifiedTerpieId;

  Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 2,
    ),
  ).listen((Position position) async {
    final prefs = await SharedPreferences.getInstance();
    final String? terpiezJson = prefs.getString('terpiez_locations');
    
    if (terpiezJson == null) return;

    List<dynamic> terpiezLocations = jsonDecode(terpiezJson);
    double minDistance = double.infinity;
    String? closestId;

    for (var terpie in terpiezLocations) {
      double distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        terpie['lat'],
        terpie['lon'],
      );

      if (distance < minDistance) {
        minDistance = distance;
        closestId = terpie['id'].toString();
      }
    }

    //Trigger Notification Logic
    if (minDistance <= 20.0) {
      if (lastNotifiedTerpieId != closestId) {
        lastNotifiedTerpieId = closestId;
        await NotificationHelper.showProximityNotification(closestId!);
      }
    } else {
      // Reset if they walk away so it can trigger again later
      lastNotifiedTerpieId = null; 
    }
  });
}