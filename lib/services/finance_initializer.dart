import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:necxa_flutter/firebase_options.dart'; // Assuming you have this from `flutterfire configure`

/// A singleton service to lazily initialize the financial backends (Firebase & Supabase).
/// This ensures that resources are only allocated when a user first interacts
/// with a Necxa Finance feature.
class FinanceInitializer {
  static final FinanceInitializer instance = FinanceInitializer._internal();
  FinanceInitializer._internal();

  bool _isInitialized = false;

  /// Ensures that Firebase is initialized and that the app is signed in
  /// with Firebase Authentication. This is required for callable functions.
  Future<void> ensureInitialized() async {
    if (_isInitialized) {
      return;
    }

    debugPrint("🚀 Lazily initializing Necxa Finance Engine...");

    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    }

    if (FirebaseAuth.instance.currentUser == null) {
      try {
        final credential = await FirebaseAuth.instance.signInAnonymously();
        debugPrint('🔥 Firebase anonymous sign-in successful: ${credential.user?.uid}');
      } catch (e) {
        debugPrint('🔥 Firebase anonymous sign-in failed: $e');
        rethrow;
      }
    }

    _isInitialized = true;
    debugPrint("✅ Necxa Finance Engine is active.");
  }
}