import 'package:shared_preferences/shared_preferences.dart';
import 'package:background_location_tracker/background_location_tracker.dart';

class LocationDao {
  static const _locationsKey = 'background_updated_locations';
  static const _locationSeparator = '-/-/-/';
  static LocationDao? _instance;

  LocationDao._();

  factory LocationDao() => _instance ??= LocationDao._();

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}.${dateTime.month}.${dateTime.year} ${dateTime.hour}:${dateTime.minute}:${dateTime.second}';
  }

  Future<SharedPreferences> get prefs async =>
      await SharedPreferences.getInstance();

  Future<void> saveLocation(BackgroundLocationUpdateData data) async {
    final locations = await getLocations();
    final now = DateTime.now();
    final locationString =
        '${_formatDateTime(now)} - Широта: ${data.lat.toStringAsFixed(6)}, Долгота: ${data.lon.toStringAsFixed(6)}';
    locations.add(locationString);
    await (await prefs)
        .setString(_locationsKey, locations.join(_locationSeparator));
  }

  Future<List<String>> getLocations() async {
    final prefs = await this.prefs;
    final locationsString = prefs.getString(_locationsKey);
    return locationsString?.split(_locationSeparator) ?? [];
  }

  Future<void> clear() async {
    final prefs = await this.prefs;
    await prefs.remove(_locationsKey);
  }
}
