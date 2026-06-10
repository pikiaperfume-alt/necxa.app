class VirtualTourBooking {
  final String id;
  final String propertyId;
  final String buyerId;
  final String? agentId;
  final DateTime scheduledFor;
  final String? meetLink;
  final String status; // pending, confirmed, completed, cancelled
  final bool buyerConfirmed;
  final bool agentConfirmed;
  final DateTime? tourCompletedAt;
  final int? buyerRating;
  final String? buyerFeedback;
  final DateTime createdAt;

  VirtualTourBooking({
    required this.id,
    required this.propertyId,
    required this.buyerId,
    this.agentId,
    required this.scheduledFor,
    this.meetLink,
    required this.status,
    this.buyerConfirmed = false,
    this.agentConfirmed = false,
    this.tourCompletedAt,
    this.buyerRating,
    this.buyerFeedback,
    required this.createdAt,
  });

  factory VirtualTourBooking.fromJson(Map<String, dynamic> json) {
    return VirtualTourBooking(
      id: json['id'],
      propertyId: json['property_id'],
      buyerId: json['buyer_id'],
      agentId: json['agent_id'],
      scheduledFor: DateTime.parse(json['scheduled_for']),
      meetLink: json['meet_link'],
      status: json['status'] ?? 'pending',
      buyerConfirmed: json['buyer_confirmed'] ?? false,
      agentConfirmed: json['agent_confirmed'] ?? false,
      tourCompletedAt: json['tour_completed_at'] != null ? DateTime.parse(json['tour_completed_at']) : null,
      buyerRating: json['buyer_rating'],
      buyerFeedback: json['buyer_feedback'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}
