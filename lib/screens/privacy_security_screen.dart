import 'package:flutter/material.dart';
import '../theme.dart';
import '../app_state.dart';
import 'policies_screen.dart';
import '../utils/error_handler.dart';

class PrivacySecurityScreen extends StatefulWidget {
  final AppState state;
  const PrivacySecurityScreen({super.key, required this.state});

  @override
  State<PrivacySecurityScreen> createState() => _PrivacySecurityScreenState();
}

class _PrivacySecurityScreenState extends State<PrivacySecurityScreen> {
  bool _biometricsEnabled = true;
  bool _escrowLock = true;
  bool _twoFactorAuth = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('PRIVACY & SECURITY', style: syne(sz: 16, w: FontWeight.w800, ls: 1)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: () => widget.state.go('profile'),
        ),
      ),
      body: GestureDetector(
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity != null && details.primaryVelocity! > 0) {
            widget.state.go('profile');
          }
        },
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _sectionHeader('IDENTITY INFRASTRUCTURE'),
            _toggleTile(
              'Biometric Auth', 
              'Require Facial/Fingerprint match for transactions', 
              widget.state.isBiometricsEnabled, 
              (v) => widget.state.setBiometricsEnabled(v),
              Icons.fingerprint,
            ),
            
            const SizedBox(height: 32),
            _sectionHeader('FINANCIAL SHIELDS'),
            _toggleTile(
              'Escrow Smart Lock', 
              'Automatically lock massive transfers in escrow', 
              _escrowLock, 
              (v) => setState(() => _escrowLock = v),
              Icons.shield_moon_outlined,
            ),
            _toggleTile(
              'Two-Factor Authentication', 
              'Secure login and withdrawals with a 2FA code', 
              widget.state.is2FAEnabled, 
              (v) => widget.state.set2FAEnabled(v),
              Icons.password,
            ),

            const SizedBox(height: 32),
            _sectionHeader('LEGAL & POLICIES'),
            _actionTile('Community & Content Guidelines', 'View the Necxa network rules', Icons.policy_outlined, () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const PoliciesScreen()));
            }),
            
            const SizedBox(height: 32),
            _sectionHeader('DATA MANAGEMENT'),
            _actionTile('Data Export', 'Download a copy of your activity and data nodes', Icons.download_outlined, () {
              _handleDataExport();
            }),
            _actionTile('Delete Account', 'Permanently destroy your Necxa presence', Icons.delete_forever, () {
              _handleDeleteAccount();
            }, isDestructive: true),
          ],
        ),
      ),
    );
  }

  void _handleDataExport() async {
    final user = widget.state.user;
    if (user == null) return;
    
    try {
      await widget.state.social.triggerDataExport(user.id, user.email ?? '');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Data export triggered! You will receive an email shortly.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed. ${getUserFriendlyError(e)}')),
        );
      }
    }
  }

  void _handleDeleteAccount() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.card,
        title: Text('DELETE ACCOUNT?', style: syne(sz: 18, w: FontWeight.w800, c: Colors.redAccent)),
        content: Text(
          'Your account will be marked for deletion. You have 14 days to cancel this request before all data is permanently purged.',
          style: dm(sz: 14, c: C.sub),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('CANCEL', style: dm(c: C.brand))),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await widget.state.social.requestAccountDeletion(widget.state.user!.id);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Account deletion scheduled (14-day window).')),
                );
              }
            },
            child: const Text('PROCEED', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 0, 16),
      child: Text(title, style: syne(sz: 11, w: FontWeight.w800, c: C.dim, ls: 1.2)),
    );
  }

  Widget _toggleTile(String title, String sub, bool val, Function(bool) onChanged, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: C.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: C.border),
      ),
      child: SwitchListTile(
        value: val,
        onChanged: onChanged,
        activeThumbColor: C.brand,
        secondary: Icon(icon, color: C.brand),
        title: Text(title, style: syne(sz: 14, w: FontWeight.w600)),
        subtitle: Text(sub, style: dm(sz: 11, c: C.dim)),
      ),
    );
  }

  Widget _actionTile(String title, String sub, IconData icon, VoidCallback onTap, {bool isDestructive = false}) {
    final actColor = isDestructive ? Colors.redAccent : C.brand;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: C.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDestructive ? Colors.redAccent.withOpacity(.2) : C.border),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: actColor),
        title: Text(title, style: syne(sz: 14, w: FontWeight.w600, c: isDestructive ? Colors.redAccent : C.text)),
        subtitle: Text(sub, style: dm(sz: 11, c: C.dim)),
        trailing: Icon(Icons.arrow_forward_ios, size: 14, color: C.dim),
      ),
    );
  }
}
