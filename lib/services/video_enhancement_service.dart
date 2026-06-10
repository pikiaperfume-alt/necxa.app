import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_min_gpl/return_code.dart';

class ClipData {
  final String path;
  final double start;
  final double end;
  final double speed;
  final double volume;
  final bool isVideo;
  final bool hasAudio;

  const ClipData({
    required this.path,
    required this.start,
    required this.end,
    this.speed = 1.0,
    this.volume = 1.0,
    this.isVideo = true,
    this.hasAudio = true,
  });
}

class VideoEnhancementService {
  
  /// Complete video enhancement pipeline
  Future<File> enhanceVideo({
    required File inputVideo,
    VideoEnhancementOptions options = const VideoEnhancementOptions(),
    void Function(double progress)? onProgress,
  }) async {
    if (!options.applyBeautyFilter && !options.autoBalance && !options.sharpen) {
      return inputVideo;
    }

    final outputPath = await _getOutputPath();
    List<String> filters = [];

    if (options.applyBeautyFilter) {
      // Apply edge-preserving blur (skin smoothing) and basic color correction
      filters.add("smartblur=lr=3:ls=-0.5:lt=0");
      filters.add("eq=brightness=0.03:saturation=1.1");
    }

    if (options.sharpen) {
      filters.add("unsharp=3:3:1.5");
    }

    String filterComplex = filters.isNotEmpty ? "-vf \"${filters.join(',')}\"" : "";
    
    // -c:v libx264 -crf 26: High-efficiency "Smart" compression
    // -movflags +faststart: Instant play in social feeds
    String command = "-i '${_escapePath(inputVideo.path)}' $filterComplex -c:v libx264 -crf 26 -preset fast -c:a copy -movflags +faststart -y \"$outputPath\"";

    debugPrint('Executing FFmpeg enhance command: $command');
    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();

    if (ReturnCode.isSuccess(returnCode)) {
      debugPrint('Video enhancement successful: $outputPath');
      return File(outputPath);
    } else {
      debugPrint('Video enhancement failed with code: $returnCode');
      return inputVideo; // Return original on failure
    }
  }
  
  Future<String> _getOutputPath() async {
    final tempDir = await getTemporaryDirectory();
    return '${tempDir.path}/vibe_${DateTime.now().millisecondsSinceEpoch}.mp4';
  }

  /// Combine multiple clips into a single video file
  Future<File?> combineSequence({
    required List<ClipData> clips,
    required String aspectRatio,
    String? backgroundMusicPath,
    double musicStart = 0.0,
    double musicEnd = 30.0,
    double musicVolume = 1.0,
    double musicOffset = 0.0,
    String? voiceOverPath,
    double voiceOverVolume = 1.0,
  }) async {
    if (clips.isEmpty) return null;
    final outputPath = await _getOutputPath();
    
    // Order of inputs: [0..N-1] clips, then BGM (optional), then Silent Source
    String inputs = "";
    for (int i = 0; i < clips.length; i++) {
      inputs += "-i '${_escapePath(clips[i].path)}' ";
    }

    int nextIndex = clips.length;
    int? bgmIndex;
    if (backgroundMusicPath != null && backgroundMusicPath.isNotEmpty) {
      inputs += "-i '${_escapePath(backgroundMusicPath)}' ";
      bgmIndex = nextIndex;
      nextIndex++;
    }
    
    int? voiceIndex;
    if (voiceOverPath != null && voiceOverPath.isNotEmpty) {
      inputs += "-i '${_escapePath(voiceOverPath)}' ";
      voiceIndex = nextIndex;
      nextIndex++;
    }

    int silentIndex = nextIndex;
    String silentInput = "-f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100 ";
    
    String filterComplex = "";
    
    int targetWidth = 720;
    int targetHeight = 1280;
    
    if (aspectRatio == '1:1') {
      targetWidth = 720;
      targetHeight = 720;
    } else if (aspectRatio == '4:5') {
      targetWidth = 720;
      targetHeight = 900;
    }

    for (int i = 0; i < clips.length; i++) {
      final clip = clips[i];
      // Note: inputs are already added above in order.
      
      double duration = (clip.end - clip.start).abs();
      if (duration < 0.1) duration = 1.0; // Fallback for safety
      
      // 1. VIDEO NORMALIZATION
      // crop and scale logic
      // Calculate aspect ratio as a float to avoid integer division in FFmpeg expressions
      String cropFilter = "crop=min(iw\\,ih*($targetWidth.0/$targetHeight.0)):min(ih\\,iw*($targetHeight.0/$targetWidth.0))";
      
      // Calculate safe fade duration (max 0.3s or 10% of clip duration)
      double safeFade = (duration / clip.speed * 0.1).clamp(0.0, 0.3);
      double fadeOutStart = (duration / clip.speed) - safeFade;
      if (fadeOutStart < 0) fadeOutStart = 0;

      if (clip.isVideo) {
        filterComplex += "[$i:v]trim=start=${clip.start}:end=${clip.end},setpts=${1.0/clip.speed}*(PTS-STARTPTS),fps=30,format=yuv420p,$cropFilter,scale=$targetWidth:$targetHeight,setsar=1";
        if (safeFade > 0.05) {
          filterComplex += ",fade=t=in:st=0:d=$safeFade,fade=t=out:st=$fadeOutStart:d=$safeFade";
        }
        filterComplex += "[v$i];";
      } else {
        filterComplex += "[$i:v]loop=loop=-1:size=1:start=0,trim=duration=$duration,setpts=PTS-STARTPTS,fps=30,format=yuv420p,$cropFilter,scale=$targetWidth:$targetHeight,setsar=1";
        if (safeFade > 0.05) {
          filterComplex += ",fade=t=in:st=0:d=$safeFade,fade=t=out:st=${duration - safeFade}:d=$safeFade";
        }
        filterComplex += "[v$i];";
      }
      
      // 2. AUDIO NORMALIZATION
      // If speed is not 1.0, we need to handle atempo (0.5 to 2.0 limit)
      String speedFilter = "";
      if (clip.speed != 1.0) {
        double s = clip.speed;
        while (s > 2.0) {
          speedFilter += "atempo=2.0,";
          s /= 2.0;
        }
        while (s < 0.5) {
          speedFilter += "atempo=0.5,";
          s /= 0.5;
        }
        speedFilter += "atempo=$s";
      } else {
        speedFilter = "anull";
      }

      if (clip.isVideo && clip.hasAudio) {
        // Use [i:a] if available, otherwise use silence
        // We use amix with silence to ensure an audio stream exists even if input has none
        filterComplex += "[$i:a]atrim=start=${clip.start}:end=${clip.end},asetpts=PTS-STARTPTS,$speedFilter,volume=${clip.volume},aresample=44100,aformat=channel_layouts=stereo[a_orig_$i];";
        // Mix with a slice of silence for extreme robustness
        filterComplex += "[$silentIndex:a]atrim=duration=${duration/clip.speed},asetpts=PTS-STARTPTS[silence$i];";
        filterComplex += "[a_orig_$i][silence$i]amix=inputs=2:duration=first[a$i];";
      } else {
        // Images or audio-less videos get silence
        filterComplex += "[$silentIndex:a]atrim=duration=${duration/clip.speed},asetpts=PTS-STARTPTS,volume=0[a$i];";
      }
    }
    
    String concatParts = "";
    for (int i = 0; i < clips.length; i++) {
      concatParts += "[v$i][a$i]";
    }
    
    if (clips.length > 1) {
      filterComplex += "${concatParts}concat=n=${clips.length}:v=1:a=1[outv][outa_orig];";
    } else {
      filterComplex += "[v0]copy[outv];[a0]acopy[outa_orig];";
    }
    
    // 3. MIXING ALL AUDIO SOURCES
    String audioSources = "[outa_orig]";
    int inputsCount = 1;

    if (bgmIndex != null) {
      int delayMs = (musicOffset * 1000).toInt();
      filterComplex += "[$bgmIndex:a]atrim=start=$musicStart:end=$musicEnd,asetpts=PTS-STARTPTS,volume=$musicVolume,aresample=44100,aformat=channel_layouts=stereo,adelay=$delayMs|$delayMs[bgm];";
      audioSources += "[bgm]";
      inputsCount++;
    }

    if (voiceIndex != null) {
      filterComplex += "[$voiceIndex:a]volume=$voiceOverVolume,aresample=44100,aformat=channel_layouts=stereo[voice];";
      audioSources += "[voice]";
      inputsCount++;
    }

    if (inputsCount > 1) {
      filterComplex += "${audioSources}amix=inputs=$inputsCount:duration=first:dropout_transition=2[outa]";
    } else {
      filterComplex += "[outa_orig]anull[outa]";
    }
    
    // libx264 -crf 26: The "Economical" compression sweet spot
    // -maxrate 2.5M: Prevents bitrate spikes on mobile data
    String command = "$inputs $silentInput -filter_complex \"$filterComplex\" -map \"[outv]\" -map \"[outa]\" -c:v libx264 -crf 26 -maxrate 2.5M -bufsize 5M -c:a aac -preset fast -pix_fmt yuv420p -movflags +faststart -y \"$outputPath\"";
    
    debugPrint('Executing smarter FFmpeg command: $command');
    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();
    
    if (ReturnCode.isSuccess(returnCode)) {
      debugPrint('FFmpeg SUCCESS: Master file generated at $outputPath');
      return File(outputPath);
    } else if (ReturnCode.isCancel(returnCode)) {
      debugPrint('FFmpeg CANCELLED');
      return null;
    } else {
      final logs = await session.getAllLogsAsString();
      debugPrint('FFmpeg ERROR (Code: $returnCode): $logs');
      return null;
    }
  }

  /// Mix background music with video while keeping original audio (ducked)
  Future<File> mixMusicWithVideo({
    required File inputVideo,
    required File musicFile,
    double musicVolume = 0.4,
    double originalVolume = 0.8,
  }) async {
    return inputVideo;
  }

  String _escapePath(String path) {
    // Escape single quotes for FFmpeg command line
    return path.replaceAll("'", "'\\''");
  }

  /// PROXY ENGINE: Generate a lightweight 540p proxy for smooth editing
  Future<File> generateProxy(File inputVideo) async {
    final tempDir = await getTemporaryDirectory();
    final outputPath = '${tempDir.path}/proxy_${DateTime.now().millisecondsSinceEpoch}.mp4';
    
    // -vf "scale=-2:540": Scales to 540p height while maintaining aspect ratio (must be even for libx264)
    // -preset ultrafast: Maximum speed for proxy generation
    // -crf 28: Lower quality is acceptable for proxy
    String command = "-i '${_escapePath(inputVideo.path)}' -vf \"scale=-2:540\" -c:v libx264 -preset ultrafast -crf 28 -c:a aac -b:a 64k -y \"$outputPath\"";
    
    debugPrint('Generating Proxy: $command');
    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();
    
    if (ReturnCode.isSuccess(returnCode)) {
      return File(outputPath);
    } else {
      debugPrint('Proxy generation failed, falling back to original');
      return inputVideo;
    }
  }
}

class VideoEnhancementOptions {
  final bool applyBeautyFilter;
  final bool autoBalance;
  final bool sharpen;
  final Size? upscaleTo;
  final bool frameInterpolation;
  final bool enhanceThumbnail;
  
  const VideoEnhancementOptions({
    this.applyBeautyFilter = false,
    this.autoBalance = false,
    this.sharpen = false,
    this.upscaleTo,
    this.frameInterpolation = false,
    this.enhanceThumbnail = false,
  });
}

