import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'coin_liquidation_service.dart';

class FirebaseLiquidationService {
  FirebaseFunctions get _functions => FirebaseFunctions.instance;
  
  // 💹 NCX Economics Node: 1 NCX = 100 UGX (Base Rate)
  static const double ncxPrice = 100.0;
  static const double burnRate = 0.11; // 11% Burn Tax

  Future<LiquidationQuote> getQuote(double ncxAmount) async {
    final double rawUgx = ncxAmount * ncxPrice;
    final double ncxBurned = ncxAmount * burnRate;
    final double ugxReceived = rawUgx * (1 - burnRate);

    return LiquidationQuote(
      ncxAmount: ncxAmount,
      ugxReceived: ugxReceived,
      ncxBurned: ncxBurned,
      burnPercentage: 11,
      effectiveRate: 0.89,
    );
  }

  Future<LiquidationResult> liquidate({
    required String userId,
    required double ncxAmount,
    required Map<String, dynamic> securityMetadata,
  }) async {
    try {
      final HttpsCallable callable = _functions.httpsCallable('liquidateCoins');
      final result = await callable.call({
        'ncxAmount': ncxAmount,
        'securityMetadata': securityMetadata,
      });

      final data = result.data;
      if (data['success'] == true) {
        return LiquidationResult(
          success: true,
          ugxReceived: (data['ugxReceived'] as num).toDouble(),
          ncxBurned: (data['ncxBurned'] as num).toDouble(),
          newCoinBalance: (data['newCoinBalance'] as num).toDouble(),
          newFiatBalance: (data['newFiatBalance'] as num).toDouble(),
          txCommitHash: data['txCommitHash'] ?? '',
          newNcxPrice: (data['newNcxPrice'] as num).toDouble(),
          message: data['message'] ?? 'Liquidation successful.',
        );
      } else {
        throw Exception(data['message'] ?? 'Liquidation failed on server.');
      }
    } catch (e) {
      debugPrint('🔥 Firebase Liquidation Error: $e');
      rethrow;
    }
  }
}
