import 'package:flutter/material.dart';
import '../theme.dart';
import '../app_state.dart';
import 'vault_deposit_overlay.dart';
import 'vault_withdraw_overlay.dart';
import 'vault_buy_shards_overlay.dart';
import 'vault_sell_shards_overlay.dart';

class VaultWidget extends StatelessWidget {
  final AppState state;
  const VaultWidget({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── FIAT NODE ──
        _VaultNodeCard(
          label: 'Your Balance',
          sub: 'Available to spend',
          value: 'UGX ${state.fiatBalance.toInt()}',
          color: const Color(0xFF3b82f6),
          actions: [
            Expanded(child: Padding(padding: const EdgeInsets.only(right: 8), child: _NodeAction(icon: Icons.add, label: 'Deposit', onTap: () => _openDeposit(context)))),
            Expanded(child: Padding(padding: const EdgeInsets.only(right: 8), child: _NodeAction(icon: Icons.arrow_upward, label: 'Withdraw', onTap: () => _openWithdraw(context)))),
          ],
        ),
        const SizedBox(height: 16),
        
        // ── SHARD NODE ──
        _VaultNodeCard(
          label: 'Coins (NCX)',
          sub: 'Digital tokens',
          value: '${state.shardBalance.toInt()} NCX',
          color: const Color(0xFFeab308),
          actions: [
            Expanded(child: Padding(padding: const EdgeInsets.only(right: 8), child: _NodeAction(icon: Icons.bolt, label: 'Buy', onTap: () => _openBuyCoins(context)))),
            Expanded(child: Padding(padding: const EdgeInsets.only(right: 8), child: _NodeAction(icon: Icons.sync_alt, label: 'Sell', onTap: () => _openSellCoins(context)))),
          ],
        ),
        const SizedBox(height: 16),

        // ── ESCROW NODE ──
        _VaultNodeCard(
          label: 'Protected Funds',
          sub: 'Held in escrow',
          value: 'UGX ${state.escrowBalance.toInt()}',
          color: const Color(0xFF10b981),
          isEscrow: true,
          actions: [
            Expanded(child: Padding(padding: const EdgeInsets.only(right: 8), child: _NodeAction(icon: Icons.shield_outlined, label: 'Protect', onTap: () {}))),
            Expanded(child: Padding(padding: const EdgeInsets.only(right: 8), child: _NodeAction(icon: Icons.history, label: 'History', onTap: () {}))),
          ],
        ),
      ],
    );
  }

  void _openDeposit(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VaultDepositOverlay(state: state),
    );
  }

  void _openWithdraw(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VaultWithdrawOverlay(state: state),
    );
  }

  void _openBuyCoins(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VaultBuyShardsOverlay(state: state),
    );
  }

  void _openSellCoins(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VaultSellShardsOverlay(state: state),
    );
  }
}

class _VaultNodeCard extends StatelessWidget {
  final String label, sub, value;
  final Color color;
  final List<Widget> actions;
  final bool isEscrow;
  const _VaultNodeCard({required this.label, required this.sub, required this.value, required this.color, required this.actions, this.isEscrow = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.02),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: color.withOpacity(.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: syne(sz: 10, w: FontWeight.w900, ls: 2, c: color)),
                  const SizedBox(height: 4),
                  Text(sub, style: dm(sz: 9, c: Colors.white24, fs: FontStyle.italic)),
                ],
              ),
              if (isEscrow) _EscrowSyncDot(),
            ],
          ),
          const SizedBox(height: 24),
          Text(value, style: syne(sz: 28, w: FontWeight.w900, fs: FontStyle.italic, c: color)),
          const SizedBox(height: 24),
          Row(children: actions),
        ],
      ),
    );
  }
}

class _EscrowSyncDot extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Row(children: [Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF10b981), shape: BoxShape.circle)), const SizedBox(width: 8), Text('Funds are protected', style: dm(sz: 9, c: Colors.white38))]);
}

class _NodeAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _NodeAction({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: Colors.white.withOpacity(.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withOpacity(.05))),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 14),
            const SizedBox(width: 8),
            Text(label, style: dm(sz: 10, w: FontWeight.w700, ls: 1)),
          ],
        ),
      ),
    );
  }
}
