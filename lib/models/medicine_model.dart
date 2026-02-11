/// Data model for a medicine entry.
class MedicineModel {
  final String id;
  final String name;
  final String detail;
  final String image; // asset path or base64 string
  final bool beforeMeal;
  final bool afterMeal;
  final String createby; // username of creator
  final String createdAt;

  const MedicineModel({
    required this.id,
    required this.name,
    this.detail = '',
    this.image = 'assets/pill/p_1.png',
    this.beforeMeal = true,
    this.afterMeal = false,
    required this.createby,
    this.createdAt = '',
  });

  /// Whether this image is a built-in asset (not base64).
  bool get isAssetImage => image.startsWith('assets/');

  /// Create from a SQLite row map.
  factory MedicineModel.fromMap(Map<String, dynamic> map) {
    return MedicineModel(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      detail: (map['detail'] ?? '').toString(),
      image: (map['image'] ?? 'assets/pill/p_1.png').toString(),
      beforeMeal: map['before_meal'] == 1,
      afterMeal: map['after_meal'] == 1,
      createby: (map['createby'] ?? '').toString(),
      createdAt: (map['created_at'] ?? '').toString(),
    );
  }

  /// Convert to a SQLite row map.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'detail': detail,
      'image': image,
      'before_meal': beforeMeal ? 1 : 0,
      'after_meal': afterMeal ? 1 : 0,
      'createby': createby,
      'created_at': createdAt,
    };
  }

  MedicineModel copyWith({
    String? id,
    String? name,
    String? detail,
    String? image,
    bool? beforeMeal,
    bool? afterMeal,
    String? createby,
    String? createdAt,
  }) {
    return MedicineModel(
      id: id ?? this.id,
      name: name ?? this.name,
      detail: detail ?? this.detail,
      image: image ?? this.image,
      beforeMeal: beforeMeal ?? this.beforeMeal,
      afterMeal: afterMeal ?? this.afterMeal,
      createby: createby ?? this.createby,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
