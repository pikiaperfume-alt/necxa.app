import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

class FirebaseVaultService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  /// Fetches available coin packs from Firestore
  Future<List<Map<String, dynamic>>> fetchCoinPacks() async {
    try {
      final snapshot = await _firestore
          .collection('coin_packs')
          .where('is_active', isEqualTo: true)
          .orderBy('fiat_price', descending: false)
          .get();
      
      if (snapshot.docs.isEmpty) {
        return _seedCoinPacks();
      }
      
      return snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
    } catch (e) {
      debugPrint('🔥 Firebase Vault: Fetch Packs Error: $e');
      return [];
    }
  }

  /// Atomic transaction for buying coins via Cloud Functions
  Future<Map<String, dynamic>> buyCoins({
    required String userId,
    required String packId,
    required String paymentMethod, // 'apple_pay', 'google_pay', 'usdt_polygon', 'momo', 'airtel_money'
    required Map<String, dynamic> securityMetadata,
  }) async {
    try {
      final HttpsCallable callable = _functions.httpsCallable('buyCoins');
      final result = await callable.call({
        'packId': packId,
        'paymentMethod': paymentMethod,
        'securityMetadata': securityMetadata,
      });
      return Map<String, dynamic>.from(result.data);
    } catch (e) {
      debugPrint('🔥 Firebase Vault: Purchase Failure: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Atomic transaction for withdrawing fiat to mobile money or bank via Cloud Functions
  Future<Map<String, dynamic>> withdrawFiat({
    required String userId,
    required double amount,
    required String method, // 'mtn', 'airtel', 'card'
    required String accountNumber,
    required String recipientName,
    required String? totpToken,
    required String emailOtp,
    required Map<String, dynamic> securityMetadata,
  }) async {
    try {
      final HttpsCallable callable = _functions.httpsCallable('withdrawFiat');
      final result = await callable.call({
        'amount': amount,
        'method': method,
        'accountNumber': accountNumber,
        'recipientName': recipientName,
        'totpToken': totpToken,
        'emailOtp': emailOtp,
        'securityMetadata': securityMetadata,
      });
      return Map<String, dynamic>.from(result.data);
    } catch (e) {
      debugPrint('🔥 Firebase Vault: Withdrawal Failure: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> request2FASetup() async {
    try {
      final HttpsCallable callable = _functions.httpsCallable('request2FASetup');
      final result = await callable.call();
      return Map<String, dynamic>.from(result.data);
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> confirm2FASetup(String token) async {
    try {
      final HttpsCallable callable = _functions.httpsCallable('confirm2FASetup');
      final result = await callable.call({'token': token});
      return Map<String, dynamic>.from(result.data);
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> sendWithdrawalOTP() async {
    try {
      final HttpsCallable callable = _functions.httpsCallable('sendWithdrawalOTP');
      final result = await callable.call();
      return Map<String, dynamic>.from(result.data);
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> refreshForexRates() async {
    try {
      final HttpsCallable callable = _functions.httpsCallable('refreshForexRates');
      final result = await callable.call();
      return Map<String, dynamic>.from(result.data);
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }


  /// Initial seed for coin packs if the collection is empty
  Future<List<Map<String, dynamic>>> _seedCoinPacks() async {
    final packs = [
      {'ncx_amount': 100, 'fiat_price': 10000, 'label': 'Starter Pack', 'is_active': true},
      {'ncx_amount': 550, 'fiat_price': 50000, 'label': 'Pro Pack', 'is_active': true},
      {'ncx_amount': 1200, 'fiat_price': 100000, 'label': 'Elite Pack', 'is_active': true},
      {'ncx_amount': 6500, 'fiat_price': 500000, 'label': 'Whale Pack', 'is_active': true},
    ];

    for (var i = 0; i < packs.length; i++) {
      await _firestore.collection('coin_packs').doc('pack_$i').set(packs[i]);
    }
    
    return packs;
  }
}
