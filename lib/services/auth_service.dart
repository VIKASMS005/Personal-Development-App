import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Stream<User?> authStateChanges() => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<User?> signInAnonymously() async {
    try {
      debugPrint('AuthService: signInAnonymously start');
      final cred = await _auth.signInAnonymously();
      debugPrint('AuthService: signInAnonymously done user=${cred.user}');
      return cred.user;
    } catch (e, st) {
      debugPrint('AuthService: signInAnonymously error: $e\n$st');
      rethrow;
    }
  }

  Future<User?> signInWithEmail(String email, String password) async {
    try {
      debugPrint('AuthService: signInWithEmail start for $email');
      final cred = await _auth.signInWithEmailAndPassword(
          email: email, password: password);
      debugPrint('AuthService: signInWithEmail done user=${cred.user}');
      return cred.user;
    } catch (e, st) {
      debugPrint('AuthService: signInWithEmail error: $e\n$st');
      rethrow;
    }
  }

  Future<User?> signUpWithEmail(String email, String password) async {
    try {
      debugPrint('AuthService: signUpWithEmail start for $email');
      final cred = await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
      debugPrint('AuthService: signUpWithEmail done user=${cred.user}');
      return cred.user;
    } catch (e, st) {
      debugPrint('AuthService: signUpWithEmail error: $e\n$st');
      rethrow;
    }
  }

  Future<User?> signInWithGoogle() async {
    try {
      debugPrint('AuthService: signInWithGoogle start');
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        debugPrint(
            'AuthService: signInWithGoogle cancelled by user (googleUser == null)');
        return null;
      }
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final res = await _auth.signInWithCredential(credential);
      debugPrint('AuthService: signInWithGoogle done user=${res.user}');
      return res.user;
    } catch (e, st) {
      debugPrint('AuthService: signInWithGoogle error: $e\n$st');
      rethrow;
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      debugPrint('AuthService: sendPasswordResetEmail start for $email');
      await _auth.sendPasswordResetEmail(email: email);
      debugPrint('AuthService: sendPasswordResetEmail done');
    } catch (e, st) {
      debugPrint('AuthService: sendPasswordResetEmail error: $e\n$st');
      rethrow;
    }
  }

  Future<void> deleteAccount() async {
    try {
      debugPrint('AuthService: deleteAccount start');
      final user = _auth.currentUser;
      if (user != null) {
        await user.delete();
      }
      debugPrint('AuthService: deleteAccount done');
    } catch (e, st) {
      debugPrint('AuthService: deleteAccount error: $e\n$st');
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      debugPrint('AuthService: signOut start');
      try {
        await GoogleSignIn().signOut();
      } catch (_) {}
      await _auth.signOut();
      debugPrint('AuthService: signOut done');
    } catch (e, st) {
      debugPrint('AuthService: signOut error: $e\n$st');
      rethrow;
    }
  }
}

