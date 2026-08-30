import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../services/database_service.dart';

class ProfileProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService.instance;
  UserProfile? _profile;

  UserProfile? get profile => _profile;
  String get displayName => _profile?.name.isNotEmpty == true
      ? _profile!.name
      : (_profile?.email.isNotEmpty == true
          ? _profile!.email.split('@').first
          : 'Champion');

  Future<void> loadProfile(String uid, {String? email, String? displayName}) async {
    var p = await _db.getProfile(uid);
    if (p == null) {
      p = UserProfile(
        uid: uid,
        email: email ?? 'user@grow.local',
        name: displayName ?? 'Grow Champion',
        bio: 'Self-discipline and continuous personal growth.',
      );
      await _db.saveProfile(p);
    }
    _profile = p;
    notifyListeners();
  }

  Future<void> updateProfile({
    required String name,
    required String bio,
    required String phone,
    String? photoPath,
  }) async {
    if (_profile == null) return;
    final updated = _profile!.copyWith(
      name: name,
      bio: bio,
      phoneNumber: phone,
      photoPath: photoPath ?? _profile!.photoPath,
      updatedAt: DateTime.now(),
    );
    _profile = updated;
    await _db.saveProfile(updated);
    notifyListeners();
  }

  Future<void> updatePhoto(String photoPath) async {
    if (_profile == null) return;
    final updated = _profile!.copyWith(
      photoPath: photoPath,
      updatedAt: DateTime.now(),
    );
    _profile = updated;
    await _db.saveProfile(updated);
    notifyListeners();
  }

  void clear() {
    _profile = null;
    notifyListeners();
  }
}
