import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:mongo_dart/mongo_dart.dart' as mongo;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../app_state.dart';

/// 🚀 Necxa Live Studio: Core Streaming Engine
/// Handles high-fidelity video/audio pipelines via Agora and real-time metadata via MongoDB.
class LiveStreamingService {
  final AppState state;
  RtcEngine? _engine;
  String? _activeChannelName;
  bool _hostingActiveChannel = false;
  
  // Agora Configuration
  static const String appId = "2d9c22945103407da35ff652bf8c9a2d";
  
  // MongoDB Configuration (Real-time Metadata Layer)
  mongo.Db? _db;
  static const String mongoUri = "mongodb://atlas-sql-6630b6a8fed7652b996aeb3d-n5eg1.a.query.mongodb.net/Hakuna?ssl=true&authSource=admin";
  
  LiveStreamingService(this.state);

  /// Exposes the Agora engine for external callers (e.g. silent face pulse snapshot).
  RtcEngine? get engine => _engine;

  // ── Initialization ──────────────────────────────────────────

  Future<void> init() async {
    // 1. Request Permissions
    await [Permission.camera, Permission.microphone].request();

    // 2. Initialize Agora Engine
    _engine = createAgoraRtcEngine();
    await _engine!.initialize(const RtcEngineContext(
      appId: appId,
      channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
    ));

    // 3. Setup Video Enhancement (Superior Filters)
    await _engine!.enableVideo();
    await _engine!.setVideoEncoderConfiguration(
      const VideoEncoderConfiguration(
        dimensions: VideoDimensions(width: 1080, height: 1920),
        frameRate: 30,
        bitrate: 2500, // High-performance 1080p bitrate
        orientationMode: OrientationMode.orientationModeFixedPortrait,
      ),
    );

    // 4. Superior Sound Setup
    await _engine!.setAudioProfile(
      profile: AudioProfileType.audioProfileMusicHighQualityStereo,
      scenario: AudioScenarioType.audioScenarioGameStreaming,
    );

    // 5. Connect to MongoDB Real-time Layer
    try {
      _db = await mongo.Db.create(mongoUri);
      await _db!.open();
      debugPrint('🛡️ Necxa Live: MongoDB Connected');
    } catch (e) {
      debugPrint('⚠️ Necxa Live: MongoDB Connection Failed: $e');
    }
  }

  // ── Stream Control ──────────────────────────────────────────

  Future<void> startStreaming(String channelName) async {
    if (_engine == null) return;
    
    // 1. Identity & Location Stamping + Token Acquisition
    try {
      final response = await Supabase.instance.client.functions.invoke('live-studio-engine', body: {
        'action': 'start',
        'channelId': channelName,
        'userId': state.user?.id,
        'metadata': {
          'hostName': state.myProfile?['full_name'] ?? 'Necxa Creator',
          'avatar': state.myProfile?['avatar_url'] ?? '',
          'title': 'Live Studio Session',
        },
        'location': {
          'lat': state.currentGps?.latitude ?? 0.0,
          'lng': state.currentGps?.longitude ?? 0.0,
        }
      });

      if (response.status == 200) {
        final data = Map<String, dynamic>.from(response.data ?? {});
        final token = (data['token'] ?? '').toString();
        if (token.isEmpty) {
          throw 'Live token was not returned by the server.';
        }
        _activeChannelName = channelName;
        _hostingActiveChannel = true;
        
        // 2. Set role as Broadcaster (Host)
        await _engine!.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
        
        // 3. Enable Beauty Filters
        await _engine!.setBeautyEffectOptions(
          enabled: true,
          options: const BeautyOptions(
            lighteningContrastLevel: LighteningContrastLevel.lighteningContrastHigh,
            lighteningLevel: 0.8,
            smoothnessLevel: 0.6,
            rednessLevel: 0.1,
            sharpnessLevel: 0.3,
          ),
        );

        await _engine!.joinChannel(
          token: token,
          channelId: channelName,
          uid: 0,
          options: const ChannelMediaOptions(),
        );
      } else {
        throw _functionError(response.data, fallback: 'Authentication failed');
      }
    } catch (e) {
      debugPrint('⚠️ Necxa Live: Start Failed: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getActiveStreams() async {
    try {
      final response = await Supabase.instance.client.functions.invoke('live-studio-engine', body: {
        'action': 'list_active',
      });
      if (response.status == 200) {
        return List<Map<String, dynamic>>.from(response.data);
      }
    } catch (e) {
      debugPrint('⚠️ Necxa Live: Failed to list active streams: $e');
    }
    return [];
  }

  Future<void> joinAsViewer(String channelName) async {
    if (_engine == null) return;
    
    try {
      // 1. Fetch token for audience
      final response = await Supabase.instance.client.functions.invoke('live-studio-engine', body: {
        'action': 'join',
        'channelId': channelName,
        'userId': state.user?.id,
        'role': 'audience',
      });

      if (response.status == 200) {
        final data = Map<String, dynamic>.from(response.data ?? {});
        final token = (data['token'] ?? '').toString();
        if (token.isEmpty) {
          throw 'Viewer live token was not returned by the server.';
        }
        _activeChannelName = channelName;
        _hostingActiveChannel = false;

        // 2. Set role as Audience
        await _engine!.setClientRole(role: ClientRoleType.clientRoleAudience);
        
        // 3. Join securely with token
        await _engine!.joinChannel(
          token: token,
          channelId: channelName,
          uid: 0,
          options: const ChannelMediaOptions(),
        );
      } else {
        throw _functionError(response.data, fallback: 'Viewer authentication failed');
      }
    } catch (e) {
      debugPrint('⚠️ Necxa Live: Join as Viewer Failed: $e');
      rethrow;
    }
  }

  Future<void> leaveChannel() async {
    final channelName = _activeChannelName;
    final shouldStop = _hostingActiveChannel && channelName != null;
    if (shouldStop) {
      await stopStreaming(channelName);
    }
    if (_engine != null) {
      await _engine!.leaveChannel();
    }
    _activeChannelName = null;
    _hostingActiveChannel = false;
  }

  Future<void> stopStreaming(String channelName) async {
    try {
      await Supabase.instance.client.functions.invoke('live-studio-engine', body: {
        'action': 'stop',
        'channelId': channelName,
        'userId': state.user?.id,
      });
    } catch (e) {
      debugPrint('⚠️ Necxa Live: Stop sync failed: $e');
    }
  }

  Future<void> switchRoleToBroadcaster() async {
    if (_engine == null) return;
    final channelName = _activeChannelName;
    if (channelName == null) throw 'No active live channel.';

    final response = await Supabase.instance.client.functions.invoke('live-studio-engine', body: {
      'action': 'join',
      'channelId': channelName,
      'userId': state.user?.id,
      'role': 'publisher',
    });

    if (response.status != 200) {
      throw _functionError(response.data, fallback: 'Broadcaster authentication failed');
    }
    final data = Map<String, dynamic>.from(response.data ?? {});
    final token = (data['token'] ?? '').toString();
    if (token.isEmpty) {
      throw 'Broadcaster live token was not returned by the server.';
    }

    await _engine!.renewToken(token);
    await _engine!.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
    await _engine!.enableLocalAudio(true);
    await _engine!.enableLocalVideo(true);
  }

  Future<void> switchRoleToAudience() async {
    if (_engine == null) return;
    final channelName = _activeChannelName;
    if (channelName != null) {
      final response = await Supabase.instance.client.functions.invoke('live-studio-engine', body: {
        'action': 'join',
        'channelId': channelName,
        'userId': state.user?.id,
        'role': 'audience',
      });

      if (response.status == 200) {
        final data = Map<String, dynamic>.from(response.data ?? {});
        final token = (data['token'] ?? '').toString();
        if (token.isNotEmpty) {
          await _engine!.renewToken(token);
        }
      }
    }
    await _engine!.enableLocalAudio(false);
    await _engine!.enableLocalVideo(false);
    await _engine!.setClientRole(role: ClientRoleType.clientRoleAudience);
  }

  // ── Real-time Metadata (MongoDB) ─────────────────────────────

  Future<void> pinProduct(String channelId, Map<String, dynamic> product) async {
    if (_db == null) return;
    final coll = _db!.collection('stream_metadata');
    await coll.update(
      mongo.where.eq('channelId', channelId),
      mongo.modify.set('pinnedProduct', product),
      upsert: true,
    );
  }

  Future<void> sendLiveGift(String channelId, String userId, Map<String, dynamic> gift) async {
    if (_db == null) return;
    final coll = _db!.collection('stream_events');
    await coll.insert({
      'channelId': channelId,
      'userId': userId,
      'type': 'gift',
      'data': gift,
      'timestamp': DateTime.now().toIso8601String(),
    });

    // Also push a special system comment to stream_chat so everyone sees the gift alert in their feeds!
    final chatColl = _db!.collection('stream_chat');
    await chatColl.insert({
      'channelName': channelId,
      'userName': gift['userName'] ?? 'Viewer',
      'text': 'sent a ${gift['name'] ?? 'Gift'} ${gift['emoji'] ?? '🎁'}',
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  Future<void> sendCoHostRequest(String channelId, String userId, Map<String, dynamic> metadata) async {
    if (_db == null) throw 'Live event service is unavailable. Please try again.';
    final coll = _db!.collection('stream_events');
    await coll.insert({
      'channelId': channelId,
      'userId': userId,
      'type': 'cohost_request',
      'data': metadata,
      'timestamp': DateTime.now().toIso8601String(),
    });
    debugPrint('🛡️ Necxa Live: Co-Host Request Sent to MongoDB');
  }

  Future<void> sendCoHostDecision(String channelId, String guestId, bool accepted) async {
    if (_db == null) throw 'Live event service is unavailable. Please try again.';
    final coll = _db!.collection('stream_events');
    await coll.insert({
      'channelId': channelId,
      'userId': guestId, // The guest who requested it
      'type': 'cohost_decision',
      'data': {'accepted': accepted},
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  Future<void> sendLiveComment(String channelName, String userName, String text) async {
    if (_db == null) return;
    try {
      final coll = _db!.collection('stream_chat');
      await coll.insert({
        'channelName': channelName,
        'userName': userName,
        'text': text,
        'timestamp': DateTime.now().toIso8601String(),
      });
      debugPrint('💬 Necxa Live: Comment Pushed to MongoDB');
    } catch (e) {
      debugPrint('⚠️ Necxa Live: Failed to push comment: $e');
    }
  }

  Future<List<Map<String, dynamic>>> fetchLiveComments(String channelName) async {
    if (_db == null) return [];
    try {
      final coll = _db!.collection('stream_chat');
      final results = await coll
          .find(mongo.where.eq('channelName', channelName).sortBy('timestamp', descending: true).limit(20))
          .toList();
      return results.map((c) => {
        'user': c['userName'] ?? 'User',
        'text': c['text'] ?? '',
      }).toList();
    } catch (e) {
      debugPrint('⚠️ Necxa Live: Failed to fetch comments: $e');
      return [];
    }
  }

  Stream<Map<String, dynamic>> listenToEvents(String channelId) {
    if (_db == null) return const Stream.empty();
    final coll = _db!.collection('stream_events');
    // In production, use Change Streams for real-time performance
    return Stream.periodic(const Duration(seconds: 1)).asyncMap((_) async {
      final lastEvent = await coll.findOne(
        mongo.where.eq('channelId', channelId).sortBy('timestamp', descending: true),
      );
      return lastEvent ?? {};
    });
  }

  String _functionError(dynamic data, {required String fallback}) {
    if (data is Map && data['error'] != null) return data['error'].toString();
    if (data is String && data.trim().isNotEmpty) return data;
    return fallback;
  }

  // ── Disposal ────────────────────────────────────────────────

  Future<void> dispose() async {
    await _engine?.release();
    await _db?.close();
  }
}
