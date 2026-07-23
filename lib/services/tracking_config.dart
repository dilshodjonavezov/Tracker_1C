import 'package:background_location_tracker/background_location_tracker.dart';

const trackerAndroidConfig = AndroidConfig(
  channelName: 'Tracker GPS',
  notificationBody: 'Трекинг активен',
  notificationIcon: 'ic_launcher',
  enableNotificationLocationUpdates: false,
  enableCancelTrackingAction: false,
  trackingInterval: Duration(seconds: 5),
  distanceFilterMeters: 5.0,
);

const trackerLocationConfig = BackgroundLocationTrackerConfig(
  loggingEnabled: true,
  androidConfig: trackerAndroidConfig,
  iOSConfig: IOSConfig(
    activityType: ActivityType.NAVIGATION,
    distanceFilterMeters: 5,
    restartAfterKill: true,
  ),
);
