import 'package:flutter/material.dart';
import '../theme.dart';
import '../app_state.dart';
import 'dart:ui';

class VaultDepositOverlay extends StatefulWidget {
  final AppState state;
  const VaultDepositOverlay({super.key, required this.state});

  @override
  State<VaultDepositOverlay> createState() => _VaultDepositOverlayState();
}

class _VaultDepositOverlayState extends State<VaultDepositOverlay> {
  int _stage = 1; // 1: Amount, 2: Method, 3: Handshake, 4: Success
  final TextEditingController _amtCtrl = TextEditingController();
  String _selectedAmount = '50,000';

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Color(0xFF0d121b),
        borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Column(
            children: [
              _buildHeader(),
              Expanded(child: _buildStageContent()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white10))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add Money', style: syne(sz: 18, w: FontWeight.w700, c: Colors.white)),
              Text('Step $_stage of 4', style: dm(sz: 11, c: Colors.white38)),
            ],
          ),
          IconButton(icon: const Icon(Icons.close, color: Colors.white38), onPressed: () => Navigator.pop(context)),
        ],
      ),
    );
  }

  Widget _buildStageContent() {
    switch (_stage) {
      case 1: return _buildAmountStage();
      case 2: return _buildMethodStage();
      case 3: return _buildHandshakeStage();
      case 4: return _buildSuccessStage();
      default: return const SizedBox();
    }
  }

  Widget _buildAmountStage() {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Quick amounts', style: dm(sz: 12, w: FontWeight.w600, c: Colors.white38)),
          const SizedBox(height: 16),
          _AmountGrid(
            selected: _selectedAmount,
            onSelect: (s) => setState(() { _selectedAmount = s; _amtCtrl.text = s.replaceAll(',', ''); }),
          ),
          const SizedBox(height: 40),
          Text('Custom amount', style: dm(sz: 12, w: FontWeight.w600, c: Colors.white38)),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(color: Colors.white.withOpacity(.02), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withOpacity(.08))),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _amtCtrl,
              keyboardType: TextInputType.number,
              style: syne(sz: 24, w: FontWeight.w700, c: Colors.white),
              decoration: const InputDecoration(hintText: 'Enter UGX amount...', hintStyle: TextStyle(color: Colors.white10), border: InputBorder.none, suffixText: 'UGX', suffixStyle: TextStyle(color: Colors.white38)),
            ),
          ),
          const Spacer(),
          _BottomBtn(label: 'Continue', onTap: () => setState(() => _stage = 2)),
        ],
      ),
    );
  }

  Widget _buildMethodStage() {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How would you like to pay?', style: dm(sz: 12, w: FontWeight.w600, c: Colors.white38)),
          const SizedBox(height: 24),
          const _MethodTile(icon: Icons.phone_android, label: 'MTN Mobile Money', sub: 'Linked: +256 701 *** 567', color: Color(0xFFeab308)),
          const SizedBox(height: 16),
          const _MethodTile(icon: Icons.phone_android, label: 'Airtel Money', sub: 'Linked: +256 755 *** 789', color: Colors.red),
          const SizedBox(height: 16),
          const _MethodTile(icon: Icons.credit_card, label: 'Visa Card', sub: 'Debit: **** 4022', color: Colors.blue),
          const SizedBox(height: 16),
          _LinkNodeBtn(),
          const Spacer(),
          _BottomBtn(label: 'Continue', onTap: () => setState(() => _stage = 3)),
        ],
      ),
    );
  }

  Widget _buildHandshakeStage() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _MatrixScanner(),
        const SizedBox(height: 40),
        Text('Confirm your identity', style: syne(sz: 16, w: FontWeight.w700, c: Colors.white)),
        const SizedBox(height: 8),
        Text('Touch to verify it\'s you...', style: dm(sz: 12, c: Colors.white38)),
        const SizedBox(height: 40),
        _BottomBtn(label: 'Confirm & Deposit', onTap: () => _finalizeInjection()),
      ],
    );
  }

  void _finalizeInjection() async {
    final amt = double.tryParse(_amtCtrl.text.isEmpty ? _selectedAmount.replaceAll(',', '') : _amtCtrl.text) ?? 50000;
    await widget.state.depositFiat(amt);
    setState(() => _stage = 4);
  }

  Widget _buildSuccessStage() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(padding: const EdgeInsets.all(32), decoration: BoxDecoration(color: const Color(0xFF22c55e).withOpacity(.1), shape: BoxShape.circle), child: const Icon(Icons.check_circle_outline, color: Color(0xFF22c55e), size: 72)),
          const SizedBox(height: 32),
          Text('Done!', style: syne(sz: 28, w: FontWeight.w700, c: Colors.white)),
          const SizedBox(height: 12),
          Text('Money added to your balance.', style: dm(sz: 14, c: Colors.white38)),
          const SizedBox(height: 48),
          _BottomBtn(label: 'Back to Wallet', onTap: () => Navigator.pop(context)),
        ],
      ),
    );
  }
}

class _AmountGrid extends StatelessWidget {
  final String selected;
  final Function(String) onSelect;
  const _AmountGrid({required this.selected, required this.onSelect});
  @override
  Widget build(BuildContext context) => GridView.count(shrinkWrap: true, crossAxisCount: 2, mainAxisSpacing: 16, crossAxisSpacing: 16, childAspectRatio: 2.2, children: ['50,000', '100,000', '250,000', '500,000'].map((s) => _BagBtn(label: s, active: selected == s, onTap: () => onSelect(s))).toList());
}

class _BagBtn extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _BagBtn({required this.label, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(onTap: onTap, child: AnimatedContainer(duration: const Duration(milliseconds: 200), decoration: BoxDecoration(color: active ? Colors.white : Colors.white.withOpacity(.02), borderRadius: BorderRadius.circular(16), border: Border.all(color: active ? Colors.white : Colors.white.withOpacity(.1))), child: Center(child: Text(label, style: syne(sz: 16, w: FontWeight.w900, c: active ? Colors.black : Colors.white60)))));
}

class _MethodTile extends StatelessWidget {
  final IconData icon;
  final String label, sub;
  final Color color;
  const _MethodTile({required this.icon, required this.label, required this.sub, required this.color});
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white.withOpacity(.03), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withOpacity(.05))), child: Row(children: [Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: color.withOpacity(.15), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: color, size: 20)), const SizedBox(width: 16), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: syne(sz: 13, w: FontWeight.w800, c: Colors.white)), Text(sub, style: dm(sz: 11, c: Colors.white38))]), const Spacer(), const Icon(Icons.chevron_right, color: Colors.white24)]));
}

class _LinkNodeBtn extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 18), decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10)), child: Center(child: Text('+ Add a new payment method', style: syne(sz: 13, w: FontWeight.w600, c: Colors.white38))));
}

class _MatrixScanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(width: 140, height: 140, decoration: BoxDecoration(color: Colors.white.withOpacity(.03), borderRadius: BorderRadius.circular(40), border: Border.all(color: Colors.blue.withOpacity(.2))), child: Stack(alignment: Alignment.center, children: [Icon(Icons.fingerprint, color: Colors.blue.withOpacity(.4), size: 64), Container(width: 100, height: 2, color: Colors.blue.withOpacity(.6))]));
}

class _BottomBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _BottomBtn({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(onTap: onTap, child: Container(height: 64, width: double.infinity, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.white.withOpacity(.1), blurRadius:20)]), child: Center(child: Text(label, style: syne(sz: 16, w: FontWeight.w700, c: Colors.black)))));
}

class BorderDash extends ShapeBorder {
  final List<double> dashPattern;
  const BorderDash(this.dashPattern);
  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;
  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => Path();
  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final path = Path()..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(20)));
    return path;
  }
  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final paint = Paint()..color = Colors.white10..style = PaintingStyle.stroke..strokeWidth = 1.5;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(20));
    canvas.drawRRect(rrect, paint); // Simplify: just draw border for now as custom dash is complex in ShapeBorder
  }
  @override
  ShapeBorder scale(double t) => this;
}
