import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:async';
import '../theme.dart';

class NecxaCameraCaptureScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const NecxaCameraCaptureScreen({super.key, required this.cameras});

  @override
  State<NecxaCameraCaptureScreen> createState() => _NecxaCameraCaptureScreenState();
}

class _NecxaCameraCaptureScreenState extends State<NecxaCameraCaptureScreen> {
  CameraController? _controller;
  bool _isRecording = false;
  int _timerSeconds = 0;
  Timer? _timer;
  
  // Settings
  double _speed = 1.0;
  String _activeFilter = 'Normal';
  bool _isFrontCamera = false;
  
  // Multi-Segment State
  final List<File> _capturedClips = [];
  double _totalRecordedSeconds = 0;

  final List<String> _filters = ['Normal', 'Cinema', 'Neon', 'Noir', 'Vivid'];
  final List<double> _speeds = [0.5, 1.0, 2.0];

  @override
  void initState() {
    super.initState();
    _initCamera(widget.cameras.first);
  }

  Future<void> _initCamera(CameraDescription description) async {
    final prev = _controller;
    _controller = CameraController(
      description,
      ResolutionPreset.high,
      enableAudio: true,
    );

    try {
      await _controller!.initialize();
    } catch (e) {
      debugPrint('Camera Init Error: $e');
    }

    if (mounted) setState(() {});
    await prev?.dispose();
  }

  void _toggleCamera() {
    _isFrontCamera = !_isFrontCamera;
    final description = widget.cameras.firstWhere(
      (c) => c.lensDirection == (_isFrontCamera ? CameraLensDirection.front : CameraLensDirection.back),
      orElse: () => widget.cameras.first,
    );
    _initCamera(description);
  }

  void _startTimer() {
    _timerSeconds = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      if (mounted) {
        setState(() {
          _timerSeconds++; // This will be deciseconds now for smoother timeline
          _totalRecordedSeconds += 0.1;
        });
      }
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _startRecording() async {
    if (_controller == null || !_controller!.value.isInitialized || _isRecording) return;

    try {
      await _controller!.startVideoRecording();
      _startTimer();
      setState(() => _isRecording = true);
    } catch (e) {
      debugPrint('Start Rec Error: $e');
    }
  }

  Future<void> _stopRecording() async {
    if (_controller == null || !_isRecording) return;

    try {
      final XFile rawFile = await _controller!.stopVideoRecording();
      _stopTimer();
      setState(() => _isRecording = false);
      
      // 🛡️ SAFELY STORE CONTENT
      await Future.delayed(const Duration(milliseconds: 300));
      final directory = await getApplicationDocumentsDirectory();
      final String fileName = 'necxa_clip_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final File savedFile = File('${directory.path}/$fileName');
      
      try {
        await File(rawFile.path).copy(savedFile.path);
        final int size = await savedFile.length();
        if (size > 0) {
          setState(() => _capturedClips.add(savedFile));
          debugPrint('🎬 NecxaCapture: Segment added (${_capturedClips.length} total)');
        }
      } catch (e) {
        debugPrint('File Save Error: $e');
      }
    } catch (e) {
      debugPrint('Stop Rec Error: $e');
    }
  }

  void _finishRecording() {
    if (_capturedClips.isEmpty) return;
    Navigator.pop(context, _capturedClips);
  }

  void _removeLastClip() {
    if (_capturedClips.isNotEmpty) {
      setState(() {
        final last = _capturedClips.removeLast();
        // Recalculate total time (approximate based on 100ms intervals during recording)
        // For simplicity in this demo, we'll just keep the timer for current session
        _totalRecordedSeconds = _capturedClips.length * 5.0; // Very rough estimation or we could track durations
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator(color: C.brand)));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Camera Preview
          Center(
            child: CameraPreview(_controller!),
          ),

          // 2. Filter Layer (Visual Only Simulation)
          if (_activeFilter != 'Normal')
            _buildFilterOverlay(),

          // 3. UI Layer
          SafeArea(
            child: Column(
              children: [
                _topBar(),
                _buildTimeline(),
                const Spacer(),
                _sideControls(),
                _bottomControls(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline() {
    const maxSeconds = 60.0;
    double progress = (_totalRecordedSeconds / maxSeconds).clamp(0.0, 1.0);

    return Container(
      width: double.infinity,
      height: 6,
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(3)),
      child: Stack(
        children: [
          // Total Progress
          AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: (MediaQuery.of(context).size.width - 40) * progress,
            decoration: BoxDecoration(
              color: C.brand,
              borderRadius: BorderRadius.circular(3),
              boxShadow: [BoxShadow(color: C.brand.withOpacity(0.4), blurRadius: 4)],
            ),
          ),
          // Segment Markers
          ...List.generate(_capturedClips.length, (i) {
             // In a real app we'd store exact duration per clip
             // Here we just show a small divider for each clip added
             return Positioned(
               left: (i + 1) * 40.0, // Simulation
               child: Container(width: 2, height: 6, color: Colors.black),
             );
          }),
        ],
      ),
    );
  }

  Widget _buildFilterOverlay() {
    Color filterColor = Colors.transparent;
    double opacity = 0.2;
    
    if (_activeFilter == 'Cinema') filterColor = Colors.orange.withOpacity(0.1);
    if (_activeFilter == 'Neon') filterColor = Colors.purple.withOpacity(0.2);
    if (_activeFilter == 'Noir') return ColorFiltered(
      colorFilter: const ColorFilter.matrix([
        0.2126, 0.7152, 0.0722, 0, 0,
        0.2126, 0.7152, 0.0722, 0, 0,
        0.2126, 0.7152, 0.0722, 0, 0,
        0,      0,      0,      1, 0,
      ]),
      child: CameraPreview(_controller!),
    );
    
    return Container(color: filterColor);
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 28),
            onPressed: () => Navigator.pop(context),
          ),
          if (_isRecording || _capturedClips.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
              child: Row(
                children: [
                  Icon(_isRecording ? Icons.circle : Icons.movie, color: _isRecording ? Colors.red : C.brand, size: 12),
                  const SizedBox(width: 8),
                  Text(
                    _isRecording ? _formatDuration(_timerSeconds) : '${_capturedClips.length} Clips',
                    style: syne(sz: 14, w: FontWeight.bold, c: Colors.white),
                  ),
                ],
              ),
            ),
          IconButton(
            icon: Icon(_isFrontCamera ? Icons.camera_rear : Icons.camera_front, color: Colors.white, size: 28),
            onPressed: _isRecording ? null : _toggleCamera,
          ),
        ],
      ),
    );
  }

  Widget _sideControls() {
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(right: 16),
        child: Column(
          children: [
            _controlBtn(Icons.zoom_in, 'Zoom', () => _showZoomDialog()),
            const SizedBox(height: 20),
            _controlBtn(Icons.filter_vintage, 'Filters', () => _showFilterDialog()),
            const SizedBox(height: 20),
            _controlBtn(Icons.timer, 'Timer', () {}),
          ],
        ),
      ),
    );
  }

  Widget _controlBtn(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(color: Colors.black26, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 4),
          Text(label, style: dm(sz: 10, c: Colors.white, w: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _bottomControls() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Gallery Button
          GestureDetector(
            onTap: () async {
              if (_isRecording) return;
              // Pass a signal back to UploadScreen to open gallery
              Navigator.pop(context, 'OPEN_GALLERY');
            },
            child: Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2), 
                borderRadius: BorderRadius.circular(8),
                color: Colors.white10,
              ),
              child: const Icon(Icons.photo_library, color: Colors.white, size: 24),
            ),
          ),
          // Delete Last Clip
          if (!_isRecording && _capturedClips.isNotEmpty)
            _controlBtn(Icons.backspace_outlined, 'Undo', _removeLastClip)
          else
            const SizedBox(width: 48),

          const SizedBox(width: 20),
          // Record Button
          GestureDetector(
            onTap: _isRecording ? _stopRecording : _startRecording,
            child: Container(
              width: 80, height: 80,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)),
              child: Container(
                decoration: BoxDecoration(
                  shape: _isRecording ? BoxShape.rectangle : BoxShape.circle,
                  color: Colors.red,
                  borderRadius: _isRecording ? BorderRadius.circular(8) : null,
                ),
              ),
            ),
          ),
          const SizedBox(width: 20),
          
          // Done Button
          if (!_isRecording && _capturedClips.isNotEmpty)
            GestureDetector(
              onTap: _finishRecording,
              child: Container(
                width: 48, height: 48,
                decoration: const BoxDecoration(color: C.brand, shape: BoxShape.circle),
                child: const Icon(Icons.check, color: Colors.black, size: 28),
              ),
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }

  void _showZoomDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      builder: (context) => Container(
        height: 120,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: _speeds.map((s) => GestureDetector(
            onTap: () async { 
              setState(() => _speed = s); 
              await _controller?.setZoomLevel(s == 0.5 ? 1.0 : (s == 1.0 ? 1.0 : 2.0)); // Note: 0.5 is usually just 1x on mobile cameras unless it's ultra-wide
              if (mounted) Navigator.pop(context); 
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(color: _speed == s ? C.brand : Colors.white10, borderRadius: BorderRadius.circular(20)),
              child: Text('${s}x', style: syne(sz: 14, w: FontWeight.bold, c: _speed == s ? Colors.black : Colors.white)),
            ),
          )).toList(),
        ),
      ),
    );
  }

  void _showFilterDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      builder: (context) => Container(
        height: 150,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(20),
          children: _filters.map((f) => GestureDetector(
            onTap: () { setState(() => _activeFilter = f); Navigator.pop(context); },
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              width: 80,
              decoration: BoxDecoration(
                color: _activeFilter == f ? C.brand : Colors.white10,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _activeFilter == f ? C.brand : Colors.white24),
              ),
              child: Center(child: Text(f, style: syne(sz: 12, w: FontWeight.bold, c: _activeFilter == f ? Colors.black : Colors.white))),
            ),
          )).toList(),
        ),
      ),
    );
  }

  String _formatDuration(int deciSeconds) {
    final totalSeconds = (deciSeconds / 10).floor();
    final min = (totalSeconds / 60).floor();
    final sec = totalSeconds % 60;
    return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }
}
