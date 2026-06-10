import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import '../app_state.dart';

class AudioService {
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;
  AudioService._internal();

  /// Plays a system notification sound
  Future<void> playNotification() async {
    await FlutterRingtonePlayer().playNotification();
  }

  /// Plays a system ringtone (e.g. for calls or long alerts)
  Future<void> playRingtone() async {
    await FlutterRingtonePlayer().playRingtone();
  }

  /// Plays a system alarm sound
  Future<void> playAlarm() async {
    await FlutterRingtonePlayer().playAlarm();
  }

  /// Plays a generic system "click" or UI sound
  Future<void> playUiSound() async {
    await FlutterRingtonePlayer().play(
      android: AndroidSounds.notification,
      ios: IosSounds.glass,
      looping: false,
      volume: 0.5,
      asAlarm: false,
    );
  }

  /// Stops any playing sound
  Future<void> stop() async {
    await FlutterRingtonePlayer().stop();
  }

  // ── APP INTEGRATION ──────────────────────────────────────────

  /// Plays sound for incoming chat message based on user settings
  Future<void> playIncomingMessage(AppState state) async {
    if (!state.soundEnabled) return;
    
    await playNotification();
  }

  /// Plays sound for sent message (subtle click)
  Future<void> playSentMessage(AppState state) async {
    if (!state.soundEnabled) return;
    
    await FlutterRingtonePlayer().play(
      android: AndroidSounds.notification,
      ios: IosSounds.sentMessage,
      volume: 0.3,
    );
  }
}
