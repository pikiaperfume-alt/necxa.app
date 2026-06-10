import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

class VolumeAutomationWidget extends StatefulWidget {
  final Widget child;
  final String? autoPlaySound;
  final double targetVolume;
  final Duration fadeDuration;
  final Curve curve;
  final bool loop;
  final VoidCallback? onSoundComplete;
  
  const VolumeAutomationWidget({
    super.key,
    required this.child,
    this.autoPlaySound,
    this.targetVolume = 0.8,
    this.fadeDuration = const Duration(milliseconds: 1500),
    this.curve = Curves.easeOutCubic,
    this.loop = false,
    this.onSoundComplete,
  });

  @override
  State<VolumeAutomationWidget> createState() => _VolumeAutomationWidgetState();
}

class _VolumeAutomationWidgetState extends State<VolumeAutomationWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _volumeController;
  late Animation<double> _volumeAnimation;
  final AudioPlayer _player = AudioPlayer();
  
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    
    // Set up volume animation controller
    _volumeController = AnimationController(
      vsync: this,
      duration: widget.fadeDuration,
    );
    
    _volumeAnimation = CurvedAnimation(
      parent: _volumeController,
      curve: widget.curve,
    );
    
    _volumeAnimation.addListener(() {
      final newVolume = _volumeAnimation.value * widget.targetVolume;
      _player.setVolume(newVolume);
    });
    
    _volumeAnimation.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onSoundComplete?.call();
      }
    });
    
    // Auto-play if sound provided
    if (widget.autoPlaySound != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startAutoPlay();
      });
    }
  }
  
  Future<void> _startAutoPlay() async {
    if (_isPlaying) return;
    
    setState(() => _isPlaying = true);
    
    // Start with zero volume
    await _player.setVolume(0);
    
    // Play the sound
    await _player.play(AssetSource(widget.autoPlaySound!));
    
    if (widget.loop) {
      await _player.setReleaseMode(ReleaseMode.loop);
    }
    
    // Start volume automation (fade in)
    _volumeController.forward(from: 0);
  }
  
  Future<void> fadeOut() async {
    await _volumeController.reverse();
    await _player.stop();
    setState(() => _isPlaying = false);
  }
  
  Future<void> setVolume(double target, {Duration? duration}) async {
    if (duration != null) {
      _volumeController.duration = duration;
      _volumeController.animateTo(target / widget.targetVolume);
      _volumeController.duration = widget.fadeDuration; // reset
    } else {
      _player.setVolume(target);
    }
  }
  
  @override
  void dispose() {
    _volumeController.dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
