import 'package:flutter/material.dart';
import '../theme.dart';
import '../app_state.dart';

import 'package:cached_network_image/cached_network_image.dart';

class NecxaAvatar extends StatelessWidget {
  final String? url;
  final String? userId;
  final String? name;
  final double size;
  final bool shadow;
  final VoidCallback? onTap;

  const NecxaAvatar({
    super.key,
    this.url,
    this.userId,
    this.name,
    this.size = 48,
    this.shadow = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Locate the nearest AppState without depending on provider package
    final state = AppState.maybeOf(context);

    String? finalUrl = url;
    String? finalName = name;

    if (state != null && userId != null && userId == state.user?.id) {
      finalUrl ??= state.currentProfile?['avatar_url'] ??
          state.currentProfile?['photo_url'];
      finalName ??= state.currentProfile?['full_name'] ??
          state.currentProfile?['display_name'];
    }

    String initials = '?';
    if (finalName != null && finalName.trim().isNotEmpty) {
      final parts = finalName.trim().split(' ');
      if (parts.length > 1 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
        initials = (parts[0][0] + parts[1][0]).toUpperCase();
      } else if (parts[0].isNotEmpty) {
        initials = parts[0][0].toUpperCase();
      }
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: shadow
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  )
                ]
              : null,
          border: Border.all(
            color: C.brand.withOpacity(0.2),
            width: 1.5,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(size / 2),
          child: Container(
            color: C.card2,
            child: finalUrl != null && finalUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: finalUrl,
                    fit: BoxFit.cover,
                    width: size,
                    height: size,
                    placeholder: (_, __) => Center(
                      child: SizedBox(
                        width: size * 0.5,
                        height: size * 0.5,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: C.brand.withOpacity(0.3),
                        ),
                      ),
                    ),
                    errorWidget: (_, __, ___) => _fallback(initials),
                  )
                : _fallback(initials),
          ),
        ),
      ),
    );
  }

  Widget _fallback(String initials) {
    return Center(
      child: Text(
        initials,
        style: syne(
          sz: size * 0.38,
          w: FontWeight.w800,
          c: C.brand,
        ),
      ),
    );
  }
}


