import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';

class AuthProvider extends ChangeNotifier {
  static const String _defaultUid = 'local_user';
  static const String _uidKey = 'grow_local_user_uid';
  
  String? _uid;
  bool _isLoading = true;

  AuthProvider() {
    _init();
  }

  String? get uid => _uid;
  bool get isAuthenticated => _uid != null;
  bool get isLoading => _isLoading;

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _uid = prefs.getString(_uidKey) ?? _defaultUid;
    await prefs.setString(_uidKey, _uid!);
    _isLoading = false;
    notifyListeners();
  }

  Future<void> resetAllLocalData() async {
    final currentUid = _uid ?? _defaultUid;
    // 1. Cancel all active local notifications and alarms
    await NotificationService.cancelAll();

    // 2. Clear all local storage records for this user from SQLite
    await DatabaseService.instance.clearLocalUserData(currentUid);

    // 3. Reset local user ID
    final prefs = await SharedPreferences.getInstance();
    _uid = _defaultUid;
    await prefs.setString(_uidKey, _defaultUid);
    notifyListeners();
  }
}
