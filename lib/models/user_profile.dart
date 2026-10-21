import 'package:flutter/material.dart';

/// Preset avatar colors users can choose from.
const kAvatarColors = [
  Color(0xFF00D4FF),
  Color(0xFF7B2FF7),
  Color(0xFFFF2D95),
  Color(0xFF00E676),
  Color(0xFFFF6B35),
  Color(0xFF448AFF),
];

/// Preset avatar icons users can choose from.
const kAvatarIcons = [
  Icons.person,
  Icons.face,
  Icons.emoji_people,
  Icons.account_circle,
  Icons.supervised_user_circle,
  Icons.manage_accounts,
];

/// A local user profile stored on-device.
class UserProfile {
  final String id;
  final String name;
  final Color avatarColor;
  final IconData avatarIcon;
  final int totalAnalyses;
  final int fakeDetections;
  final DateTime createdAt;
  final String? profilePicturePath; // path to user-uploaded photo

  const UserProfile({
    required this.id,
    required this.name,
    required this.avatarColor,
    required this.avatarIcon,
    this.totalAnalyses = 0,
    this.fakeDetections = 0,
    required this.createdAt,
    this.profilePicturePath,
  });

  int get realDetections => totalAnalyses - fakeDetections;

  double get fakePercent =>
      totalAnalyses == 0 ? 0.0 : (fakeDetections / totalAnalyses) * 100;

  double get realPercent =>
      totalAnalyses == 0 ? 0.0 : (realDetections / totalAnalyses) * 100;

  UserProfile copyWith({
    String? id,
    String? name,
    Color? avatarColor,
    IconData? avatarIcon,
    int? totalAnalyses,
    int? fakeDetections,
    DateTime? createdAt,
    String? profilePicturePath,
  }) {
    return UserProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarColor: avatarColor ?? this.avatarColor,
      avatarIcon: avatarIcon ?? this.avatarIcon,
      totalAnalyses: totalAnalyses ?? this.totalAnalyses,
      fakeDetections: fakeDetections ?? this.fakeDetections,
      createdAt: createdAt ?? this.createdAt,
      profilePicturePath: profilePicturePath ?? this.profilePicturePath,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'avatarColorValue': avatarColor.toARGB32(),
        'avatarIconCodePoint': avatarIcon.codePoint,
        'avatarIconFontFamily': avatarIcon.fontFamily ?? 'MaterialIcons',
        'totalAnalyses': totalAnalyses,
        'fakeDetections': fakeDetections,
        'createdAt': createdAt.toIso8601String(),
        'profilePicturePath': profilePicturePath,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      avatarColor: Color(json['avatarColorValue'] as int),
      // Reconstruct from the const preset list rather than calling the
      // non-const IconData() constructor. This keeps release icon-font
      // tree-shaking enabled (avoids the build warning) and stays
      // backward-compatible with saved profiles (still keyed on codePoint).
      avatarIcon: kAvatarIcons.firstWhere(
        (i) => i.codePoint == json['avatarIconCodePoint'],
        orElse: () => kAvatarIcons.first,
      ),
      totalAnalyses: json['totalAnalyses'] as int? ?? 0,
      fakeDetections: json['fakeDetections'] as int? ?? 0,
      createdAt: DateTime.parse(json['createdAt'] as String),
      profilePicturePath: json['profilePicturePath'] as String?,
    );
  }
}
