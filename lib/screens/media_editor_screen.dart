import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../models/edit_models.dart';
import '../widgets/media_editor_tools.dart';
import '../theme.dart';

enum EditorTool { none, trim, text, filter }

class MediaEditorScreen extends StatefulWidget {
  final String mediaPath;
  const MediaEditorScreen({super.key, required this.mediaPath});

  @override
  State<MediaEditorScreen> createState() => _MediaEditorScreenState();
}

class _MediaEditorScreenState extends State<MediaEditorScreen> {
  late VideoPlayerController _controller;
  EditorTool _activeTool = EditorTool.none;
  bool _isToolbarVisible = false;

  // Store for non-destructive edits
  final List<EditOperation> _edits = [];
  TrimOperation? _trimOp;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.mediaPath))
      ..initialize().then((_) {
        setState(() {});
        _controller.setLooping(true);
        _controller.play();
        _trimOp = TrimOperation(
          start: Duration.zero,
          end: _controller.value.duration,
          maxDuration: _controller.value.duration,
        );
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleToolbar() {
    setState(() {
      _isToolbarVisible = !_isToolbarVisible;
      // If hiding toolbar, also deactivate any active tool
      if (!_isToolbarVisible) {
        _activeTool = EditorTool.none;
      }
    });
  }

  void _onToolSelected(EditorTool tool) {
    setState(() {
      // Toggle tool off if it's already active, otherwise switch to it
      _activeTool = _activeTool == tool ? EditorTool.none : tool;
    });
  }

  void _onFinishEditing() {
    // 1. Consolidate all edits
    final finalEdits = <EditOperation>[];
    if (_trimOp != null && (_trimOp!.start > Duration.zero || _trimOp!.end < _trimOp!.maxDuration)) {
      finalEdits.add(_trimOp!);
    }
    finalEdits.addAll(_edits.where((e) => e is! TrimOperation));

    // 2. Serialize to JSON
    final editingMetadata = {
      'version': '1.0',
      'edits': finalEdits.map((e) => e.toJson()).toList(),
    };

    // 3. Return metadata to the previous screen
    Navigator.pop(context, editingMetadata);
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final isToolActive = _activeTool != EditorTool.none;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleToolbar,
        child: Stack(
          children: [
            // --- Video Player ---
            // The container animates its size to make room for the tools.
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              height: isToolActive ? screenHeight * 0.65 : screenHeight,
              alignment: Alignment.center,
              child: _controller.value.isInitialized
                  ? AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: VideoPlayer(_controller),
                    )
                  : const Center(child: CircularProgressIndicator(color: C.brand)),
            ),

            // --- Top Bar (Save/Cancel) ---
            AnimatedOpacity(
              opacity: _isToolbarVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white, size: 28),
                        onPressed: () => Navigator.pop(context),
                      ),
                      TextButton(
                        onPressed: _onFinishEditing,
                        style: TextButton.styleFrom(backgroundColor: C.brand, padding: const EdgeInsets.symmetric(horizontal: 20)),
                        child: Text('Done', style: syne(c: Colors.black, w: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // --- Bottom Toolbars ---
            if (_isToolbarVisible)
              Align(
                alignment: Alignment.bottomCenter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Specific tool's UI (e.g., Trimmer)
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, animation) => SlideTransition(
                        position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(animation),
                        child: child,
                      ),
                      child: _buildActiveToolWidget(),
                    ),
                    // Main tool selection bar
                    MainToolbar(
                      activeTool: _activeTool,
                      onToolSelected: _onToolSelected,
                    ),
                    SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveToolWidget() {
    if (!_controller.value.isInitialized) return const SizedBox.shrink();

    switch (_activeTool) {
      case EditorTool.trim:
        return TrimTool(
          controller: _controller,
          trimOperation: _trimOp!,
          onTrimChanged: (start, end) => setState(() {
            _trimOp?.start = start;
            _trimOp?.end = end;
          }),
        );
      case EditorTool.text:
        return const TextTool(); // Placeholder
      case EditorTool.filter:
        return const FilterTool(); // Placeholder
      case EditorTool.none:
        return const SizedBox.shrink();
    }
  }
}