import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../models/edit_models.dart';
import '../screens/media_editor_screen.dart';
import '../theme.dart';

/// Main toolbar for selecting an editing tool.
class MainToolbar extends StatelessWidget {
  final EditorTool activeTool;
  final ValueChanged<EditorTool> onToolSelected;

  const MainToolbar({super.key, required this.activeTool, required this.onToolSelected});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.3),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildToolIcon(EditorTool.trim, Icons.cut_rounded, 'Trim'),
          _buildToolIcon(EditorTool.text, Icons.text_fields_rounded, 'Text'),
          _buildToolIcon(EditorTool.filter, Icons.filter_vintage_rounded, 'Filter'),
        ],
      ),
    );
  }

  Widget _buildToolIcon(EditorTool tool, IconData icon, String label) {
    final isActive = activeTool == tool;
    final color = isActive ? C.brand : Colors.white;
    return GestureDetector(
      onTap: () => onToolSelected(tool),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 4),
          Text(label, style: dm(sz: 10, c: color)),
        ],
      ),
    );
  }
}

/// UI for the video trimming tool.
class TrimTool extends StatefulWidget {
  final VideoPlayerController controller;
  final TrimOperation trimOperation;
  final Function(Duration start, Duration end) onTrimChanged;

  const TrimTool({
    super.key,
    required this.controller,
    required this.trimOperation,
    required this.onTrimChanged,
  });

  @override
  State<TrimTool> createState() => _TrimToolState();
}

class _TrimToolState extends State<TrimTool> {
  // In a real app, this would be a proper video trimmer UI package.
  // For this example, we use a RangeSlider to simulate it.
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: RangeSlider(
        values: RangeValues(
          widget.trimOperation.start.inMilliseconds.toDouble(),
          widget.trimOperation.end.inMilliseconds.toDouble(),
        ),
        min: 0,
        max: widget.trimOperation.maxDuration.inMilliseconds.toDouble(),
        activeColor: C.brand,
        inactiveColor: Colors.white24,
        onChanged: (values) => widget.onTrimChanged(Duration(milliseconds: values.start.round()), Duration(milliseconds: values.end.round())),
      ),
    );
  }
}

// Placeholder widgets for other tools
class TextTool extends StatelessWidget {
  const TextTool({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox(height: 80, child: Center(child: Text('Text Controls UI', style: TextStyle(color: Colors.white))));
}

class FilterTool extends StatelessWidget {
  const FilterTool({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox(height: 80, child: Center(child: Text('Filter Selection UI', style: TextStyle(color: Colors.white))));
}