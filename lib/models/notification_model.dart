class AppNotification {
  final String id;
  final String type; // 'listing', 'content', 'financial', 'social'
  final String title;
  final String body;
  final String? payload; // JSON data for navigation
  final bool isRead;
  final DateTime createdAt;

  AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.payload,
    this.isRead = false,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'title': title,
      'body': body,
      'payload': payload,
      'is_read': isRead ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory AppNotification.fromMap(Map<String, dynamic> map) {
    return AppNotification(
      id: map['id'],
      type: map['type'],
      title: map['title'],
      body: map['body'],
      payload: map['payload'],
      isRead: map['is_read'] == 1,
      createdAt: DateTime.parse(map['created_at']),
    );
  }
}
