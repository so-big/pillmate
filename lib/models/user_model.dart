/// Data model for a user account (master or sub-profile).
class UserModel {
  final String userid;
  final String password; // SHA-256 hashed
  final String imageBase64;
  final String subProfile; // empty string for master accounts
  final String info;
  final String securityQuestion;
  final String securityAnswer;
  final String breakfast; // "HH:mm"
  final String lunch;
  final String dinner;
  final String bedtime; // "HH:mm" — ก่อนนอน
  final bool isBedtimeEnabled;
  final String createdAt;

  const UserModel({
    required this.userid,
    required this.password,
    this.imageBase64 = '',
    this.subProfile = '',
    this.info = '',
    this.securityQuestion = '',
    this.securityAnswer = '',
    this.breakfast = '06:00',
    this.lunch = '12:00',
    this.dinner = '18:00',
    this.bedtime = '22:00',
    this.isBedtimeEnabled = false,
    this.createdAt = '',
  });

  /// Whether this user is a master (main) account.
  bool get isMaster => subProfile.isEmpty;

  /// Create from a SQLite row map.
  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      userid: (map['userid'] ?? '').toString(),
      password: (map['password'] ?? '').toString(),
      imageBase64: (map['image_base64'] ?? '').toString(),
      subProfile: (map['sub_profile'] ?? '').toString(),
      info: (map['info'] ?? '').toString(),
      securityQuestion: (map['security_question'] ?? '').toString(),
      securityAnswer: (map['security_answer'] ?? '').toString(),
      breakfast: (map['breakfast'] ?? '06:00').toString(),
      lunch: (map['lunch'] ?? '12:00').toString(),
      dinner: (map['dinner'] ?? '18:00').toString(),
      bedtime: (map['bedtime'] ?? '22:00').toString(),
      isBedtimeEnabled: (map['is_bedtime_enabled'] == 1 || map['is_bedtime_enabled'] == true),
      createdAt: (map['created_at'] ?? '').toString(),
    );
  }

  /// Convert to a SQLite row map.
  Map<String, dynamic> toMap() {
    return {
      'userid': userid,
      'password': password,
      'image_base64': imageBase64,
      'sub_profile': subProfile,
      'info': info,
      'security_question': securityQuestion,
      'security_answer': securityAnswer,
      'breakfast': breakfast,
      'lunch': lunch,
      'dinner': dinner,
      'bedtime': bedtime,
      'is_bedtime_enabled': isBedtimeEnabled ? 1 : 0,
      'created_at': createdAt,
    };
  }

  /// Create a copy with some fields changed.
  UserModel copyWith({
    String? userid,
    String? password,
    String? imageBase64,
    String? subProfile,
    String? info,
    String? securityQuestion,
    String? securityAnswer,
    String? breakfast,
    String? lunch,
    String? dinner,
    String? bedtime,
    bool? isBedtimeEnabled,
    String? createdAt,
  }) {
    return UserModel(
      userid: userid ?? this.userid,
      password: password ?? this.password,
      imageBase64: imageBase64 ?? this.imageBase64,
      subProfile: subProfile ?? this.subProfile,
      info: info ?? this.info,
      securityQuestion: securityQuestion ?? this.securityQuestion,
      securityAnswer: securityAnswer ?? this.securityAnswer,
      breakfast: breakfast ?? this.breakfast,
      lunch: lunch ?? this.lunch,
      dinner: dinner ?? this.dinner,
      bedtime: bedtime ?? this.bedtime,
      isBedtimeEnabled: isBedtimeEnabled ?? this.isBedtimeEnabled,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
