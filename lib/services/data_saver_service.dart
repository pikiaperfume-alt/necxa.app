import 'package:shared_preferences/shared_preferences.dart';

class DataSaverService {
  static final DataSaverService _instance = DataSaverService._internal();
  factory DataSaverService() => _instance;
  DataSaverService._internal();

  bool _isEnabled = false;
  bool get isEnabled => _isEnabled;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _isEnabled = prefs.getBool('dataSaverEnabled') ?? false;
  }

  Future<void> setEnabled(bool value) async {
    _isEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dataSaverEnabled', value);
  }

  // Optimized Settings for Data Saving
  int get imageQuality => _isEnabled ? 50 : 85;
  bool get preloadVideos => !_isEnabled;
  bool get autoPlayVideos => !_isEnabled;
  
  // Cache retention policy: Loaded content stays for 48 hours by default
  // but we can make it longer if user wants "not instant deletion"
  Duration get cacheRetention => const Duration(hours: 72); 
}
