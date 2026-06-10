// ignore_for_file: constant_identifier_names
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'dart:async';

class SoundService {
  static final SoundService _instance = SoundService._internal();
  factory SoundService() => _instance;
  SoundService._internal();

  final AudioPlayer _audioPlayer = AudioPlayer();
  final Map<String, AudioPlayer> _cachedPlayers = {};
  
  bool _isMuted = false;
  double _masterVolume = 0.8; // 80% default
  
  // Current fade animation
  Timer? _fadeTimer;
  double _currentFadeVolume = 0.0;
  
  // Available sounds
  static const String SOUND_GIFT_RECEIVED = 'gift_received.mp3';
  static const String SOUND_LIKE = 'like.mp3';
  static const String SOUND_COMMENT = 'comment.mp3';
  static const String SOUND_NOTIFICATION = 'notification.mp3';
  static const String SOUND_SUCCESS = 'success.mp3';
  static const String SOUND_LEVEL_UP = 'level_up.mp3';
  static const String SOUND_COIN_SYNTHESIS = 'coin_synthesis.mp3';
  
  // Ambient sounds
  static const String AMBIENT_LOUNGE = 'ambient_lounge.mp3';
  static const String AMBIENT_CHILL = 'ambient_chill.mp3';
  static const String AMBIENT_ENERGY = 'ambient_energy.mp3';
  
  void setMuted(bool muted) {
    _isMuted = muted;
    if (_isMuted) {
      _audioPlayer.setVolume(0);
    } else {
      _audioPlayer.setVolume(_masterVolume);
    }
  }
  
  void setMasterVolume(double volume) {
    _masterVolume = volume.clamp(0.0, 1.0);
    if (!_isMuted) {
      _audioPlayer.setVolume(_masterVolume);
    }
  }
  
  /// Play sound with GRADUAL VOLUME AUTOMATION (fade in)
  Future<void> playWithFade({
    required String soundPath,
    double targetVolume = 0.8,
    Duration fadeDuration = const Duration(milliseconds: 1500),
    Curve curve = Curves.easeOutCubic,
    bool loop = false,
  }) async {
    if (_isMuted) return;
    
    // Stop any existing fade
    _fadeTimer?.cancel();
    
    // Create or get cached player
    AudioPlayer player = _cachedPlayers[soundPath] ?? AudioPlayer();
    if (!_cachedPlayers.containsKey(soundPath)) {
      _cachedPlayers[soundPath] = player;
    }
    
    // Set up loop if needed
    if (loop) {
      await player.setReleaseMode(ReleaseMode.loop);
    }
    
    // Start with volume 0
    await player.setVolume(0);
    
    // Play the sound
    await player.play(AssetSource(soundPath));
    
    // Fade in gradually
    final startTime = DateTime.now();
    final endVolume = targetVolume.clamp(0.0, 1.0);
    
    _fadeTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      final elapsed = DateTime.now().difference(startTime);
      final progress = (elapsed.inMilliseconds / fadeDuration.inMilliseconds).clamp(0.0, 1.0);
      final easedProgress = curve.transform(progress);
      final currentVolume = easedProgress * endVolume;
      
      player.setVolume(currentVolume);
      _currentFadeVolume = currentVolume;
      
      if (progress >= 1.0) {
        timer.cancel();
      }
    });
  }
  
  /// Play with fade OUT then IN (for transitions)
  Future<void> playWithFadeInOut({
    required String soundPath,
    double targetVolume = 0.8,
    Duration fadeInDuration = const Duration(milliseconds: 1000),
    Duration fadeOutDuration = const Duration(milliseconds: 800),
    Duration holdDuration = const Duration(milliseconds: 2000),
  }) async {
    if (_isMuted) return;
    
    AudioPlayer player = _cachedPlayers[soundPath] ?? AudioPlayer();
    if (!_cachedPlayers.containsKey(soundPath)) {
      _cachedPlayers[soundPath] = player;
    }
    
    // Fade IN
    await playWithFade(
      soundPath: soundPath,
      targetVolume: targetVolume,
      fadeDuration: fadeInDuration,
    );
    
    // Hold at target volume
    await Future.delayed(holdDuration);
    
    // Fade OUT
    await fadeOut(soundPath: soundPath, fadeDuration: fadeOutDuration);
  }
  
  /// Gradual volume decrease (fade out)
  Future<void> fadeOut({
    required String soundPath,
    Duration fadeDuration = const Duration(milliseconds: 1000),
    Curve curve = Curves.easeInCubic,
  }) async {
    final player = _cachedPlayers[soundPath];
    if (player == null) return;
    
    final startVolume = _currentFadeVolume;
    final startTime = DateTime.now();
    
    Timer.periodic(const Duration(milliseconds: 16), (timer) {
      final elapsed = DateTime.now().difference(startTime);
      final progress = (elapsed.inMilliseconds / fadeDuration.inMilliseconds).clamp(0.0, 1.0);
      final easedProgress = curve.transform(progress);
      final currentVolume = startVolume * (1 - easedProgress);
      
      player.setVolume(currentVolume);
      
      if (progress >= 1.0) {
        timer.cancel();
        player.stop();
      }
    });
  }
  
  /// Play gift sound with celebration effect
  Future<void> playGiftSound() async {
    await playWithFade(
      soundPath: SOUND_GIFT_RECEIVED,
      targetVolume: 0.7,
      fadeDuration: const Duration(milliseconds: 800),
      curve: Curves.elasticOut,
    );
  }
  
  /// Play like sound (short, quick fade)
  Future<void> playLikeSound() async {
    await playWithFade(
      soundPath: SOUND_LIKE,
      targetVolume: 0.5,
      fadeDuration: const Duration(milliseconds: 200),
      curve: Curves.easeOutQuad,
    );
  }
  
  /// Play coin synthesis sound (dramatic fade in)
  Future<void> playCoinSynthesisSound() async {
    await playWithFade(
      soundPath: SOUND_COIN_SYNTHESIS,
      targetVolume: 0.9,
      fadeDuration: const Duration(milliseconds: 1200),
      curve: Curves.easeOutBack,
    );
  }
  
  /// Play ambient background sound (continuous with fade)
  Future<void> startAmbientSound(String ambientType) async {
    await playWithFade(
      soundPath: ambientType,
      targetVolume: 0.3, // Low background volume
      fadeDuration: const Duration(seconds: 3),
      loop: true,
    );
  }
  
  /// Stop ambient sound with fade out
  Future<void> stopAmbientSound() async {
    await fadeOut(soundPath: AMBIENT_LOUNGE, fadeDuration: const Duration(seconds: 2));
  }
  
  /// Play sound on notification with priority (interrupts current)
  Future<void> playNotificationSound() async {
    // Fade out current sound quickly
    await fadeOut(soundPath: SOUND_NOTIFICATION, fadeDuration: const Duration(milliseconds: 300));
    
    // Play notification with fast fade in
    await playWithFade(
      soundPath: SOUND_NOTIFICATION,
      targetVolume: 0.85,
      fadeDuration: const Duration(milliseconds: 400),
    );
  }
  
  void dispose() {
    _fadeTimer?.cancel();
    for (var player in _cachedPlayers.values) {
      player.dispose();
    }
    _cachedPlayers.clear();
    _audioPlayer.dispose();
  }
}
