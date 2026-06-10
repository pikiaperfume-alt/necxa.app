import 'package:flutter/material.dart';
import '../theme.dart';

class PoliciesScreen extends StatelessWidget {
  const PoliciesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: C.bg,
          title: Text('Necxa Policies', style: syne(sz: 18, w: FontWeight.w900)),
          bottom: TabBar(
            indicatorColor: C.brand,
            labelStyle: syne(sz: 14, w: FontWeight.w700),
            unselectedLabelStyle: syne(sz: 14),
            tabs: const [
              Tab(text: 'Community Guidelines'),
              Tab(text: 'Content Policy'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _CommunityGuidelines(),
            _ContentPolicy(),
          ],
        ),
      ),
    );
  }
}

class _CommunityGuidelines extends StatelessWidget {
  const _CommunityGuidelines();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _buildSectionTitle('Welcome to the Grid'),
        _buildSectionText('Necxa is a unified space for creators, merchants, and visionaries. Our guidelines ensure the Grid remains inspiring, safe, and professional.'),
        
        const SizedBox(height: 24),
        _buildSectionTitle('1. Respect & Professionalism'),
        _buildSectionText('We have zero tolerance for hate speech, harassment, or targeted attacks. Treat all users, buyers, and creators with respect.'),
        
        const SizedBox(height: 24),
        _buildSectionTitle('2. Authentication & Truth'),
        _buildSectionText('Do not impersonate other users, entities, or businesses. Authentic identities are enforced on the Grid framework.'),
        
        const SizedBox(height: 24),
        _buildSectionTitle('3. Fair Commerce'),
        _buildSectionText('When utilizing the Production hub for syndicating products, you must deliver exactly what is advertised. Misinformation, scams, and deceptive metadata will result in immediate suspension.'),
      ],
    );
  }
}

class _ContentPolicy extends StatelessWidget {
  const _ContentPolicy();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _buildSectionTitle('Content Submission Rules'),
        _buildSectionText('By uploading to the Necxa Grid, you accept the responsibilities of grid syndication.'),

        const SizedBox(height: 24),
        _buildSectionTitle('1. Intellectual Property'),
        _buildSectionText('You must own the rights to the media (audio, video, images) you upload. Do not post copyrighted material without express consent from the owner.'),

        const SizedBox(height: 24),
        _buildSectionTitle('2. Prohibited Content'),
        _buildSectionText(
          '• Explicit, adult, or pornographic content\n'
          '• Violent, graphic, or gore media\n'
          '• Illegal goods, services, or transactions\n'
          '• Malicious executable payloads disguised as media'
        ),

        const SizedBox(height: 24),
        _buildSectionTitle('3. Enforcement & Governance'),
        _buildSectionText('Necxa AI moderators and the decentralized reporting nodes constantly scan syndicated content. Violations will result in content deletion, Necxa Coin slashing, or permanent hardware bans.'),
      ],
    );
  }
}

Widget _buildSectionTitle(String title) {
  return Text(
    title,
    style: syne(sz: 18, w: FontWeight.bold, c: C.brand),
  );
}

Widget _buildSectionText(String text) {
  return Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      text,
      style: dm(sz: 14, c: C.dim, h: 1.5),
    ),
  );
}
