import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../services/database_service.dart';

class ProfileProvider extends ChangeNotifier {
  static const _oldDefaultEmail = 'user@grow.local';
  static const _oldDefaultName = 'Grow Champion';
  static const _oldDefaultBio = 'Self-discipline and continuous personal growth.';

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
      // A new profile starts empty. Made-up values ("Grow Champion",
      // user@grow.local, a stock bio) used to be saved as if the user had
      // entered them, and were shown and given to the AI as real details.
      p = UserProfile(
        uid: uid,
        email: email ?? '',
        name: displayName ?? '',
        bio: '',
      );
      await _db.saveProfile(p);
    } else if (p.email == _oldDefaultEmail ||
        p.name == _oldDefaultName ||
        p.bio == _oldDefaultBio) {
      // Clear those old stand-ins wherever the user never replaced them.
      p = p.copyWith(
        email: p.email == _oldDefaultEmail ? '' : p.email,
        name: p.name == _oldDefaultName ? '' : p.name,
        bio: p.bio == _oldDefaultBio ? '' : p.bio,
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
