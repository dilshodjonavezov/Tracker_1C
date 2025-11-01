import 'package:background_location_tracker/background_location_tracker.dart';
import 'package:background_location_tracker_example/services/repo.dart';

@pragma('vm:entry-point')
void backgroundCallback() {
  print('BackgroundCallback: Starting background update handler at ${DateTime.now()}');
  try {
    BackgroundLocationTrackerManager.handleBackgroundUpdated(
      (data) async {
        print('BackgroundCallback: Received location data: $data');
        await Repo().update(data);
      },
    );
    print('BackgroundCallback: Handler registered successfully');
  } catch (e) {
    print('BackgroundCallback: Error in handler: $e');
  }
}