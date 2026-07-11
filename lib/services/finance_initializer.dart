import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:necxa_flutter/firebase_options.dart'; // Assuming you have this from `flutterfire configure`

/// A singleton service to lazily initialize the financial backends (Firebase & Supabase).
/// This ensures that resources are only allocated when a user first interacts
/// with a Necxa Finance feature.
class FinanceInitializer {
  static final FinanceInitializer instance = FinanceInitializer._internal();
  FinanceInitializer._internal();

  bool _isInitialized = false;

  /// Ensures that Firebase and Supabase are initialized.
  /// This method is safe to call multiple times; it will only run the
  /// initialization logic once.
  Future<void> ensureInitialized() async {
    if (_isInitialized) {
      return;
    }

    debugPrint("🚀 Lazily initializing Necxa Finance Engine...");

    // Initialize Supabase - Move your keys from main.dart here
    await Supabase.initialize(
      url: 'YOUR_SUPABASE_URL', // Add your Supabase URL
      anonKey: 'YOUR_SUPABASE_ANON_KEY', // Add your Supabase Anon Key
    );

    // Initialize Firebase
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

    _isInitialized = true;
    debugPrint("✅ Necxa Finance Engine is active.");
  }
}