import 'dart:convert';

class UserProfile {
  final String uid;
  final String email;
  final String name;
  final String bio;
  final String phoneNumber;
  final String? photoPath;
  final List<String> focusAreas;
  final DateTime updatedAt;
  final bool isSynced;

  UserProfile({
    required this.uid,
    this.email = '',
    this.name = '',
    this.bio = '',
    this.phoneNumber = '',
    this.photoPath,
    this.focusAreas = const [],
    DateTime? updatedAt,
    this.isSynced = false,
  }) : updatedAt = updatedAt ?? DateTime.now();

  UserProfile copyWith({
    String? uid,
    String? email,
    String? name,
    String? bio,
    String? phoneNumber,
    String? photoPath,
    List<String>? focusAreas,
    DateTime? updatedAt,
    bool? isSynced,
  }) {
    return UserProfile(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      name: name ?? this.name,
      bio: bio ?? this.bio,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      photoPath: photoPath ?? this.photoPath,
      focusAreas: focusAreas ?? this.focusAreas,
      updatedAt: updatedAt ?? this.updatedAt,
      isSynced: isSynced ?? this.isSynced,
    );
  }


  Map<String, dynamic> toMap() => {
        'uid': uid,
        'email': email,
        'name': name,
        'bio': bio,
        'phoneNumber': phoneNumber,
        'photoPath': photoPath,
        'focusAreas': focusAreas,
        'updatedAt': updatedAt.toIso8601String(),
        'isSynced': isSynced ? 1 : 0,
      };

  factory UserProfile.fromMap(Map<String, dynamic> m) {
    List<String> parsedFocus = [];
    if (m['focusAreas'] != null) {
      if (m['focusAreas'] is List) {
        parsedFocus = List<String>.from(m['focusAreas']);
      } else if (m['focusAreas'] is String) {
        try {
          parsedFocus = List<String>.from(jsonDecode(m['focusAreas']));
        } catch (_) {}
      }
    }
    return UserProfile(
      uid: m['uid'] ?? '',
      email: m['email'] ?? '',
      name: m['name'] ?? '',
      bio: m['bio'] ?? '',
      phoneNumber: m['phoneNumber'] ?? '',
      photoPath: m['photoPath'],
      focusAreas: parsedFocus,
      updatedAt: m['updatedAt'] != null
          ? DateTime.tryParse(m['updatedAt']) ?? DateTime.now()
          : DateTime.now(),
      isSynced: (m['isSynced'] == 1 || m['isSynced'] == true),
    );
  }

  Map<String, dynamic> toSqliteMap() => {
        'uid': uid,
        'email': email,
        'name': name,
        'bio': bio,
        'phone_number': phoneNumber,
        'photo_path': photoPath,
        'focus_areas': jsonEncode(focusAreas),
        'updated_at': updatedAt.toIso8601String(),
        'is_synced': isSynced ? 1 : 0,
      };
}

