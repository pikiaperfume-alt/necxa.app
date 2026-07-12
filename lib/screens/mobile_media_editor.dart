import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../theme.dart';
import '../app_state.dart';
import '../widgets/media_editor_tools.dart';
import '../widgets/mobile_editor_panels.dart';
import '../services/video_enhancement_service.dart';
import 'pro_media_editor_screen.dart';

// ══════════════════════════════════════════════════════════════
// MOBILE MEDIA EDITOR - Responsive adaptation of desktop editor
// ══════════════════════════════════════════════════════════════

class MobileMediaEditor extends StatefulWidget {
  final AppState state;
  final File? initialMedia;
  
  const MobileMediaEditor({
    super.key,
    required this.state,
    this.initialMedia,
  });

  @override
  State<MobileMediaEditor> createState() => _MobileMediaEditorState();
}

class _MobileMediaEditorState extends State<MobileMediaEditor>
    with TickerProviderStateMixin {
  
  // ── Selection & State ────────────────────────────────────────
  String? _selectedTrackId;
  int? _selectedTrackIndex;
  EditorObject? _selectedObject;
  
  // ── Timeline ─────────────────────────────────────────────────
  final List<EditorTrack> _tracks = [];
  double _playheadPosition = 0.0;
  double _timelineZoom = 1.0;
  bool _isPlaying = false;
  Duration _currentTime = Duration.zero;
  Duration _totalDuration = Duration(seconds: 30);
  
  // ── Canvas State ─────────────────────────────────────────────
  double _canvasScale = 1.0;
  double _gestureScale = 1.0;
  double _canvasRotation = 0.0;
  double _gestureRotation = 0.0;
  Offset _canvasOffset = Offset.zero;
  
  // ── Media Playback ─────────────────────────────────────────
  VideoPlayerController? _videoController;
  bool _isVideoReady = false;
  final VideoEnhancementService _videoService = VideoEnhancementService();
  bool _isProcessing = false;
  double _globalSpeed = 1.0;
  double _globalOpacity = 1.0;
  double _audioVolume = 1.0;
  double _audioBass = 0.5;
  double _audioTreble = 0.5;
  bool _audioFadeIn = false;
  bool _audioFadeOut = false;
  double _audioSpeed = 1.0;
  String? _selectedEffect;
  double _brightness = 0.0;
  double _contrast = 1.0;
  double _saturation = 1.0;
  double _hue = 0.0;
  double _vignette = 0.0;
  double _blur = 0.0;
  double _grain = 0.0;
  String? _selectedTransition;
  String _activeFilter = 'None';
  File? _combinedFile;
  
  // ── UI State ─────────────────────────────────────────────────
  int _activeToolPanel = 0; // 0: Timeline, 1: Media, 2: Audio, 3: Text, 4: Effects
  bool _showFullscreenPreview = false;
  String _selectedAspectRatio = '9:16';
  String _selectedResolution = '1080p';
  String _selectedFps = '30fps';
  
  // ── Controllers ──────────────────────────────────────────────
  late TabController _bottomNavController;
  
  @override
  void initState() {
    super.initState();
    _bottomNavController = TabController(length: 8, vsync: this);
    _initializeEditor();
  }
  
  void _initializeEditor() {
    final videoTrack = EditorTrack(id: 'video-1', name: 'Video', type: TrackType.video);
    videoTrack.clips.add(EditorObject(
      id: 'video-clip-1',
      name: 'Main Clip',
      type: 'video',
      startTime: Duration.zero,
      duration: const Duration(seconds: 12),
    ));

    final audioTrack = EditorTrack(id: 'audio-1', name: 'Audio', type: TrackType.audio);
    audioTrack.clips.add(EditorObject(
      id: 'audio-clip-1',
      name: 'Voiceover',
      type: 'audio',
      startTime: Duration.zero,
      duration: const Duration(seconds: 12),
    ));

    final textTrack = EditorTrack(id: 'text-1', name: 'Text', type: TrackType.text);
    textTrack.clips.add(EditorObject(
      id: 'text-clip-1',
      name: 'Caption',
      type: 'text',
      startTime: const Duration(seconds: 2),
      duration: const Duration(seconds: 4),
    ));

    final effectsTrack = EditorTrack(id: 'effects-1', name: 'Effects', type: TrackType.effects);
    effectsTrack.clips.add(EditorObject(
      id: 'effect-clip-1',
      name: 'Glow',
      type: 'effects',
      startTime: const Duration(seconds: 4),
      duration: const Duration(seconds: 3),
    ));

    _tracks.addAll([videoTrack, audioTrack, textTrack, effectsTrack]);

    if (widget.initialMedia != null && widget.initialMedia!.existsSync()) {
      _videoController = VideoPlayerController.file(widget.initialMedia!)
        ..initialize().then((_) {
          if (!mounted) return;
          setState(() {
            _isVideoReady = true;
            _totalDuration = _videoController!.value.duration;
          });
          _videoController!.setLooping(true);
          _videoController!.addListener(_syncVideoState);
          _videoController!.play();
        });
    }
  }
  
  @override
  void dispose() {
    _videoController?.removeListener(_syncVideoState);
    _videoController?.dispose();
    _bottomNavController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isPortrait = screenSize.height > screenSize.width;
    
    if (!isPortrait) {
      // Landscape: use desktop editor
      return ProMediaEditorScreen(state: widget.state);
    }
    
    return Scaffold(
      backgroundColor: C.bg,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildMobileHeader(screenSize),
                Expanded(
                  child: Column(
                    children: [
                      _buildPreviewCanvas(screenSize),
                      _buildPlaybackControls(screenSize),
                      Expanded(
                        child: _buildTimelineWorkspace(screenSize),
                      ),
                    ],
                  ),
                ),
                _buildContextToolbar(screenSize),
                _buildBottomNavigation(screenSize),
              ],
            ),
            if (_showFullscreenPreview) _buildFullscreenPreviewOverlay(),
          ],
        ),
      ),
    );
  }
  
  Widget _buildFullscreenPreviewOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.96),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => setState(() => _showFullscreenPreview = false),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Fullscreen Preview',
                        style: dm(sz: 11, c: Colors.white, w: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 9 / 16,
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white24),
                        color: Colors.black,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: _buildCanvasContent(),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_formatDuration(_currentTime), style: dm(sz: 12, c: Colors.white, w: FontWeight.w700)),
                        Text(_formatDuration(_totalDuration), style: dm(sz: 12, c: Colors.white70)),
                      ],
                    ),
                    Slider(
                      value: _totalDuration.inMilliseconds > 0
                          ? _currentTime.inMilliseconds / _totalDuration.inMilliseconds
                          : 0.0,
                      onChanged: (value) {
                        if (_videoController != null && _totalDuration.inMilliseconds > 0) {
                          final target = Duration(milliseconds: (value * _totalDuration.inMilliseconds).round());
                          _videoController!.seekTo(target);
                        }
                      },
                      activeColor: C.brand,
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildFullscreenControl(Icons.skip_previous, () => _previousFrame()),
                        const SizedBox(width: 12),
                        _buildFullscreenControl(
                          _isPlaying ? Icons.pause : Icons.play_arrow,
                          () => _togglePlayback(),
                          isLarge: true,
                        ),
                        const SizedBox(width: 12),
                        _buildFullscreenControl(Icons.skip_next, () => _nextFrame()),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFullscreenControl(IconData icon, VoidCallback onTap, {bool isLarge = false}) {
    return Container(
      width: isLarge ? 56 : 44,
      height: isLarge ? 56 : 44,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(isLarge ? 28 : 12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(isLarge ? 28 : 12),
          child: Icon(icon, color: Colors.white, size: isLarge ? 28 : 22),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // A. HEADER (8–10% of screen)
  // ═══════════════════════════════════════════════════════════
  Widget _buildMobileHeader(Size screenSize) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: C.card,
        border: Border(bottom: BorderSide(color: C.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildIconAction(Icons.arrow_back_ios_new, onTap: () {}),
              const SizedBox(width: 8),
              Text('NECXA', style: syne(sz: 14, w: FontWeight.w900, c: C.brand)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: C.brand.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('Pro', style: dm(sz: 10, w: FontWeight.w700, c: C.brand)),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: _export,
                style: ElevatedButton.styleFrom(
                  backgroundColor: C.brand,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.upload, size: 16, color: Colors.white),
                label: Text('Export', style: dm(sz: 11, c: Colors.white, w: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('New Project', style: syne(sz: 13, w: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _buildSettingsChip(_selectedAspectRatio, () => _showSelectionSheet('Aspect ratio', ['9:16', '16:9', '1:1', '4:5'], (value) => setState(() => _selectedAspectRatio = value))),
                        const SizedBox(width: 6),
                        _buildSettingsChip(_selectedResolution, () => _showSelectionSheet('Resolution', ['480p', '720p', '1080p', '4K'], (value) => setState(() => _selectedResolution = value))),
                        const SizedBox(width: 6),
                        _buildSettingsChip(_selectedFps, () => _showSelectionSheet('FPS', ['24fps', '30fps', '60fps'], (value) => setState(() => _selectedFps = value))),
                      ],
                    ),
                  ],
                ),
              ),
              _buildIconAction(Icons.undo, onTap: _undo),
              const SizedBox(width: 6),
              _buildIconAction(Icons.redo, onTap: _redo),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildSettingsChip(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: C.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: C.border),
        ),
        child: Text(label, style: dm(sz: 9, w: FontWeight.w600, c: C.text)),
      ),
    );
  }

  Widget _buildIconAction(IconData icon, {required VoidCallback onTap, double size = 20}) {
    return Material(
      color: C.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: size, color: C.text),
        ),
      ),
    );
  }
  
  // ═══════════════════════════════════════════════════════════
  // B. PREVIEW CANVAS (30–35% of screen)
  // ═══════════════════════════════════════════════════════════
  Widget _buildPreviewCanvas(Size screenSize) {
    final canvasHeight = screenSize.height * 0.32;
    final aspectRatio = 9 / 16;
    final maxCanvasWidth = canvasHeight * aspectRatio;
    
    return Container(
      height: canvasHeight,
      color: Colors.black,
      child: Stack(
        alignment: Alignment.center,
        children: [
          GestureDetector(
            onTap: () => setState(() {
              _selectedObject = EditorObject(
                id: 'preview-clip',
                name: 'Preview',
                type: 'video',
                startTime: _currentTime,
                duration: const Duration(seconds: 1),
              );
            }),
            onDoubleTap: () => setState(() {
              _canvasScale = _canvasScale == 1.0 ? 1.8 : 1.0;
              _canvasRotation = 0.0;
              _canvasOffset = Offset.zero;
            }),
            onScaleStart: (_) => setState(() {
              _gestureScale = _canvasScale;
              _gestureRotation = _canvasRotation;
            }),
            onScaleUpdate: (details) => setState(() {
              _canvasScale = (_gestureScale * details.scale).clamp(0.85, 3.0);
              _canvasRotation = _gestureRotation + details.rotation;
            }),
            onPanUpdate: (details) {
              if (_canvasScale > 1.0) {
                setState(() {
                  _canvasOffset += details.delta;
                });
              }
            },
            child: Transform.translate(
              offset: _canvasOffset,
              child: Transform.rotate(
                angle: _canvasRotation,
                child: Transform.scale(
                  scale: _canvasScale,
                  child: Container(
                    width: maxCanvasWidth,
                    height: canvasHeight,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      border: Border.all(color: C.dim.withAlpha(51)),
                    ),
                    child: _buildCanvasContent(),
                  ),
                ),
              ),
            ),
          ),
          
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: C.brand.withAlpha(26),
                    width: 2,
                  ),
                ),
              ),
            ),
          ),
          
          if (_canvasScale > 1.0)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(204),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: C.brand.withAlpha(77)),
                ),
                child: Text(
                  '${(_canvasScale * 100).toStringAsFixed(0)}%',
                  style: dm(sz: 10, c: Colors.white, w: FontWeight.w600),
                ),
              ),
            ),
        ],
      ),
    );
  }
  
  Widget _buildCanvasContent() {
    if (_isVideoReady && _videoController != null) {
      return Stack(
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: _videoController!.value.aspectRatio,
              child: VideoPlayer(_videoController!),
            ),
          ),
          Positioned(
            bottom: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.64),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _isPlaying ? 'Playing' : 'Paused',
                style: dm(sz: 10, c: Colors.white, w: FontWeight.w600),
              ),
            ),
          ),
        ],
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.video_camera_back, size: 42, color: C.dim.withAlpha(128)),
          const SizedBox(height: 10),
          Text(
            'Tap to select media',
            style: dm(sz: 13, c: C.dim.withAlpha(128)),
          ),
        ],
      ),
    );
  }
  
  // ═══════════════════════════════════════════════════════════
  // C. PLAYBACK CONTROLS
  // ═══════════════════════════════════════════════════════════
  Widget _buildPlaybackControls(Size screenSize) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: C.card,
        border: Border(bottom: BorderSide(color: C.border)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatDuration(_currentTime), style: dm(sz: 11, c: C.sub)),
              Text(_formatDuration(_totalDuration), style: dm(sz: 11, c: C.sub)),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: 6,
            decoration: BoxDecoration(
              color: C.surface,
              borderRadius: BorderRadius.circular(6),
            ),
            child: FractionallySizedBox(
              widthFactor: _totalDuration.inMilliseconds > 0 ? (_currentTime.inMilliseconds / _totalDuration.inMilliseconds).clamp(0.0, 1.0) : 0.0,
              child: Container(
                decoration: BoxDecoration(
                  color: C.brand,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildPlaybackButton(Icons.skip_previous, () => _previousFrame()),
              const SizedBox(width: 12),
              _buildPlaybackButton(_isPlaying ? Icons.pause : Icons.play_arrow, () => _togglePlayback(), isLarge: true),
              const SizedBox(width: 12),
              _buildPlaybackButton(Icons.skip_next, () => _nextFrame()),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildPlaybackButton(IconData icon, VoidCallback onTap, {bool isLarge = false}) {
    return Container(
      width: isLarge ? 48 : 40,
      height: isLarge ? 48 : 40,
      decoration: BoxDecoration(
        color: isLarge ? C.brand : C.surface,
        borderRadius: BorderRadius.circular(isLarge ? 24 : 8),
        border: Border.all(color: C.border),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(isLarge ? 24 : 8),
          child: Icon(
            icon,
            size: isLarge ? 24 : 20,
            color: isLarge ? Colors.white : C.brand,
          ),
        ),
      ),
    );
  }
  
  // ═══════════════════════════════════════════════════════════
  // D. TIMELINE WORKSPACE (30%)
  // ═══════════════════════════════════════════════════════════
  Widget _buildTimelineWorkspace(Size screenSize) {
    return Container(
      color: C.bg,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Timeline', style: syne(sz: 13, w: FontWeight.w800, c: C.text)),
                    const SizedBox(height: 4),
                    Text('Drag clips, trim, and layer media', style: dm(sz: 10, c: C.sub)),
                  ],
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: C.brand.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text('${_tracks.length} Tracks', style: dm(sz: 9, c: C.brand, w: FontWeight.w700)),
                ),
              ],
            ),
          ),
          _buildTimelineRuler(screenSize),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 8),
              itemCount: _tracks.length,
              itemBuilder: (context, index) {
                return _buildTrackRow(_tracks[index], index, screenSize);
              },
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildTimelineRuler(Size screenSize) {
    const rulerHeight = 28.0;
    final timelineWidth = (screenSize.width - 96).clamp(0.0, double.infinity);
    final playheadOffset = _totalDuration.inMilliseconds > 0
        ? ((screenSize.width - 96) * (_currentTime.inMilliseconds / _totalDuration.inMilliseconds)).clamp(0.0, timelineWidth)
        : 0.0;
    
    return Container(
      height: rulerHeight,
      color: C.card,
      padding: const EdgeInsets.only(left: 48),
      child: GestureDetector(
        onTapDown: (details) {
          if (_totalDuration.inMilliseconds > 0) {
            final localX = details.localPosition.dx.clamp(0.0, timelineWidth);
            final targetMs = ((localX / timelineWidth) * _totalDuration.inMilliseconds).round();
            _videoController?.seekTo(Duration(milliseconds: targetMs));
          }
        },
        child: Stack(
          children: [
            Row(
              children: List.generate(
                (_totalDuration.inSeconds / 5).ceil(),
                (i) => Expanded(
                  child: Column(
                    children: [
                      Container(
                        width: 1,
                        height: 4,
                        color: C.dim.withAlpha(128),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            '${i * 5}s',
                            style: dm(sz: 7, c: C.dim),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: playheadOffset,
              top: 0,
              bottom: 0,
              child: Container(width: 2, color: C.brand),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildTrackRow(EditorTrack track, int index, Size screenSize) {
    final isSelected = _selectedTrackIndex == index;
    
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isSelected ? C.card2 : C.card,
        border: Border.all(
          color: isSelected ? C.brand : C.border,
          width: isSelected ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () => setState(() => _selectedTrackIndex = index),
                child: Container(
                  width: 56,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  decoration: BoxDecoration(
                    color: C.surface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(_getTrackIcon(track.type), style: const TextStyle(fontSize: 18)),
                      const SizedBox(height: 6),
                      Text(
                        track.name,
                        style: dm(sz: 8, c: C.dim),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(track.name.toUpperCase(), style: dm(sz: 10, w: FontWeight.w700, c: C.text)),
                    const SizedBox(height: 6),
                    Container(
                      height: 12,
                      decoration: BoxDecoration(
                        color: C.surface,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: FractionallySizedBox(
                        widthFactor: 0.78,
                        child: Container(
                          decoration: BoxDecoration(
                            color: C.brand.withOpacity(0.85),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                children: [
                  _buildTrackButton(Icons.visibility, () => _toggleTrackVisibility(index), size: 18),
                  const SizedBox(height: 6),
                  _buildTrackButton(Icons.lock, () => _toggleTrackLock(index), size: 18),
                ],
              ),
            ],
          ),
          if (track.clips.isNotEmpty) ...[
            const SizedBox(height: 14),
            SizedBox(
              height: 76,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: track.clips.length,
                itemBuilder: (context, clipIndex) {
                  final clip = track.clips[clipIndex];
                  final clipWidth = (clip.duration.inMilliseconds / 120).clamp(100.0, 260.0).toDouble();
                  final selected = clip == _selectedObject;

                  return GestureDetector(
                    onTap: () => setState(() {
                      _selectedObject = clip;
                      _selectedTrackId = track.id;
                    }),
                    child: Container(
                      width: clipWidth,
                      margin: const EdgeInsets.only(right: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: _trackGradientForType(track.type),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: selected ? C.brand : Colors.transparent,
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.18),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  clip.name,
                                  style: dm(sz: 11, c: Colors.white, w: FontWeight.w700),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(Icons.drag_handle, size: 16, color: Colors.white54),
                            ],
                          ),
                          Container(
                            height: 5,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: FractionallySizedBox(
                              widthFactor: 0.66,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.92),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _formatDuration(clip.duration),
                                style: dm(sz: 9, c: Colors.white70),
                              ),
                              Text(
                                track.type == TrackType.audio ? 'Audio' : track.type == TrackType.text ? 'Text' : 'Video',
                                style: dm(sz: 8, c: Colors.white70),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  LinearGradient _trackGradientForType(TrackType type) {
    switch (type) {
      case TrackType.video:
        return const LinearGradient(
          colors: [Color(0xFF2C3EF0), Color(0xFF5459FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case TrackType.audio:
        return const LinearGradient(
          colors: [Color(0xFF0EA5E9), Color(0xFF06B6D4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case TrackType.text:
        return const LinearGradient(
          colors: [Color(0xFFF59E0B), Color(0xFFFBBF24)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case TrackType.effects:
        return const LinearGradient(
          colors: [Color(0xFFEC4899), Color(0xFFDB2777)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      default:
        return const LinearGradient(
          colors: [Color(0xFF6B7280), Color(0xFF9CA3AF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
    }
  }

  Color _trackColorForType(TrackType type) {
    switch (type) {
      case TrackType.video:
        return const Color(0xFF4F46E5);
      case TrackType.audio:
        return const Color(0xFF0891B2);
      case TrackType.text:
        return const Color(0xFFF59E0B);
      case TrackType.effects:
        return const Color(0xFFEC4899);
      default:
        return C.dim.withOpacity(0.8);
    }
  }
  
  Widget _buildTrackButton(IconData icon, VoidCallback onTap, {double size = 20}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: size, color: C.dim),
        ),
      ),
    );
  }
  
  String _getTrackIcon(TrackType type) {
    switch (type) {
      case TrackType.video: return '🎬';
      case TrackType.audio: return '🎵';
      case TrackType.text: return '📝';
      case TrackType.effects: return '✨';
      case TrackType.stickers: return '⭐';
      case TrackType.voiceOver: return '🎙️';
      case TrackType.captions: return '📄';
      default: return '📌';
    }
  }
  
  // ═══════════════════════════════════════════════════════════
  // E. CONTEXT TOOLBAR
  // ═══════════════════════════════════════════════════════════
  Widget _buildContextToolbar(Size screenSize) {
    return Container(
      height: 86,
      decoration: BoxDecoration(
        color: C.card,
        border: Border(top: BorderSide(color: C.border)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: _buildContextualTools(),
    );
  }
  
  Widget _buildContextualTools() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: _selectedObject == null ? _buildToolsForSelection() : _buildToolsForObject(_selectedObject!),
      ),
    );
  }
  
  List<Widget> _buildToolsForSelection() {
    switch (_activeToolPanel) {
      case 1:
        return [
          _buildToolIconButton(Icons.photo, 'Media', () => _showToolPanel('Media')),
          _buildToolIconButton(Icons.crop, 'Crop', () => _showToolPanel('Media')),
          _buildToolIconButton(Icons.pause_circle, 'Split', () => _splitClip()),
          _buildToolIconButton(Icons.speed, 'Speed', () => _adjustSpeed()),
          _buildToolIconButton(Icons.volume_up, 'Volume', () => _adjustVolume()),
          _buildToolIconButton(Icons.filter_vintage, 'Filter', () => _applyFilter()),
          _buildToolIconButton(Icons.delete_outline, 'Delete', () => _deleteClip()),
        ];
      case 2:
        return [
          _buildToolIconButton(Icons.music_note, 'Audio', () => _showToolPanel('Audio')),
          _buildToolIconButton(Icons.volume_up, 'Volume', () => _adjustVolume()),
          _buildToolIconButton(Icons.graphic_eq, 'EQ', () => _showSnack('EQ presets')),
          _buildToolIconButton(Icons.waveform, 'Fade', () => _addFade()),
          _buildToolIconButton(Icons.noise_control_off, 'Noise', () => _showToolPanel('Audio')),
        ];
      case 3:
        return [
          _buildToolIconButton(Icons.font_download, 'Font', () => _changeFont()),
          _buildToolIconButton(Icons.format_size, 'Size', () => _changeFontSize()),
          _buildToolIconButton(Icons.color_lens, 'Color', () => _changeTextColor()),
          _buildToolIconButton(Icons.shadow, 'Shadow', () => _addShadow()),
          _buildToolIconButton(Icons.delete_outline, 'Delete', () => _deleteClip()),
        ];
      case 4:
        return [
          _buildToolIconButton(Icons.filter, 'Filter', () => _applyFilter()),
          _buildToolIconButton(Icons.blur_on, 'Blur', () => _showToolPanel('Effects')),
          _buildToolIconButton(Icons.auto_awesome, 'Glow', () => _showToolPanel('Effects')),
          _buildToolIconButton(Icons.layers, 'Overlay', () => _showToolPanel('Effects')),
        ];
      case 5:
        return [
          _buildToolIconButton(Icons.compare_arrows, 'Transition', () => _showToolPanel('Transitions')),
          _buildToolIconButton(Icons.play_circle, 'Preview', _showPreview),
          _buildToolIconButton(Icons.settings, 'Style', () => _showSnack('Transition style')),
        ];
      case 6:
        return [
          _buildToolIconButton(Icons.folder_open, 'Assets', _showMediaSheet),
          _buildToolIconButton(Icons.photo_library, 'Media', () => _showToolPanel('Media')),
          _buildToolIconButton(Icons.auto_awesome_motion, 'Effects', () => _showToolPanel('Effects')),
        ];
      case 7:
        return [
          _buildToolIconButton(Icons.settings, 'Settings', () => _showSnack('Editor settings')),
          _buildToolIconButton(Icons.info_outline, 'Help', () => _showSnack('Help & tips')),
          _buildToolIconButton(Icons.dark_mode, 'Theme', () => _showSnack('Theme toggled')),
        ];
      default:
        return [
          _buildToolIconButton(Icons.scissors, 'Split', () => _splitClip()),
          _buildToolIconButton(Icons.crop, 'Trim', () => _trimClip()),
          _buildToolIconButton(Icons.crop_square, 'Crop', () => _showToolPanel('Media')),
          _buildToolIconButton(Icons.speed, 'Speed', () => _adjustSpeed()),
          _buildToolIconButton(Icons.volume_up, 'Volume', () => _adjustVolume()),
          _buildToolIconButton(Icons.delete_outline, 'Delete', () => _deleteClip()),
        ];
    }
  }
  
  List<Widget> _buildToolsForObject(EditorObject obj) {
    final tools = <Widget>[];
    
    if (obj.type == 'video') {
      tools.addAll([
        _buildToolIconButton(Icons.scissors, 'Split', () => _splitClip()),
        _buildToolIconButton(Icons.crop, 'Trim', () => _trimClip()),
        _buildToolIconButton(Icons.crop_square, 'Crop', () => _cropClip()),
        _buildToolIconButton(Icons.speed, 'Speed', () => _adjustSpeed()),
        _buildToolIconButton(Icons.opacity, 'Opacity', () => _adjustOpacity()),
        _buildToolIconButton(Icons.transform, 'Transform', () => _applyTransform()),
        _buildToolIconButton(Icons.auto_awesome, 'Animation', () => _applyAnimation()),
        _buildToolIconButton(Icons.filter_alt, 'Filter', () => _applyFilter()),
        _buildToolIconButton(Icons.tune, 'Adjust', () => _showSnack('Adjust settings')),
        _buildToolIconButton(Icons.delete_outline, 'Delete', () => _deleteClip()),
      ]);
    } else if (obj.type == 'text') {
      tools.addAll([
        _buildToolIconButton(Icons.font_download, 'Font', () => _changeFont()),
        _buildToolIconButton(Icons.format_size, 'Size', () => _changeFontSize()),
        _buildToolIconButton(Icons.color_lens, 'Color', () => _changeTextColor()),
        _buildToolIconButton(Icons.shadow, 'Shadow', () => _addShadow()),
        _buildToolIconButton(Icons.stacked_line_chart, 'Stroke', () => _applyStroke()),
        _buildToolIconButton(Icons.auto_awesome, 'Animation', () => _applyAnimation()),
        _buildToolIconButton(Icons.format_align_center, 'Alignment', () => _adjustTextAlignment()),
        _buildToolIconButton(Icons.timeline, 'Duration', () => _adjustDuration()),
        _buildToolIconButton(Icons.delete_outline, 'Delete', () => _deleteClip()),
      ]);
    } else if (obj.type == 'audio') {
      tools.addAll([
        _buildToolIconButton(Icons.volume_up, 'Volume', () => _adjustVolume()),
        _buildToolIconButton(Icons.waveform, 'Fade', () => _addFade()),
        _buildToolIconButton(Icons.noise_control_off, 'Noise', () => _noiseRemoval()),
        _buildToolIconButton(Icons.graphic_eq, 'EQ', () => _showSnack('EQ presets')),
        _buildToolIconButton(Icons.speed, 'Speed', () => _adjustSpeed()),
        _buildToolIconButton(Icons.link_off, 'Detach', () => _detachAudio()),
        _buildToolIconButton(Icons.delete_outline, 'Delete', () => _deleteClip()),
      ]);
    }

    return tools;
  }

  Widget _buildToolIconButton(IconData icon, String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: C.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(icon, size: 22, color: C.text),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(label, style: dm(sz: 9, c: C.sub), textAlign: TextAlign.center),
        ],
      ),
    );
  }
  
  // ═══════════════════════════════════════════════════════════
  // F. BOTTOM NAVIGATION
  // ═══════════════════════════════════════════════════════════
  Widget _buildBottomNavigation(Size screenSize) {
    final navItems = [
      (Icons.timeline, 'Timeline'),
      (Icons.photo_library, 'Media'),
      (Icons.music_note, 'Audio'),
      (Icons.text_fields, 'Text'),
      (Icons.auto_awesome, 'Effects'),
      (Icons.compare_arrows, 'Transitions'),
      (Icons.grid_view, 'Assets'),
      (Icons.settings, 'Settings'),
    ];
    
    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: C.card,
        border: Border(top: BorderSide(color: C.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(
          navItems.length,
          (index) => GestureDetector(
            onTap: () => setState(() {
              _activeToolPanel = index;
              _bottomNavController.index = index;
            }),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(navItems[index].$1, size: 22, color: index == _activeToolPanel ? C.brand : C.dim),
                const SizedBox(height: 4),
                Text(navItems[index].$2, style: dm(sz: 9, c: index == _activeToolPanel ? C.brand : C.dim)),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  // ═══════════════════════════════════════════════════════════
  // FLOATING ACTION BUTTONS
  // ═══════════════════════════════════════════════════════════
  Widget _buildPreviewBadge(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: C.card.withOpacity(0.9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: C.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: C.brand),
            const SizedBox(width: 6),
            Text(label, style: dm(sz: 10, c: C.text, w: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
  
  // ═══════════════════════════════════════════════════════════
  // ACTION HANDLERS
  // ═══════════════════════════════════════════════════════════
  
  void _showAspectRatioMenu() {
    _showSelectionSheet('Aspect ratio', ['9:16', '16:9', '1:1', '4:5'], (value) => setState(() => _selectedAspectRatio = value));
  }

  void _showSelectionSheet(String title, List<String> values, ValueChanged<String> onSelect) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: C.card,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: syne(sz: 14, w: FontWeight.w800, c: C.text)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: values.map((value) => GestureDetector(
                  onTap: () {
                    onSelect(value);
                    Navigator.pop(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: C.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: C.border),
                    ),
                    child: Text(value, style: dm(sz: 11, w: FontWeight.w600)),
                  ),
                )).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  void _undo() {
    _showSnack('Undo');
  }

  void _redo() {
    _showSnack('Redo');
  }

  Future<void> _export() async {
    if (widget.initialMedia == null) {
      _showSnack('No media available for export.');
      return;
    }

    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      final clips = _buildExportClips();
      if (clips.isEmpty) {
        _showSnack('No clips available for export.');
        return;
      }

      final combinedFile = await _videoService.combineSequence(
        clips: clips,
        aspectRatio: _selectedAspectRatio,
        overlays: _renderOverlays(),
        effects: RenderEffects(
          brightness: _brightness,
          contrast: _contrast,
          saturation: _saturation,
          hue: _hue,
          vignette: _vignette,
          blur: _blur,
          grain: _grain,
        ),
      );

      if (combinedFile == null) {
        _showSnack('Export failed.');
        return;
      }

      _combinedFile = combinedFile;
      _showSnack('Export complete');

      if (!mounted) return;
      Navigator.pop(context, {
        'sequence': [combinedFile],
        'combined_file': combinedFile,
        'track': null,
        'flatten': true,
        'aspect_ratio': _selectedAspectRatio,
        'music_vol': _audioVolume,
        'voice_vol': 1.0,
        'original_vol': 1.0,
        'voice_over': null,
        'overlays': _renderOverlays(),
      });
    } catch (e) {
      _showSnack('Export failed: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  List<ClipData> _buildExportClips() {
    if (widget.initialMedia == null) return [];

    final file = widget.initialMedia!;
    final durationSeconds = _totalDuration.inMilliseconds > 0 ? _totalDuration.inMilliseconds / 1000.0 : 3.0;
    return [
      ClipData(
        path: file.path,
        start: 0.0,
        end: durationSeconds,
        speed: _globalSpeed,
        volume: _audioVolume,
        isVideo: file.path.toLowerCase().endsWith('.mp4') || file.path.toLowerCase().endsWith('.mov'),
        hasAudio: file.path.toLowerCase().endsWith('.mp4') || file.path.toLowerCase().endsWith('.mov'),
        scale: _globalOpacity == 1.0 ? 1.0 : _globalOpacity,
        rotation: _canvasRotation,
        offsetX: _canvasOffset.dx,
        offsetY: _canvasOffset.dy,
        opacity: _globalOpacity,
      )
    ];
  }

  List<RenderOverlay> _renderOverlays() {
    return _tracks.expand((track) {
      return track.clips.where((clip) => clip.type == 'text' || clip.type == 'effects').map((clip) {
        return RenderOverlay(
          type: clip.type,
          text: clip.type == 'text' ? clip.name : clip.type == 'effects' ? clip.name : null,
          start: clip.startTime.inMilliseconds / 1000.0,
          end: (clip.startTime + clip.duration).inMilliseconds / 1000.0,
          x: 0.5,
          y: 0.35,
          scale: 1.0,
          rotation: 0.0,
          opacity: 1.0,
          fontSize: clip.type == 'text' ? 28.0 : 24.0,
          color: Colors.white,
          background: Colors.black,
          backgroundOpacity: clip.type == 'text' ? 0.4 : 0.0,
          shadow: true,
        );
      });
    }).toList();
  }

  Future<void> _saveDraft() async {
    if (widget.initialMedia == null) {
      _showSnack('Nothing to save yet.');
      return;
    }

    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final fileToSave = _combinedFile ?? widget.initialMedia!;
      await widget.state.drafts.saveDraft(mediaFile: fileToSave, trackId: _selectedTrackId, caption: '');
      _showSnack('Saved to Drafts');
    } catch (e) {
      _showSnack('Draft save failed: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showPreview() {
    setState(() => _showFullscreenPreview = true);
  }

  void _togglePlayback() {
    if (_videoController == null) {
      setState(() => _isPlaying = !_isPlaying);
      return;
    }

    if (_videoController!.value.isPlaying) {
      _videoController!.pause();
    } else {
      _videoController!.play();
    }

    setState(() {
      _isPlaying = _videoController?.value.isPlaying ?? !_isPlaying;
    });
  }

  void _previousFrame() {
    if (_videoController == null) return;
    final target = _videoController!.value.position - const Duration(milliseconds: 100);
    _videoController!.seekTo(target < Duration.zero ? Duration.zero : target);
  }

  void _nextFrame() {
    if (_videoController == null) return;
    final target = _videoController!.value.position + const Duration(milliseconds: 100);
    final maxDuration = _videoController!.value.duration;
    _videoController!.seekTo(target > maxDuration ? maxDuration : target);
  }
  void _toggleTrackVisibility(int index) {
    setState(() => _tracks[index].isVisible = !_tracks[index].isVisible);
    _showSnack('${_tracks[index].name} visibility ${_tracks[index].isVisible ? 'on' : 'off'}');
  }

  void _toggleTrackLock(int index) {
    setState(() => _tracks[index].isLocked = !_tracks[index].isLocked);
    _showSnack('${_tracks[index].name} ${_tracks[index].isLocked ? 'locked' : 'unlocked'}');
  }

  void _splitClip() {
    if (_selectedTrackIndex == null || _selectedObject == null) {
      _showSnack('Select a clip to split');
      return;
    }
    final track = _tracks[_selectedTrackIndex!];
    final clip = _selectedObject!;
    if (clip.duration.inMilliseconds < 200) {
      _showSnack('Clip too short to split');
      return;
    }
    final splitDuration = Duration(milliseconds: (clip.duration.inMilliseconds / 2).round());
    final first = EditorObject(
      id: '${clip.id}-a',
      name: '${clip.name} A',
      type: clip.type,
      startTime: clip.startTime,
      duration: splitDuration,
      speed: clip.speed,
      opacity: clip.opacity,
      filter: clip.filter,
    );
    final second = EditorObject(
      id: '${clip.id}-b',
      name: '${clip.name} B',
      type: clip.type,
      startTime: clip.startTime + splitDuration,
      duration: clip.duration - splitDuration,
      speed: clip.speed,
      opacity: clip.opacity,
      filter: clip.filter,
    );
    final clipIndex = track.clips.indexOf(clip);
    if (clipIndex < 0) return;
    setState(() {
      track.clips.removeAt(clipIndex);
      track.clips.insertAll(clipIndex, [first, second]);
      _selectedObject = second;
      _totalDuration = _calculateTimelineDuration();
    });
    _showSnack('Clip split');
  }

  void _trimClip() {
    if (_selectedObject == null || _videoController == null) {
      _showSnack('Select a clip and wait for the video to load');
      return;
    }
    final clip = _selectedObject!;
    final maxDuration = _videoController!.value.duration;
    showModalBottomSheet(
      context: context,
      backgroundColor: C.card,
      builder: (context) {
        return TrimTool(
          controller: _videoController!,
          trimOperation: TrimOperation(start: clip.startTime, end: clip.startTime + clip.duration, maxDuration: maxDuration),
          onTrimChanged: (start, end) {
            setState(() {
              clip.startTime = start;
              clip.duration = end - start;
              _totalDuration = _calculateTimelineDuration();
            });
          },
        );
      },
    );
  }

  void _adjustSpeed() {
    if (_selectedObject == null) {
      _showSnack('Select a clip to adjust speed');
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: C.card,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Speed', style: syne(sz: 14, w: FontWeight.w800, c: C.text)),
              const SizedBox(height: 12),
              Slider(
                value: _globalSpeed,
                min: 0.25,
                max: 3.0,
                divisions: 11,
                label: '${_globalSpeed.toStringAsFixed(2)}x',
                onChanged: (value) => setState(() => _globalSpeed = value),
              ),
              const SizedBox(height: 8),
              Text('${_globalSpeed.toStringAsFixed(2)}x', style: dm(sz: 11, c: C.sub)),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Done', style: dm(sz: 12, c: C.brand, w: FontWeight.w700)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _adjustOpacity() {
    if (_selectedObject == null) {
      _showSnack('Select a clip to adjust opacity');
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: C.card,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Opacity', style: syne(sz: 14, w: FontWeight.w800, c: C.text)),
              const SizedBox(height: 12),
              Slider(
                value: _globalOpacity,
                min: 0.1,
                max: 1.0,
                divisions: 9,
                label: '${(_globalOpacity * 100).round()}%',
                onChanged: (value) => setState(() => _globalOpacity = value),
              ),
              const SizedBox(height: 8),
              Text('${(_globalOpacity * 100).round()}%', style: dm(sz: 11, c: C.sub)),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Done', style: dm(sz: 12, c: C.brand, w: FontWeight.w700)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _applyFilter() {
    showModalBottomSheet(
      context: context,
      backgroundColor: C.card,
      builder: (context) {
        return FilterTool(
          activeFilter: _activeFilter,
          onFilterSelected: (value) {
            setState(() {
              _activeFilter = value;
            });
            Navigator.pop(context);
            _showSnack('$value filter selected');
          },
        );
      },
    );
  }

  void _deleteClip() {
    if (_selectedTrackIndex == null || _selectedObject == null) {
      _showSnack('Select a clip to delete');
      return;
    }
    final track = _tracks[_selectedTrackIndex!];
    setState(() {
      track.clips.remove(_selectedObject);
      _selectedObject = null;
      _totalDuration = _calculateTimelineDuration();
    });
    _showSnack('Clip deleted');
  }

  void _changeFont() {
    _showTextEditor('font');
  }

  void _changeFontSize() {
    _showTextEditor('size');
  }

  void _changeTextColor() {
    _showTextEditor('color');
  }

  void _addShadow() {
    _showTextEditor('shadow');
  }

  void _adjustVolume() {
    if (_selectedObject == null) {
      _showSnack('Select audio to adjust');
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: C.card,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Volume', style: syne(sz: 14, w: FontWeight.w800, c: C.text)),
              const SizedBox(height: 12),
              Slider(
                value: _audioVolume,
                min: 0.0,
                max: 1.0,
                divisions: 10,
                label: '${(_audioVolume * 100).round()}%',
                onChanged: (value) => setState(() => _audioVolume = value),
              ),
              const SizedBox(height: 8),
              Text('${(_audioVolume * 100).round()}%', style: dm(sz: 11, c: C.sub)),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Done', style: dm(sz: 12, c: C.brand, w: FontWeight.w700)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _addFade() {
    _showSnack('Fade curve available in desktop editor');
  }

  void _cropClip() {
    _showSnack('Crop tool opened');
  }

  void _applyTransform() {
    _showSnack('Transform controls opened');
  }

  void _applyAnimation() {
    _showSnack('Animation options opened');
  }

  void _adjustTextAlignment() {
    _showSnack('Text alignment options opened');
  }

  void _noiseRemoval() {
    _showSnack('Noise removal options opened');
  }

  void _detachAudio() {
    _showSnack('Audio detached from video');
  }

  void _applyStroke() {
    _showSnack('Stroke styling opened');
  }

  void _adjustDuration() {
    _showSnack('Duration adjustment opened');
  }

  void _showToolPanel(String toolName) {
    switch (toolName) {
      case 'Media':
        _showMediaSheet();
        break;
      case 'Audio':
        _showAudioPanel();
        break;
      case 'Text':
        if (_selectedObject != null && _selectedObject!.type == 'text') {
          _showTextEditor('font');
        } else {
          _showCaptionSheet();
        }
        break;
      case 'Effects':
        _showEffectsPanel();
        break;
      case 'Transitions':
        _showTransitionSheet();
        break;
      default:
        _showSnack('$toolName panel opened');
    }
  }

  void _showMediaSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: C.card,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Media tools', style: syne(sz: 14, w: FontWeight.w800, c: C.text)),
            const SizedBox(height: 16),
            _panelButton(Icons.video_library, 'Add video clip', _addMediaClip),
            _panelButton(Icons.audiotrack, 'Add audio clip', _addAudioClip),
            _panelButton(Icons.text_fields, 'Add caption', _showCaptionSheet),
            _panelButton(Icons.emoji_emotions_outlined, 'Add sticker', _showStickerSheet),
            _panelButton(Icons.crop, 'Frame picker', _showFrameOverlayPicker),
          ],
        ),
      ),
    );
  }

  void _showAudioPanel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AudioEditingPanel(
        onClose: () => Navigator.pop(context),
        onVolumeChanged: (value) => setState(() => _audioVolume = value),
        onSpeedChanged: (value) => setState(() => _audioSpeed = value),
        onBassChanged: (value) => setState(() => _audioBass = value),
        onTrebleChanged: (value) => setState(() => _audioTreble = value),
        onFadeInChanged: (value) => setState(() => _audioFadeIn = value),
        onFadeOutChanged: (value) => setState(() => _audioFadeOut = value),
      ),
    );
  }

  void _showEffectsPanel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EffectsPanel(
        onClose: () => Navigator.pop(context),
        onEffectSelected: (effect) {
          _applyEffect(effect);
          Navigator.pop(context);
        },
        activeEffect: _selectedEffect,
      ),
    );
  }

  void _showTransitionSheet() {
    final transitions = ['Fade', 'Slide', 'Zoom', 'Rotate', 'Wipe', 'Blur', 'Bounce', 'Flip'];
    showModalBottomSheet(
      context: context,
      backgroundColor: C.card,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Transitions', style: syne(sz: 14, w: FontWeight.w800, c: C.text)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: transitions.map((transition) {
                final selected = _selectedTransition == transition;
                return GestureDetector(
                  onTap: () {
                    setState(() => _selectedTransition = transition);
                    Navigator.pop(context);
                    _showSnack('$transition transition selected');
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: selected ? C.brand : C.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: selected ? C.brand : C.border),
                    ),
                    child: Text(transition, style: dm(sz: 11, c: selected ? Colors.black : C.text)),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  void _addMediaClip() {
    final track = _tracks.firstWhere((track) => track.type == TrackType.video, orElse: () {
      final newTrack = EditorTrack(id: 'video-${_tracks.length + 1}', name: 'Video', type: TrackType.video);
      _tracks.add(newTrack);
      return newTrack;
    });

    final newClip = EditorObject(
      id: 'video-clip-${DateTime.now().millisecondsSinceEpoch}',
      name: 'New Clip',
      type: 'video',
      startTime: Duration.zero,
      duration: const Duration(seconds: 4),
    );

    setState(() {
      track.clips.add(newClip);
      _selectedTrackId = track.id;
      _selectedTrackIndex = _tracks.indexOf(track);
      _selectedObject = newClip;
      _totalDuration = _calculateTimelineDuration();
    });

    Navigator.pop(context);
    _showSnack('Video clip added');
  }

  void _addAudioClip() {
    final track = _tracks.firstWhere((track) => track.type == TrackType.audio, orElse: () {
      final newTrack = EditorTrack(id: 'audio-${_tracks.length + 1}', name: 'Audio', type: TrackType.audio);
      _tracks.add(newTrack);
      return newTrack;
    });

    final newClip = EditorObject(
      id: 'audio-clip-${DateTime.now().millisecondsSinceEpoch}',
      name: 'Audio Clip',
      type: 'audio',
      startTime: Duration.zero,
      duration: const Duration(seconds: 4),
    );

    setState(() {
      track.clips.add(newClip);
      _selectedTrackId = track.id;
      _selectedTrackIndex = _tracks.indexOf(track);
      _selectedObject = newClip;
      _totalDuration = _calculateTimelineDuration();
    });

    Navigator.pop(context);
    _showSnack('Audio clip added');
  }

  void _showStickerSheet() {
    final stickers = ['WOW', 'SALE', 'LIVE', 'NEW', '💥', '🔥'];
    showModalBottomSheet(
      context: context,
      backgroundColor: C.card,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Stickers', style: syne(sz: 14, w: FontWeight.w800, c: C.text)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: stickers.map((sticker) {
                return GestureDetector(
                  onTap: () {
                    final track = _tracks.firstWhere((track) => track.type == TrackType.effects, orElse: () {
                      final newTrack = EditorTrack(id: 'effects-${_tracks.length + 1}', name: 'Effects', type: TrackType.effects);
                      _tracks.add(newTrack);
                      return newTrack;
                    });

                    final stickerClip = EditorObject(
                      id: 'sticker-${DateTime.now().millisecondsSinceEpoch}',
                      name: sticker,
                      type: 'effects',
                      startTime: const Duration(seconds: 0),
                      duration: const Duration(seconds: 3),
                    );

                    setState(() {
                      track.clips.add(stickerClip);
                      _selectedTrackIndex = _tracks.indexOf(track);
                      _selectedObject = stickerClip;
                      _totalDuration = _calculateTimelineDuration();
                    });

                    Navigator.pop(context);
                    _showSnack('Sticker added');
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: C.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: C.border),
                    ),
                    child: Text(sticker, style: syne(sz: 14, w: FontWeight.w700, c: C.text)),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  void _showFrameOverlayPicker() {
    final ratios = ['9:16', '1:1', '4:5', '16:9'];
    showModalBottomSheet(
      context: context,
      backgroundColor: C.card,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Frame presets', style: syne(sz: 14, w: FontWeight.w800, c: C.text)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: ratios.map((ratio) {
                final selected = _selectedAspectRatio == ratio;
                return GestureDetector(
                  onTap: () {
                    setState(() => _selectedAspectRatio = ratio);
                    Navigator.pop(context);
                    _showSnack('Aspect ratio set to $ratio');
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: selected ? C.brand : C.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: selected ? C.brand : C.border),
                    ),
                    child: Text(ratio, style: dm(sz: 11, c: selected ? Colors.black : C.text)),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  void _showCaptionSheet() {
    var captionText = '';
    showModalBottomSheet(
      context: context,
      backgroundColor: C.card,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 16, left: 16, right: 16, top: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add caption', style: syne(sz: 14, w: FontWeight.w800, c: C.text)),
            const SizedBox(height: 12),
            TextField(
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Type your caption',
                filled: true,
                fillColor: C.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              onChanged: (value) => captionText = value,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      if (captionText.trim().isEmpty) {
                        _showSnack('Enter caption text first');
                        return;
                      }
                      final track = _tracks.firstWhere((track) => track.type == TrackType.text, orElse: () {
                        final newTrack = EditorTrack(id: 'text-${_tracks.length + 1}', name: 'Text', type: TrackType.text);
                        _tracks.add(newTrack);
                        return newTrack;
                      });
                      final captionClip = EditorObject(
                        id: 'caption-${DateTime.now().millisecondsSinceEpoch}',
                        name: captionText.trim(),
                        type: 'text',
                        startTime: Duration.zero,
                        duration: const Duration(seconds: 4),
                      );
                      setState(() {
                        track.clips.add(captionClip);
                        _selectedTrackId = track.id;
                        _selectedTrackIndex = _tracks.indexOf(track);
                        _selectedObject = captionClip;
                        _totalDuration = _calculateTimelineDuration();
                      });
                      Navigator.pop(context);
                      _showSnack('Caption added');
                    },
                    child: Text('Add caption', style: syne(sz: 12, w: FontWeight.w700, c: Colors.black)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _panelButton(IconData icon, String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: C.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: C.border),
          ),
          child: Row(
            children: [
              Icon(icon, color: C.text, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: dm(sz: 12, c: C.text, w: FontWeight.w700))),
            ],
          ),
        ),
      ),
    );
  }

  Duration _calculateTimelineDuration() {
    return _tracks.fold(Duration.zero, (durationSum, track) {
      return durationSum + track.clips.fold(Duration.zero, (clipSum, clip) => clipSum + clip.duration);
    });
  }

  void _showTextEditor(String mode) {
    if (_selectedObject == null || _selectedObject!.type != 'text') {
      _showSnack('Select a text clip first');
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.card,
      builder: (context) {
        return TextEditingPanel(
          initialText: _selectedObject!.name,
          onTextChanged: (value) {
            setState(() {
              final updated = EditorObject(
                id: _selectedObject!.id,
                name: value,
                type: _selectedObject!.type,
                startTime: _selectedObject!.startTime,
                duration: _selectedObject!.duration,
                speed: _selectedObject!.speed,
                opacity: _selectedObject!.opacity,
                filter: _selectedObject!.filter,
              );
              _selectedObject = updated;
              if (_selectedTrackIndex != null) {
                final track = _tracks[_selectedTrackIndex!];
                final clipIndex = track.clips.indexWhere((clip) => clip.id == updated.id);
                if (clipIndex >= 0) track.clips[clipIndex] = updated;
              }
            });
          },
          onClose: () => Navigator.pop(context),
        );
      },
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _syncVideoState() {
    if (!mounted || _videoController == null) return;
    setState(() {
      _currentTime = _videoController!.value.position;
      _totalDuration = _videoController!.value.duration;
      _isPlaying = _videoController!.value.isPlaying;
      if (_totalDuration.inMilliseconds > 0) {
        _playheadPosition = (_currentTime.inMilliseconds / _totalDuration.inMilliseconds) * 200;
      }
    });
  }
  
  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

// ══════════════════════════════════════════════════════════════
// DATA MODELS
// ══════════════════════════════════════════════════════════════

enum TrackType {
  video,
  audio,
  text,
  effects,
  stickers,
  voiceOver,
  captions,
}

class EditorTrack {
  final String id;
  final String name;
  final TrackType type;
  final List<EditorObject> clips = [];
  bool isVisible = true;
  bool isLocked = false;
  
  EditorTrack({
    required this.id,
    required this.name,
    required this.type,
  });
}

class EditorObject {
  final String id;
  final String name;
  final String type; // 'video', 'audio', 'text', etc.
  final Duration startTime;
  final Duration duration;
  final double speed;
  final double opacity;
  final String filter;
  
  EditorObject({
    required this.id,
    required this.name,
    required this.type,
    required this.startTime,
    required this.duration,
    this.speed = 1.0,
    this.opacity = 1.0,
    this.filter = 'None',
  });
}

int min(int a, int b) => a < b ? a : b;
