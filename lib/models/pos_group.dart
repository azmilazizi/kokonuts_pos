class PosGroup {
  const PosGroup({required this.id, required this.name});

  final String id;
  final String name;

  static PosGroup? fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString();
    final name = (json['sub_group_name'] as String?)?.trim();
    if (id == null || id.isEmpty || name == null || name.isEmpty) return null;
    return PosGroup(id: id, name: name);
  }
}
