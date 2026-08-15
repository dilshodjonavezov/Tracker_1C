import 'package:background_location_tracker/background_location_tracker.dart';

const trackerAndroidConfig = AndroidConfig(
  channelName: 'Tracker GPS',
  notificationBody: 'Трекинг активен',
  notificationIcon: 'ic_launcher',
  enableNotificationLocationUpdates: false,
  enableCancelTrackingAction: false,
  trackingInterval: Duration(seconds: 5),
  // Do not suppress time-based samples while the device moves less than 5 m.
  // Android may still adjust the cadence for power/OS reasons, but this keeps
  // our request consistent with the required five-second collection interval.
  distanceFilterMeters: 0,
);

const trackerLocationConfig = BackgroundLocationTrackerConfig(
  loggingEnabled: true,
  androidConfig: trackerAndroidConfig,
  iOSConfig: IOSConfig(
    activityType: ActivityType.NAVIGATION,
    distanceFilterMeters: 0,
    restartAfterKill: true,
  ),
);
