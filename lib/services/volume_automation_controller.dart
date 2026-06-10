import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:math';

enum VolumeAutomationType {
  linear,      // Linear increase
  logarithmic, // Fast start, slow end
  exponential, // Slow start, fast end
  sine,        // Smooth S-curve
  step,        // Step increments
}

class VolumeAutomationController {
  final AudioPlayer _player;
  Timer? _automationTimer;
  
  double _currentVolume = 0.0;
  VolumeAutomationType _type = VolumeAutomationType.logarithmic;
  
  VolumeAutomationController(this._player);
  
  /// Start gradual volume automation
  Future<void> startAutomation({
    required double targetVolume,
    Duration duration = const Duration(seconds: 2),
    VolumeAutomationType type = VolumeAutomationType.logarithmic,
    VoidCallback? onComplete,
  }) async {
    targetVolume = targetVolume.clamp(0.0, 1.0);
    _type = type;
    
    _automationTimer?.cancel();
    
    final startVolume = _currentVolume;
    final totalSteps = duration.inMilliseconds ~/ 16; // ~60fps
    
    for (int step = 0; step <= totalSteps; step++) {
      final progress = step / totalSteps;
      double easedProgress;
      
      switch (_type) {
        case VolumeAutomationType.linear:
          easedProgress = progress;
          break;
        case VolumeAutomationType.logarithmic:
          // Fast start, slow end
          easedProgress = 1 - (1 - progress) * (1 - progress);
          break;
        case VolumeAutomationType.exponential:
          // Slow start, fast end
          easedProgress = progress * progress;
          break;
        case VolumeAutomationType.sine:
          // Smooth S-curve
          easedProgress = (1 - cos(progress * 3.14159)) / 2;
          break;
        case VolumeAutomationType.step:
          // Step increments every 10%
          easedProgress = (progress * 10).floor() / 10;
          break;
      }
      
      _currentVolume = startVolume + (targetVolume - startVolume) * easedProgress;
      await _player.setVolume(_currentVolume);
      
      if (step < totalSteps) {
        await Future.delayed(const Duration(milliseconds: 16));
      }
    }
    
    onComplete?.call();
  }
  
  /// Create a wave pattern (volume goes up and down)
  Future<void> startWavePattern({
    double minVolume = 0.2,
    double maxVolume = 0.9,
    Duration waveDuration = const Duration(seconds: 3),
    int cycles = 2,
  }) async {
    _automationTimer?.cancel();
    
    final halfWave = Duration(milliseconds: waveDuration.inMilliseconds ~/ 2);
    
    for (int i = 0; i < cycles; i++) {
      // Fade up
      await startAutomation(
        targetVolume: maxVolume,
        duration: halfWave,
        type: VolumeAutomationType.sine,
      );
      
      // Fade down
      await startAutomation(
        targetVolume: minVolume,
        duration: halfWave,
        type: VolumeAutomationType.sine,
      );
    }
    
    // Return to normal
    await startAutomation(
      targetVolume: 0.7,
      duration: const Duration(milliseconds: 800),
      type: VolumeAutomationType.linear,
    );
  }
  
  /// Pulse effect (quick spike then return)
  Future<void> pulse({
    double peakVolume = 1.0,
    Duration riseDuration = const Duration(milliseconds: 150),
    Duration fallDuration = const Duration(milliseconds: 300),
  }) async {
    final originalVolume = _currentVolume;
    
    // Quick rise
    await startAutomation(
      targetVolume: peakVolume,
      duration: riseDuration,
      type: VolumeAutomationType.exponential,
    );
    
    // Fall back
    await startAutomation(
      targetVolume: originalVolume,
      duration: fallDuration,
      type: VolumeAutomationType.logarithmic,
    );
  }
  
  void dispose() {
    _automationTimer?.cancel();
  }
}
