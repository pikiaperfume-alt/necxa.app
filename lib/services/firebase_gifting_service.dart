import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

// ── Gift item model (mirrors gift_items Firestore collection) ─────────────────
class GiftItem {
  final String id;
  final String name;
  final String emoji;
  final int ncxValue;
  final int ugxValue;
  final String category; // standard | rare | epic | legendary
  final int sortOrder;
  final bool isActive;

  const GiftItem({
    required this.id,
    required this.name,
    required this.emoji,
    required this.ncxValue,
    required this.ugxValue,
    required this.category,
    required this.sortOrder,
    this.isActive = true,
  });

  factory GiftItem.fromJson(Map<String, dynamic> json) => GiftItem(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        emoji: json['emoji'] as String? ?? '💎',
        ncxValue: (json['ncx_value'] as num?)?.toInt() ?? 0,
        ugxValue: (json['ugx_value'] as num?)?.toInt() ?? 0,
        category: json['category'] as String? ?? 'standard',
        sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
        isActive: json['is_active'] as bool? ?? true,
      );

  String get categoryLabel {
    switch (category) {
      case 'rare':      return '✨ Rare';
      case 'epic':      return '💥 Epic';
      case 'legendary': return '🌟 Legendary';
      default:          return 'Standard';
    }
  }
}

// ── Gift result model ─────────────────────────────────────────────────────────
class GiftResult {
  final bool success;
  final String giftId;
  final String giftEmoji;
  final String giftName;
  final int ncxAmount;
  final int receiverNcx;
  final int platformFeeNcx;
  final int ugxEquivalent;
  final bool isHighlighted;
  final String message;

  const GiftResult({
    required this.success,
    required this.giftId,
    required this.giftEmoji,
    required this.giftName,
    required this.ncxAmount,
    required this.receiverNcx,
    required this.platformFeeNcx,
    required this.ugxEquivalent,
    required this.isHighlighted,
    required this.message,
  });

  factory GiftResult.fromMap(Map<String, dynamic> d) => GiftResult(
        success: d['success'] as bool? ?? false,
        giftId: d['giftId'] as String? ?? '',
        giftEmoji: d['giftEmoji'] as String? ?? '💎',
        giftName: d['giftName'] as String? ?? '',
        ncxAmount: (d['ncxAmount'] as num?)?.toInt() ?? 0,
        receiverNcx: (d['receiverNcx'] as num?)?.toInt() ?? 0,
        platformFeeNcx: (d['platformFeeNcx'] as num?)?.toInt() ?? 0,
        ugxEquivalent: (d['ugxEquivalent'] as num?)?.toInt() ?? 0,
        isHighlighted: d['isHighlighted'] as bool? ?? false,
        message: d['message'] as String? ?? '',
      );
}

// ── Context gift entry ────────────────────────────────────────────────────────
class ContextGiftEntry {
  final String giftId;
  final String? senderId;
  final String giftEmoji;
  final String giftName;
  final int ncxAmount;
  final int ugxEquivalent;
  final int receiverNcx;
  final bool isAnonymous;
  final bool isHighlighted;
  final DateTime? createdAt;

  const ContextGiftEntry({
    required this.giftId,
    this.senderId,
    required this.giftEmoji,
    required this.giftName,
    required this.ncxAmount,
    required this.ugxEquivalent,
    required this.receiverNcx,
    required this.isAnonymous,
    required this.isHighlighted,
    this.createdAt,
  });

  factory ContextGiftEntry.fromMap(Map<String, dynamic> d) => ContextGiftEntry(
        giftId: d['gift_id'] as String? ?? '',
        senderId: d['sender_id'] as String?,
        giftEmoji: d['gift_emoji'] as String? ?? '💎',
        giftName: d['gift_name'] as String? ?? '',
        ncxAmount: (d['ncx_amount'] as num?)?.toInt() ?? 0,
        ugxEquivalent: (d['ugx_equivalent'] as num?)?.toInt() ?? 0,
        receiverNcx: (d['receiver_ncx'] as num?)?.toInt() ?? 0,
        isAnonymous: d['is_anonymous'] as bool? ?? false,
        isHighlighted: d['is_highlighted'] as bool? ?? false,
        createdAt: d['created_at'] != null ? DateTime.tryParse(d['created_at'] as String) : null,
      );
}

// ── Context gift totals ───────────────────────────────────────────────────────
class ContextGiftTotals {
  final int totalGifts;
  final int totalNcx;
  final int totalUgx;
  final int uniqueGifters;
  final String? topEmoji;

  const ContextGiftTotals({
    required this.totalGifts,
    required this.totalNcx,
    required this.totalUgx,
    required this.uniqueGifters,
    this.topEmoji,
  });

  factory ContextGiftTotals.fromMap(Map<String, dynamic> d) => ContextGiftTotals(
        totalGifts: (d['total_gifts'] as num?)?.toInt() ?? 0,
        totalNcx: (d['total_ncx'] as num?)?.toInt() ?? 0,
        totalUgx: (d['total_ugx'] as num?)?.toInt() ?? 0,
        uniqueGifters: (d['unique_gifters'] as num?)?.toInt() ?? 0,
        topEmoji: d['top_emoji'] as String?,
      );

  factory ContextGiftTotals.empty() => const ContextGiftTotals(
        totalGifts: 0, totalNcx: 0, totalUgx: 0, uniqueGifters: 0);
}

// ── Gift streak ───────────────────────────────────────────────────────────────
class GiftStreak {
  final String userId;
  final int currentStreak;
  final int longestStreak;
  final int totalGiftsSent;
  final int totalNcxSent;
  final String? lastGiftDate;

  const GiftStreak({
    required this.userId,
    required this.currentStreak,
    required this.longestStreak,
    required this.totalGiftsSent,
    required this.totalNcxSent,
    this.lastGiftDate,
  });

  factory GiftStreak.fromMap(String uid, Map<String, dynamic> d) => GiftStreak(
        userId: uid,
        currentStreak: (d['current_streak'] as num?)?.toInt() ?? 0,
        longestStreak: (d['longest_streak'] as num?)?.toInt() ?? 0,
        totalGiftsSent: (d['total_gifts_sent'] as num?)?.toInt() ?? 0,
        totalNcxSent: (d['total_ncx_sent'] as num?)?.toInt() ?? 0,
        lastGiftDate: d['last_gift_date'] as String?,
      );
}

// ═════════════════════════════════════════════════════════════════════════════
// FirebaseGiftingService
// ═════════════════════════════════════════════════════════════════════════════
class FirebaseGiftingService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseFunctions _fn = FirebaseFunctions.instance;

  // ── Catalogue ────────────────────────────────────────────────────────────

  /// Fetches the full gift items catalogue from Firestore (seeded on first
  /// Cloud Function call). Returns items sorted by sort_order.
  Future<List<GiftItem>> fetchGiftItems() async {
    try {
      final snap = await _db
          .collection('gift_items')
          .where('is_active', isEqualTo: true)
          .orderBy('sort_order')
          .get();

      if (snap.docs.isEmpty) return _localCatalogue();

      return snap.docs
          .map((d) => GiftItem.fromJson({'id': d.id, ...d.data()}))
          .toList();
    } catch (e) {
      debugPrint('🎁 GiftingService: fetchGiftItems error: $e');
      return _localCatalogue();
    }
  }

  /// Gift items grouped by category for UI rendering.
  Future<Map<String, List<GiftItem>>> fetchGiftItemsByCategory() async {
    final items = await fetchGiftItems();
    final map = <String, List<GiftItem>>{};
    for (final item in items) {
      map.putIfAbsent(item.category, () => []).add(item);
    }
    return map;
  }

  // ── Core send ────────────────────────────────────────────────────────────

  /// Sends a gift via the `processGift` Cloud Function.
  ///
  /// [contextType] — one of: creator_post | live_stream |
  ///                          property_listing | broadcast_message | direct
  Future<GiftResult> sendGift({
    required String senderId,
    required String receiverId,
    required String giftItemId,
    required int ncxAmount,
    required String contextType,
    String? contextId,
    String? contextNote,
    bool isAnonymous = false,
  }) async {
    try {
      final callable = _fn.httpsCallable('processGift');
      final result = await callable.call({
        'receiverId': receiverId,
        'giftItemId': giftItemId,
        'ncxAmount': ncxAmount,
        'contextType': contextType,
        'contextId': contextId,
        'contextNote': contextNote,
        'isAnonymous': isAnonymous,
      });
      return GiftResult.fromMap(Map<String, dynamic>.from(result.data as Map));
    } on FirebaseFunctionsException catch (e) {
      debugPrint('🎁 processGift error: ${e.code} — ${e.message}');
      return GiftResult(
        success: false, giftId: '', giftEmoji: '💎', giftName: '',
        ncxAmount: ncxAmount, receiverNcx: 0, platformFeeNcx: 0,
        ugxEquivalent: 0, isHighlighted: false,
        message: e.message ?? 'Gift failed.',
      );
    }
  }

  // ── Context feed ─────────────────────────────────────────────────────────

  /// Fetches recent gifts on a post / stream / listing.
  Future<List<ContextGiftEntry>> getContextGifts({
    required String contextId,
    required String contextType,
    int limit = 20,
  }) async {
    try {
      final callable = _fn.httpsCallable('getContextGifts');
      final result = await callable.call({
        'contextId': contextId,
        'contextType': contextType,
        'limit': limit,
      });
      final list = (result.data as List).cast<Map>();
      return list.map((m) => ContextGiftEntry.fromMap(Map<String, dynamic>.from(m))).toList();
    } catch (e) {
      debugPrint('🎁 getContextGifts error: $e');
      return [];
    }
  }

  /// Real-time stream of gifts on a context — useful for live streams.
  Stream<List<ContextGiftEntry>> streamContextGifts({
    required String contextId,
    required String contextType,
    int limit = 30,
  }) {
    return _db
        .collection('ncx_gifts')
        .where('context_id', isEqualTo: contextId)
        .where('context_type', isEqualTo: contextType)
        .where('status', isEqualTo: 'completed')
        .orderBy('created_at', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
              final d = doc.data();
              return ContextGiftEntry(
                giftId: doc.id,
                senderId: (d['is_anonymous'] as bool? ?? false) ? null : d['sender_id'] as String?,
                giftEmoji: d['gift_emoji'] as String? ?? '💎',
                giftName: d['gift_name'] as String? ?? '',
                ncxAmount: (d['ncx_amount'] as num?)?.toInt() ?? 0,
                ugxEquivalent: (d['ugx_equivalent'] as num?)?.toInt() ?? 0,
                receiverNcx: (d['receiver_ncx'] as num?)?.toInt() ?? 0,
                isAnonymous: d['is_anonymous'] as bool? ?? false,
                isHighlighted: d['is_highlighted'] as bool? ?? false,
                createdAt: (d['created_at'] as Timestamp?)?.toDate(),
              );
            }).toList());
  }

  /// Gift totals/summary for a context.
  Future<ContextGiftTotals> getContextGiftTotals({
    required String contextId,
    required String contextType,
  }) async {
    try {
      final callable = _fn.httpsCallable('getContextGiftTotals');
      final result = await callable.call({
        'contextId': contextId,
        'contextType': contextType,
      });
      return ContextGiftTotals.fromMap(Map<String, dynamic>.from(result.data as Map));
    } catch (e) {
      debugPrint('🎁 getContextGiftTotals error: $e');
      return ContextGiftTotals.empty();
    }
  }

  // ── Leaderboards ─────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getTopGifters({int limit = 20}) async {
    try {
      final callable = _fn.httpsCallable('getTopGifters');
      final result = await callable.call({'limit': limit});
      return (result.data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      debugPrint('🎁 getTopGifters error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getTopReceivers({int limit = 20}) async {
    try {
      final callable = _fn.httpsCallable('getTopReceivers');
      final result = await callable.call({'limit': limit});
      return (result.data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      debugPrint('🎁 getTopReceivers error: $e');
      return [];
    }
  }

  // ── Streaks ───────────────────────────────────────────────────────────────

  /// Fetches the gift streak for the current user.
  Future<GiftStreak?> getMyStreak(String userId) async {
    try {
      final doc = await _db.collection('gift_streaks').doc(userId).get();
      if (!doc.exists) return null;
      return GiftStreak.fromMap(userId, doc.data()!);
    } catch (e) {
      debugPrint('🎁 getMyStreak error: $e');
      return null;
    }
  }

  // ── My gift history ───────────────────────────────────────────────────────

  /// Gifts sent by the user (read from vault_transactions for security).
  Stream<List<Map<String, dynamic>>> streamMySentGifts(String userId) {
    return _db
        .collection('vault_transactions')
        .where('user_id', isEqualTo: userId)
        .where('type', isEqualTo: 'gift_sent')
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  /// Gifts received by the user.
  Stream<List<Map<String, dynamic>>> streamMyReceivedGifts(String userId) {
    return _db
        .collection('vault_transactions')
        .where('user_id', isEqualTo: userId)
        .where('type', isEqualTo: 'gift_received')
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  // ── Local fallback catalogue ──────────────────────────────────────────────
  List<GiftItem> _localCatalogue() => const [
        GiftItem(id: 'rose',     name: 'Rose',        emoji: '🌹',  ncxValue: 1,     ugxValue: 100,    category: 'standard',  sortOrder: 1),
        GiftItem(id: 'clap',     name: 'Clap',        emoji: '👏',  ncxValue: 2,     ugxValue: 200,    category: 'standard',  sortOrder: 2),
        GiftItem(id: 'heart',    name: 'Heart',       emoji: '❤️',  ncxValue: 3,     ugxValue: 300,    category: 'standard',  sortOrder: 3),
        GiftItem(id: 'coffee',   name: 'Coffee',      emoji: '☕',  ncxValue: 5,     ugxValue: 500,    category: 'standard',  sortOrder: 4),
        GiftItem(id: 'star',     name: 'Star',        emoji: '⭐',  ncxValue: 5,     ugxValue: 500,    category: 'standard',  sortOrder: 5),
        GiftItem(id: 'fire',     name: 'Fire',        emoji: '🔥',  ncxValue: 10,    ugxValue: 1000,   category: 'standard',  sortOrder: 6),
        GiftItem(id: 'rocket',   name: 'Rocket',      emoji: '🚀',  ncxValue: 20,    ugxValue: 2000,   category: 'rare',      sortOrder: 10),
        GiftItem(id: 'crown',    name: 'Crown',       emoji: '👑',  ncxValue: 25,    ugxValue: 2500,   category: 'rare',      sortOrder: 11),
        GiftItem(id: 'diamond',  name: 'Diamond',     emoji: '💎',  ncxValue: 50,    ugxValue: 5000,   category: 'rare',      sortOrder: 12),
        GiftItem(id: 'trophy',   name: 'Trophy',      emoji: '🏆',  ncxValue: 50,    ugxValue: 5000,   category: 'rare',      sortOrder: 13),
        GiftItem(id: 'moneybag', name: 'Money Bag',   emoji: '💰',  ncxValue: 100,   ugxValue: 10000,  category: 'rare',      sortOrder: 14),
        GiftItem(id: 'sportscar',name: 'Sports Car',  emoji: '🏎️', ncxValue: 200,   ugxValue: 20000,  category: 'epic',      sortOrder: 20),
        GiftItem(id: 'yacht',    name: 'Yacht',       emoji: '⛵',  ncxValue: 300,   ugxValue: 30000,  category: 'epic',      sortOrder: 21),
        GiftItem(id: 'villa',    name: 'Villa',       emoji: '🏡',  ncxValue: 500,   ugxValue: 50000,  category: 'epic',      sortOrder: 22),
        GiftItem(id: 'jet',      name: 'Private Jet', emoji: '✈️',  ncxValue: 1000,  ugxValue: 100000, category: 'legendary', sortOrder: 30),
        GiftItem(id: 'palace',   name: 'NECXA Palace',emoji: '🏰',  ncxValue: 5000,  ugxValue: 500000, category: 'legendary', sortOrder: 31),
        GiftItem(id: 'galaxy',   name: 'Galaxy',      emoji: '🌌',  ncxValue: 10000, ugxValue: 1000000,category: 'legendary', sortOrder: 32),
      ];
}
