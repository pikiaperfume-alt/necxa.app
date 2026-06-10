import 'package:flutter/material.dart';
import '../theme.dart';

// ── OBJECTIVE CARD ───────────────────────────────────────────
class ObjectiveCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onTap;
  final bool isSelected;

  const ObjectiveCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colors,
    required this.onTap,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.only(bottom: 16),
        height: 120,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isSelected 
              ? colors 
              : [colors[0].withOpacity(0.1), colors[1].withOpacity(0.05)],
          ),
          border: Border.all(
            color: isSelected ? Colors.white : colors[0].withOpacity(0.3),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected ? [
            BoxShadow(color: colors[0].withOpacity(0.4), blurRadius: 20, spreadRadius: 0)
          ] : [],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              Positioned(
                right: -10, bottom: -10,
                child: Icon(icon, color: Colors.white.withOpacity(0.05), size: 100),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.black26 : colors[0].withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: isSelected ? Colors.white : colors[0], size: 28),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            title, 
                            style: syne(
                              sz: 18, 
                              w: FontWeight.w900, 
                              c: isSelected ? Colors.white : Colors.white,
                              ls: 1,
                            )
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle, 
                            style: dm(
                              sz: 12, 
                              c: isSelected ? Colors.white.withOpacity(0.8) : Colors.white54
                            )
                          ),
                        ],
                      ),
                    ),
                    if (isSelected) 
                      const Icon(Icons.check_circle, color: Colors.white, size: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── PREMIUM PROGRESS STEPPER ─────────────────────────────────
class PremiumStepper extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  final Color accentColor;

  const PremiumStepper({
    super.key,
    required this.currentStep,
    required this.totalSteps,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        children: [
          Row(
            children: List.generate(totalSteps, (i) {
              final active = i <= currentStep;
              return Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  height: 4,
                  margin: EdgeInsets.only(right: i == totalSteps - 1 ? 0 : 6),
                  decoration: BoxDecoration(
                    color: active ? accentColor : Colors.white12,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: active ? [
                      BoxShadow(color: accentColor.withOpacity(0.4), blurRadius: 4)
                    ] : [],
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('STEP ${currentStep + 1}', style: syne(sz: 10, w: FontWeight.w800, c: accentColor, ls: 1)),
              Text('OF $totalSteps', style: syne(sz: 10, w: FontWeight.w800, c: Colors.white24, ls: 1)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── GLASS CARD ───────────────────────────────────────────────
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final double? height;

  const GlassCard({super.key, required this.child, this.padding, this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white10),
      ),
      child: child,
    );
  }
}
// ── TIMELINE TRACK ───────────────────────────────────────────
class TimelineTrack extends StatelessWidget {
  final String label;
  final double startTime; // 0.0 to 1.0
  final double endTime;   // 0.0 to 1.0
  final Color color;
  final Function(double, double) onRangeChanged;
  final bool isSelected;

  const TimelineTrack({
    super.key,
    required this.label,
    required this.startTime,
    required this.endTime,
    required this.color,
    required this.onRangeChanged,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isSelected ? Colors.white.withOpacity(0.05) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.layers_outlined, size: 12, color: color),
              const SizedBox(width: 8),
              Text(label, style: syne(sz: 10, w: FontWeight.bold, c: Colors.white70)),
            ],
          ),
          const SizedBox(height: 8),
          Stack(
            children: [
              // Track background
              Container(
                height: 24,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              // Range segment
              Positioned(
                left: startTime * MediaQuery.of(context).size.width * 0.6,
                width: (endTime - startTime) * MediaQuery.of(context).size.width * 0.6,
                child: Container(
                  height: 24,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: color),
                  ),
                  child: const Center(
                    child: Icon(Icons.drag_handle, size: 16, color: Colors.white70),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── MASKING PREVIEW ──────────────────────────────────────────
class MaskingPreview extends StatefulWidget {
  final Widget child;
  final List<Widget> overlays;
  final bool isMasked;
  final VoidCallback onToggle;

  const MaskingPreview({
    super.key,
    required this.child,
    required this.overlays,
    this.isMasked = false,
    required this.onToggle,
  });

  @override
  State<MaskingPreview> createState() => _MaskingPreviewState();
}

class _MaskingPreviewState extends State<MaskingPreview> {
  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (!widget.isMasked) ...widget.overlays,
        
        // Mask Toggle Button
        Positioned(
          top: 60,
          left: 16,
          child: GestureDetector(
            onTap: widget.onToggle,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: widget.isMasked ? C.brand : Colors.black38,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24),
              ),
              child: Icon(
                widget.isMasked ? Icons.visibility_off : Icons.visibility,
                color: widget.isMasked ? Colors.black : Colors.white,
                size: 20,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
