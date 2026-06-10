import 'package:flutter/material.dart';
import '../theme.dart';
import '../data.dart';
import '../app_state.dart';

class GiftOverlay extends StatelessWidget {
  final AppState state;
  final void Function(String emoji, String name, int price, int fee) onSend;

  const GiftOverlay({super.key, required this.state, required this.onSend});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F1623),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: C.border)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Text('🎁 Send a Gift', style: syne(sz: 20)),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: C.border,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text('✕',
                        style: TextStyle(color: C.text, fontSize: 16)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('Creator gets 60% · NECXA platform fee 40%',
              style: dm(sz: 11, c: C.dim)),
          const SizedBox(height: 14),

          // Wallet row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: C.border,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Text('💰 Wallet Balance',
                    style: dm(sz: 12, c: C.sub)),
                const Spacer(),
                Text(ugx(state.wallet),
                    style: syne(sz: 16, c: C.brand)),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Gifts grid
          Wrap(
            spacing: 10, runSpacing: 10,
            children: gifts.map((g) {
              final canAfford = state.wallet >= g.price;
              return GestureDetector(
                onTap: canAfford
                    ? () => onSend(g.emoji, g.name, g.price, g.fee)
                    : null,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: canAfford ? 1.0 : 0.35,
                  child: Container(
                    width: (MediaQuery.of(context).size.width - 100) / 4,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: C.border,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: canAfford ? const Color(0xFF2A3545) : C.border,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(g.emoji,
                            style: const TextStyle(fontSize: 28)),
                        const SizedBox(height: 4),
                        Text(g.name,
                            style: dm(sz: 10, w: FontWeight.w700),
                            textAlign: TextAlign.center),
                        const SizedBox(height: 2),
                        Text(ugx(g.price),
                            style: dm(sz: 9, w: FontWeight.w700, c: C.brand)),
                        Text('Fee: ${ugx(g.fee)}',
                            style: dm(sz: 8, c: C.red)),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Top-up button
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(
              gradient: brandGrad,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('➕ ', style: TextStyle(fontSize: 16)),
                Text('Top Up Wallet (MTN / Airtel)',
                    style: dm(sz: 14, w: FontWeight.w800, c: C.bg)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
