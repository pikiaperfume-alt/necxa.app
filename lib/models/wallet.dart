class Wallet {
  final String id;
  final String userId;
  final double fiatBalance;
  final double escrowBalance;
  final double coinBalance;
  final double stakedBalance;
  final double totalEarned;
  final double totalSpent;
  final double totalCommissionEarned;
  final int dailyWithdrawalLimit;
  final int monthlyWithdrawalLimit;
  final bool isFrozen;
  final String? freezeReason;
  final DateTime? frozenAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  Wallet({
    required this.id,
    required this.userId,
    required this.fiatBalance,
    required this.escrowBalance,
    required this.coinBalance,
    required this.stakedBalance,
    required this.totalEarned,
    required this.totalSpent,
    required this.totalCommissionEarned,
    required this.dailyWithdrawalLimit,
    required this.monthlyWithdrawalLimit,
    required this.isFrozen,
    this.freezeReason,
    this.frozenAt,
    required this.createdAt,
    required this.updatedAt,
  });

  static DateTime _parseDate(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is String) return DateTime.parse(value);
    if (value.runtimeType.toString() == 'Timestamp') return value.toDate(); // Handles Cloud Firestore Timestamp
    return DateTime.now();
  }

  factory Wallet.fromJson(Map<String, dynamic> json, {String? docId}) {
    return Wallet(
      id: docId ?? json['id'] ?? json['user_id'] ?? 'unknown',
      userId: json['user_id'] ?? 'unknown',
      fiatBalance: (json['fiat_balance'] as num?)?.toDouble() ?? 0.0,
      escrowBalance: (json['escrow_balance'] as num?)?.toDouble() ?? 0.0,
      coinBalance: (json['coin_balance'] as num?)?.toDouble() ?? 0.0,
      stakedBalance: (json['staked_balance'] as num?)?.toDouble() ?? 0.0,
      totalEarned: (json['total_earned'] as num?)?.toDouble() ?? 0.0,
      totalSpent: (json['total_spent'] as num?)?.toDouble() ?? 0.0,
      totalCommissionEarned: (json['total_commission_earned'] as num?)?.toDouble() ?? 0.0,
      dailyWithdrawalLimit: json['daily_withdrawal_limit'] ?? 5000000,
      monthlyWithdrawalLimit: json['monthly_withdrawal_limit'] ?? 50000000,
      isFrozen: json['is_frozen'] ?? false,
      freezeReason: json['freeze_reason'],
      frozenAt: json['frozen_at'] != null ? _parseDate(json['frozen_at']) : null,
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at'] ?? json['last_topup_at'] ?? json['last_sync_from_supabase']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'fiat_balance': fiatBalance,
      'escrow_balance': escrowBalance,
      'coin_balance': coinBalance,
      'staked_balance': stakedBalance,
      'is_frozen': isFrozen,
    };
  }
}
