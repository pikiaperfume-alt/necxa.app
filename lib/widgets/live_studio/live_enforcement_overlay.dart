import 'package:flutter/material.dart';
import 'dart:ui';
import '../../theme.dart';

class LiveEnforcementOverlay extends StatelessWidget {
  final String? enforcementReason;
  final VoidCallback onClose;

  const LiveEnforcementOverlay({
    super.key,
    required this.enforcementReason,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          color: Colors.black87,
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.black, // Assuming NecxaColors.surface is dark
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.redAccent.withOpacity(0.3), width: 1),
                boxShadow: [
                  BoxShadow(color: Colors.redAccent.withOpacity(0.1), blurRadius: 40, spreadRadius: -10),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.gavel_rounded, color: Colors.redAccent, size: 48),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    "Stream Terminated",
                    style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: -0.5),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "This stream has been terminated due to a violation of our community safety guidelines.\n\nReason: ${enforcementReason ?? 'Dangerous or inappropriate content.'}",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 15, height: 1.5),
                  ),
                  const SizedBox(height: 32),
                  GestureDetector(
                    onTap: onClose,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Center(
                        child: Text(
                          "CLOSE STUDIO",
                          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
