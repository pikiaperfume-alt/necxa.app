import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'finance_initializer.dart';

/// WalletService
///
/// Handles all financial operations related to the user's wallet, including
/// fetching balances and initiating coin purchases. This service communicates
/// directly with your backend (Firebase Functions and Supabase).
class WalletService {
  // Services are no longer stored as final members, but retrieved on-demand
  // after ensuring initialization.
  WalletService();

  // Helper to get initialized clients lazily.
  Future<SupabaseClient> _getSupabaseClient() async {
    await FinanceInitializer.instance.ensureInitialized();
    return Supabase.instance.client;
  }

  Future<FirebaseFunctions> _getFirebaseFunctions() async {
    await FinanceInitializer.instance.ensureInitialized();
    return FirebaseFunctions.instance;
  }

  /// Fetches the user's complete wallet details from the Supabase `wallets` table.
  ///
  /// Returns a map containing fiat_balance, coin_balance, and escrow_balance.
  Future<Map<String, dynamic>> getWalletDetails() async {
    final supabase = await _getSupabaseClient();
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('User not authenticated.');
    }

    try {
      final data = await supabase
          .from('wallets')
          .select('fiat_balance, coin_balance, escrow_balance')
          .eq('user_id', userId)
          .single();

      return data;
    } catch (e) {
      debugPrint('Error fetching wallet details: $e');
      // Return a default empty state on error
      return {
        'fiat_balance': 0,
        'coin_balance': 0,
        'escrow_balance': 0,
      };
    }
  }

  /// Initiates the purchase of a coin pack.
  ///
  /// This function calls the unified `purchaseCoins` Firebase Cloud Function,
  /// which then orchestrates the transaction with the Supabase backend.
  ///
  /// [method] can be 'FIAT_BALANCE' or 'PESAPAL'.
  /// [packId] is the document ID of the coin pack from the `coin_packs` collection.
  Future<PurchaseResult> purchaseCoins({
    required String method,
    required String packId,
  }) async {
    try {
      final firebaseFunctions = await _getFirebaseFunctions();
      final HttpsCallable callable = firebaseFunctions.httpsCallable('purchaseCoins');

      final response = await callable.call<Map<String, dynamic>>({
        'method': method,
        'packId': packId,
      });

      final data = response.data;

      if (data['success'] == true) {
        // For Pesapal, the redirect_url will be in the data
        return PurchaseResult.success(
          message: data['message'],
          redirectUrl: data['redirect_url'],
        );
      } else {
        return PurchaseResult.failure(
            data['message'] ?? 'An unknown error occurred.');
      }
    } on FirebaseFunctionsException catch (e) {
      debugPrint('Firebase Functions Error calling purchaseCoins: ${e.message}');
      return PurchaseResult.failure(e.message ?? 'A server error occurred.');
    } catch (e) {
      debugPrint('Generic Error in purchaseCoins: $e');
      return PurchaseResult.failure('An unexpected error occurred.');
    }
  }

  /// Sends a virtual gift from the current user to a receiver.
  ///
  /// This function calls the `processGift` Firebase Cloud Function. If the user
  /// has insufficient funds, the returned [GiftResult] will indicate failure
  /// with a specific reason, allowing the UI to prompt a coin purchase.
  Future<GiftResult> sendGift({
    required String receiverId,
    required String postId,
    required String giftItemId,
    required int ncxAmount,
    String? contextNote,
    bool isAnonymous = false,
  }) async {
    final supabase = await _getSupabaseClient();
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      return GiftResult.failure('You must be logged in to send a gift.');
    }
    if (userId == receiverId) {
      return GiftResult.failure('You cannot send a gift to yourself.');
    }

    try {
      final firebaseFunctions = await _getFirebaseFunctions();
      final HttpsCallable callable = firebaseFunctions.httpsCallable('processGift');

      final response = await callable.call<Map<String, dynamic>>({
        'receiverId': receiverId,
        'postId': postId,
        'giftItemId': giftItemId,
        'ncxAmount': ncxAmount,
        'contextType': 'creator_post', // Or other contexts
        'contextNote': contextNote,
        'isAnonymous': isAnonymous,
      });

      final data = response.data;
      if (data['success'] == true) {
        return GiftResult.success(data['message'] ?? 'Gift sent successfully!');
      } else {
        return GiftResult.failure(data['message'] ?? 'An unknown error occurred.');
      }
    } on FirebaseFunctionsException catch (e) {
      debugPrint('Firebase Functions Error calling processGift: ${e.code} - ${e.message}');
      // This is the key part for the UI flow
      if (e.code == 'resource-exhausted') {
        return GiftResult.insufficientFunds(e.message ?? 'Insufficient NCX balance.');
      }
      return GiftResult.failure(e.message ?? 'A server error occurred.');
    } catch (e) {
      debugPrint('Generic Error in sendGift: $e');
      return GiftResult.failure('An unexpected error occurred.');
    }
  }

  /// Liquidates a specified amount of NCX coins into the user's fiat balance.
  ///
  /// Calls the `liquidateCoins` Firebase Cloud Function and handles the response.
  /// Requires 2FA if enabled by the user.
  Future<LiquidationResult> liquidateCoins({
    required int ncxAmount,
    required Map<String, dynamic> securityMetadata, // For location, device ID etc.
  }) async {
    if (ncxAmount <= 0) {
      return LiquidationResult.failure("Amount must be greater than zero.");
    }

    try {
      final firebaseFunctions = await _getFirebaseFunctions();
      final HttpsCallable callable = firebaseFunctions.httpsCallable('liquidateCoins');

      final response = await callable.call<Map<String, dynamic>>({
        'ncxAmount': ncxAmount,
        'securityMetadata': securityMetadata,
      });

      final data = response.data;
      if (data['success'] == true) {
        return LiquidationResult.success(
          message: data['message'] ?? 'Liquidation successful.',
          ugxReceived: data['ugxReceived']?.toDouble() ?? 0.0,
          ncxBurned: data['ncxBurned']?.toDouble() ?? 0.0,
        );
      } else {
        return LiquidationResult.failure(
            data['message'] ?? 'An unknown error occurred.');
      }
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
          'Firebase Functions Error calling liquidateCoins: ${e.code} - ${e.message}');
      // The backend throws 'failed-precondition' for insufficient balance
      if (e.code == 'failed-precondition') {
        return LiquidationResult.failure(
            e.message ?? 'Insufficient NCX balance.');
      }
      return LiquidationResult.failure(e.message ?? 'A server error occurred.');
    } catch (e) {
      debugPrint('Generic Error in liquidateCoins: $e');
      return LiquidationResult.failure('An unexpected error occurred.');
    }
  }
}

/// A result class to handle the outcomes of a purchase attempt.
class PurchaseResult {
  final bool isSuccess;
  final String message;
  final String? redirectUrl; // For external payment gateways like Pesapal

  PurchaseResult.success({required this.message, this.redirectUrl})
      : isSuccess = true;

  PurchaseResult.failure(this.message)
      : isSuccess = false,
        redirectUrl = null;
}

/// A result class to handle the outcomes of a gifting attempt.
class GiftResult {
  final bool isSuccess;
  final String message;
  final bool needsTopUp;

  GiftResult.success(this.message)
      : isSuccess = true,
        needsTopUp = false;

  GiftResult.failure(this.message)
      : isSuccess = false,
        needsTopUp = false;

  GiftResult.insufficientFunds(this.message)
      : isSuccess = false,
        needsTopUp = true;
}

/// A result class to handle the outcomes of a coin liquidation attempt.
class LiquidationResult {
  final bool isSuccess;
  final String message;
  final double ugxReceived;
  final double ncxBurned;

  LiquidationResult.success(
      {required this.message, this.ugxReceived = 0.0, this.ncxBurned = 0.0})
      : isSuccess = true;

  LiquidationResult.failure(this.message)
      : isSuccess = false,
        ugxReceived = 0.0,
        ncxBurned = 0.0;
}

/// A result class to handle the outcomes of a shop purchase attempt.
class ShopPurchaseResult {
  final bool isSuccess;
  final String message;
  final bool needsTopUp;

  ShopPurchaseResult.success(this.message)
      : isSuccess = true,
        needsTopUp = false;

  ShopPurchaseResult.failure(this.message)
      : isSuccess = false,
        needsTopUp = false;

  ShopPurchaseResult.insufficientFunds(this.message)
      : isSuccess = false,
        needsTopUp = true;
}

extension WalletServiceShop on WalletService {
  /// Processes a shop purchase using the user's NCX balance.
  ///
  /// Calls the `processShopPurchase` Firebase Cloud Function. If the user
  /// has insufficient funds, the returned [ShopPurchaseResult] will indicate failure
  /// with a specific reason, allowing the UI to prompt a coin purchase.
  Future<ShopPurchaseResult> processShopPurchase({
    required String orderId,
    required String listingId,
    required String vendorId,
    required String sku,
    required int quantity,
    required String deliverySpeed, // 'express', 'standard', 'batch'
    required Map<String, double> customerLocation, // {'lat': ..., 'lon': ...}
    required String customerNumber,
  }) async {
    try {
      final firebaseFunctions = await _getFirebaseFunctions();
      final HttpsCallable callable = firebaseFunctions.httpsCallable('processShopPurchase');

      final response = await callable.call<Map<String, dynamic>>({
        'orderId': orderId, 'listingId': listingId, 'vendorId': vendorId,
        'sku': sku, 'quantity': quantity,
        'deliverySpeed': deliverySpeed,
        'customerLocation': customerLocation,
        'customerNumber': customerNumber,
      });

      final data = response.data;
      return ShopPurchaseResult.success(data['message'] ?? 'Purchase successful!');
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'resource-exhausted') {
        return ShopPurchaseResult.insufficientFunds(e.message ?? 'Insufficient NCX balance.');
      }
      return ShopPurchaseResult.failure(e.message ?? 'A server error occurred.');
    } catch (e) {
      return ShopPurchaseResult.failure('An unexpected error occurred.');
    }
  }
}