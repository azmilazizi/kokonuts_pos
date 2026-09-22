class Reminder {
  const Reminder({
    required this.id,
    required this.itemLabel,
    required this.reason,
    required this.createdAt,
  });

  final String id;
  final String itemLabel;
  final String reason;
  final DateTime createdAt;

  factory Reminder.fromJson(Map<String, dynamic> json) => Reminder(
        id: json['id']?.toString() ?? '',
        itemLabel: json['item_label']?.toString() ?? '',
        reason: json['reason']?.toString() ?? '',
        createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
            DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'item_label': itemLabel,
        'reason': reason,
        'created_at': createdAt.toIso8601String(),
      };
}
