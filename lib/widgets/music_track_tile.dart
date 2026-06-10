import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/music_models.dart';
import '../theme.dart';

class MusicTrackTile extends StatelessWidget {
  final MusicTrack track;
  final VoidCallback onTap;
  final bool isPlaying;

  const MusicTrackTile({
    super.key,
    required this.track,
    required this.onTap,
    this.isPlaying = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isPlaying ? C.brand.withOpacity(0.1) : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isPlaying ? C.brand.withOpacity(0.3) : Colors.white10,
          ),
        ),
        child: Row(
          children: [
            // Album Art
            Stack(
              alignment: Alignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: track.albumArtUrl != null
                      ? Image.network(track.albumArtUrl!, width: 56, height: 56, fit: BoxFit.cover)
                      : Container(
                          width: 56, height: 56,
                          color: Colors.white12,
                          child: const Icon(Icons.music_note, color: Colors.white38),
                        ),
                ),
                if (isPlaying)
                  Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(12)),
                    child: const Center(child: Icon(Icons.pause, color: C.brand)),
                  )
                else
                  const Center(child: Icon(Icons.play_arrow, color: Colors.white54, size: 20)),
              ],
            ),
            const SizedBox(width: 16),
            
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    style: syne(sz: 15, w: FontWeight.bold, c: isPlaying ? C.brand : Colors.white),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    track.artistName,
                    style: dm(sz: 13, c: Colors.white60),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            
            // Duration & Viral Count
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(track.formattedDuration, style: dm(sz: 12, c: Colors.white38)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.trending_up, size: 10, color: Colors.white24),
                    const SizedBox(width: 4),
                    Text('${track.usageCount}k', style: dm(sz: 10, c: Colors.white24)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
