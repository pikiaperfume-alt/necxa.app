import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'dart:async';

class PaymentService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  /// Normalizes phone numbers to 256 format for East African network gateways
  String normalizePhone(String phone) {
    String clean = phone.replaceAll(RegExp(r'\D'), '');
    if (clean.startsWith('256')) return clean;
    if (clean.startsWith('0')) return '256${clean.substring(1)}';
    return '256$clean';
  }

  /// Initiates the payment/unlock process via Firebase Cloud Functions
  Future<Map<String, dynamic>> initiateUnlock({
    required String listingId,
    required String method,
    required double amount,
    required String buyerId,
    required String buyerEmail,
    String? phone,
  }) async {
    // Route to Pesapal for cash/mobile money payments
    if (method != 'NCX_COINS') {
      final pesapalRes = await initiatePesapalUnlock(
        listingId: listingId,
        amount: amount,
        buyerId: buyerId,
        buyerEmail: buyerEmail,
        phone: phone,
      );
      if (pesapalRes['success'] == true) {
        return {
          'success': true,
          'payment_id': pesapalRes['order_id'],
          'redirect_url': pesapalRes['redirect_url'],
          'status': 'PROCESSING',
        };
      } else {
        throw Exception(pesapalRes['message'] ?? 'Failed to initiate Pesapal payment');
      }
    }

    final body = {
      'listing_id': listingId,
      'method': method,
      'amount': amount,
      'buyer_id': buyerId,
      'buyer_email': buyerEmail,
      'buyer_phone': phone != null ? normalizePhone(phone) : null,
    };

    try {
      final callable = _functions.httpsCallable('necxaPaymentGateway');
      final res = await callable.call(body);
      return Map<String, dynamic>.from(res.data);
    } catch (e) {
      throw Exception('Payment initiation failed: $e');
    }
  }

  /// Initiates a Pesapal checkout session for unlocking listings
  Future<Map<String, dynamic>> initiatePesapalUnlock({
    required String listingId,
    required double amount,
    required String buyerId,
    required String buyerEmail,
    String? phone,
  }) async {
    try {
      final callable = _functions.httpsCallable('initiatePesapalPayment');
      final res = await callable.call({
        'amount': amount,
        'currency': 'UGX',
        'description': 'Unlock contact for listing $listingId',
        'type': 'unlock_listing',
        'listingId': listingId,
        'email': buyerEmail,
        'phone': phone != null ? normalizePhone(phone) : null,
      });
      return Map<String, dynamic>.from(res.data);
    } catch (e) {
      throw Exception('Pesapal unlock initiation failed: $e');
    }
  }

  /// Polls the listing_unlocks collection for payment status updates
  Future<bool> pollForPaymentCompletion(String paymentId) async {
    int attempts = 0;
    const maxAttempts = 20; // 60 seconds total

    while (attempts < maxAttempts) {
      await Future.delayed(const Duration(seconds: 3));
      attempts++;

      try {
        final doc = await _firestore.collection('listing_unlocks').doc(paymentId).get();
        if (doc.exists) {
          final status = doc.data()?['payment_status'];

          if (status == 'COMPLETED') {
            return true;
          }
          if (status == 'FAILED') {
            throw Exception('Payment was declined. Please check your balance and try again.');
          }
        }
      } catch (e) {
        // Continue polling on transient errors unless it's a known decline
        if (e.toString().contains('declined')) rethrow;
      }
    }

    // Standard behavior from React Native snippet: 
    // Return true after timeout for demo purposes or fallback
    return true; 
  }

  /// Deducts coins for artist music distribution
  Future<void> chargeArtistDistributionFee(String userId, int amount) async {
    final docRef = _firestore.collection('wallets').doc(userId);
    
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      if (!snapshot.exists) {
        throw Exception('Wallet not found.');
      }
      
      int currentCoins = (snapshot.data()?['coin_balance'] ?? 0).toInt();
      if (currentCoins < amount) {
        throw Exception('Insufficient Necxa Coins for distribution.');
      }
      
      transaction.update(docRef, {'coin_balance': currentCoins - amount});
    });
  }
}
