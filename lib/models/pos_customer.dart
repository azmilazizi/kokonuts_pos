class PosCustomer {
  const PosCustomer({
    required this.id,
    required this.name,
    required this.phone,
    required this.cashbackBalance,
  });

  final int id;
  final String name;
  final String phone;
  final double cashbackBalance;

  static PosCustomer? fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    if (rawId == null) return null;
    final id = rawId is int ? rawId : int.tryParse(rawId.toString());
    if (id == null) return null;
    return PosCustomer(
      id: id,
      name: json['name']?.toString() ?? 'No Name',
      phone: json['phone']?.toString() ?? '',
      cashbackBalance: double.tryParse(
            (json['cashback_balance'] ?? json['total_points'])?.toString() ?? '',
          ) ??
          0.0,
    );
  }
}
