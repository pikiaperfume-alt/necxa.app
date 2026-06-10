import 'package:flutter/material.dart';

// ── Models ────────────────────────────────────────────────────

class Post {
  final String id,
      creatorId,
      creator,
      avatar,
      type,
      title,
      views,
      duration,
      grad;
  final int likes, comments, gifts, earned;
  final List<String> tags;
  final String timeAgo;
  final bool verified;

  const Post({
    required this.id,
    required this.creatorId,
    required this.creator,
    required this.avatar,
    required this.verified,
    required this.type,
    required this.title,
    required this.views,
    required this.likes,
    required this.comments,
    required this.gifts,
    required this.duration,
    required this.grad,
    required this.tags,
    required this.timeAgo,
    required this.earned,
  });
}

class Creator {
  final String id, name, username, avatar, followers, category, bio;
  final int totalEarned;
  final bool verified;

  const Creator({
    required this.id,
    required this.name,
    required this.username,
    required this.avatar,
    required this.followers,
    required this.verified,
    required this.category,
    required this.bio,
    required this.totalEarned,
  });
}

class Profile {
  final String id, username;
  final String? fullName, avatarUrl, bio;
  final bool verified, aiVerified;
  final DateTime createdAt;

  Profile({
    required this.id,
    required this.username,
    this.fullName,
    this.avatarUrl,
    this.bio,
    required this.verified,
    required this.aiVerified,
    required this.createdAt,
  });

  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
    id: m['id'],
    username: m['username'] ?? m['full_name']?.toLowerCase().replaceAll(' ', '_') ?? 'user_${m['id'].toString().substring(0, 4)}',
    fullName: m['full_name'] ?? 'Necxa User',
    avatarUrl: m['avatar_url'],
    bio: m['bio'],
    verified: m['verified'] ?? false,
    aiVerified: m['ai_verified'] ?? false,
    createdAt: m['created_at'] != null ? DateTime.parse(m['created_at']) : DateTime.now(),
  );
}

class Gift {
  final String id, emoji, name;
  final int price, fee;
  const Gift({
    required this.id,
    required this.emoji,
    required this.name,
    required this.price,
    required this.fee,
  });
}

class GiftPreset {
  final int id;
  final double ncxAmount;
  final String icon;
  final String label;
  final String? color;
  final int? order;

  GiftPreset({
    required this.id,
    required this.ncxAmount,
    required this.icon,
    required this.label,
    this.color,
    this.order,
  });

  factory GiftPreset.fromJson(Map<String, dynamic> json) {
    return GiftPreset(
      id: json['id'],
      ncxAmount: (json['ncx_amount'] as num).toDouble(),
      icon: json['icon'],
      label: json['label'],
      color: json['color'],
      order: json['order'],
    );
  }
}

class PaymentMethod {
  final String type;
  final String name;
  final String icon;
  final Color color;

  PaymentMethod(this.type, this.name, this.icon, this.color);
}

// ── Static Data ───────────────────────────────────────────────

// ── Helpers ───────────────────────────────────────────────────

const List<Gift> gifts = [
  Gift(id: 'g1', emoji: '🌹', name: 'Rose', price: 2000, fee: 400),
  Gift(id: 'g2', emoji: '🎵', name: 'Note', price: 5000, fee: 1000),
  Gift(id: 'g3', emoji: '🏆', name: 'Trophy', price: 10000, fee: 2000),
  Gift(id: 'g4', emoji: '💎', name: 'Diamond', price: 50000, fee: 10000),
  Gift(id: 'g5', emoji: '🚗', name: 'Benz', price: 100000, fee: 20000),
  Gift(id: 'g6', emoji: '✈️', name: 'Jet', price: 500000, fee: 100000),
  Gift(id: 'g7', emoji: '🏠', name: 'House', price: 1000000, fee: 200000),
  Gift(id: 'g8', emoji: '🌍', name: 'Universe', price: 5000000, fee: 1000000),
];

const List<Post> posts = [
  Post(id: 'p1', creatorId: 'c1', creator: 'Sheeba UG', avatar: '🎤', verified: true, type: 'music', title: 'Afrobeats Fusion – New Drop 🔥', views: '2.4M', likes: 184000, comments: 3200, gifts: 1240, duration: '3:42', grad: 'music', tags: ['#Afrobeats', '#Uganda', '#NewMusic'], timeAgo: '2h ago', earned: 3240000),
  Post(id: 'p2', creatorId: 'c2', creator: 'Kampala Art', avatar: '🎨', verified: false, type: 'art', title: 'Abstract East Africa – Limited Edition', views: '890K', likes: 62000, comments: 1100, gifts: 480, duration: '1:20', grad: 'art', tags: ['#Art', '#EastAfrica', '#NFT'], timeAgo: '5h ago', earned: 820000),
  Post(id: 'p3', creatorId: 'c3', creator: 'DJ Nexus 256', avatar: '🎧', verified: true, type: 'live', title: '🔴 LIVE: Friday Vibe Session', views: '14K', likes: 9200, comments: 740, gifts: 320, duration: 'LIVE', grad: 'live', tags: ['#Live', '#DJ', '#Kampala'], timeAgo: 'Now', earned: 1450000),
];

const List<Creator> creators = [
  Creator(id: 'c1', name: 'Sheeba UG', username: '@sheeba_ug', avatar: '🎤', followers: '2.4M', verified: true, category: 'Music', bio: 'Afrobeats queen. Top creator Uganda 2024.', totalEarned: 48000000),
  Creator(id: 'c2', name: 'Kampala Art', username: '@kampala_art', avatar: '🎨', followers: '890K', verified: false, category: 'Art', bio: 'Visual artist & digital creator.', totalEarned: 12000000),
  Creator(id: 'c3', name: 'DJ Nexus 256', username: '@djnexus256', avatar: '🎧', followers: '1.1M', verified: true, category: 'Music', bio: 'East Africa\'s top DJ. Kampala nights.', totalEarned: 31000000),
];

// ── Helpers ───────────────────────────────────────────────────
String ugx(num n) {
  // 1. Convert to integer to strip decimals
  final int val = n.toInt();
  final String s = val.toString();
  final buf = StringBuffer();
  
  for (int i = 0; i < s.length; i++) {
    int revPos = s.length - i;
    if (i > 0 && revPos % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return 'UGX $buf';
}

String kNum(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}K';
  return n.toString();
}
