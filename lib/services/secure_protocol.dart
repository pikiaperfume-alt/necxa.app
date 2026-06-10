import 'dart:convert';

/// ── Necxa Secure Protocol (E2EE Simulation) ──────────────────────────
/// This service provides end-to-end encryption for chat messages and media URLs,
/// ensuring that the backend only acts as a blind relay.
class SecureProtocol {
  /// Simple Base64 + XOR scrambling for the pitch demonstration of E2EE.
  /// In a production environment, this would be replaced with AES-256 or Signal Protocol.
  static String encrypt(String plainText, String key) {
    if (plainText.isEmpty) return '';
    
    // 1. Convert to bytes
    final bytes = utf8.encode(plainText);
    final keyBytes = utf8.encode(key);
    
    // 2. XOR scramble
    final scrambled = List<int>.generate(bytes.length, (i) {
      return bytes[i] ^ keyBytes[i % keyBytes.length];
    });
    
    // 3. Encode to Base64 to safely transport through the relay
    return base64Encode(scrambled);
  }

  static String decrypt(String? encryptedText, String key) {
    if (encryptedText == null || encryptedText.isEmpty) return '';
    
    try {
      // 1. Decode from Base64
      final bytes = base64Decode(encryptedText);
      final keyBytes = utf8.encode(key);
      
      // 2. XOR unscramble
      final unscrambled = List<int>.generate(bytes.length, (i) {
        return bytes[i] ^ keyBytes[i % keyBytes.length];
      });
      
      // 3. Convert back to string
      return utf8.decode(unscrambled);
    } catch (e) {
      // If decryption fails, return the original text (fallback for unencrypted legacy messages)
      return encryptedText;
    }
  }

  /// Generates a "Secure Handshake" visual for the UI
  static String getHandshakeStatus(String roomId) {
    final shortId = roomId.substring(0, 8).toUpperCase();
    return 'NECX-$shortId-SECURE';
  }
}
