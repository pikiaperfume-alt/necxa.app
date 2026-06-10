// lib/screens/creator_chat_list_screen.dart
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme.dart';
import '../app_state.dart';
import '../models/chat_models.dart';

class CreatorChatListScreen extends StatefulWidget {
  final AppState state;
  const CreatorChatListScreen({super.key, required this.state});

  @override
  State<CreatorChatListScreen> createState() => _CreatorChatListScreenState();
}

class _CreatorChatListScreenState extends State<CreatorChatListScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    widget.state.fetchCreatorConversations();
    widget.state.loadNotifications();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => widget.state.goBack(),
        ),
        title: Text('CREATOR SOCIAL', style: syne(sz: 18, w: FontWeight.w900, ls: 2)),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF00E5FF),
          labelColor: const Color(0xFF00E5FF),
          unselectedLabelColor: Colors.white54,
          labelStyle: syne(sz: 13, w: FontWeight.bold),
          tabs: const [
            Tab(text: 'CHATS'),
            Tab(text: 'NOTIFICATIONS'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildChatList(),
          _buildNotificationList(),
        ],
      ),
    );
  }

  Widget _buildChatList() {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        if (widget.state.isCreatorChatLoading) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)));
        }

        final convos = widget.state.creatorConversations;
        if (convos.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.forum_outlined, size: 60, color: Colors.white10),
                const SizedBox(height: 16),
                Text('NO CREATOR INTERACTIONS YET', style: syne(sz: 12, c: Colors.white24, ls: 1)),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: convos.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final room = convos[i];
            return _CreatorChatTile(room: room, state: widget.state);
          },
        );
      },
    );
  }

  Widget _buildNotificationList() {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final notifs = widget.state.appNotifications;
        if (notifs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.notifications_off_outlined, size: 60, color: Colors.white10),
                const SizedBox(height: 16),
                Text('ALL CAUGHT UP', style: syne(sz: 12, c: Colors.white24, ls: 1)),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: notifs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final notif = notifs[i];
            return _NotificationTile(notif: notif, state: widget.state);
          },
        );
      },
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final dynamic notif;
  final AppState state;
  const _NotificationTile({required this.notif, required this.state});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color iconColor;
    switch (notif.type) {
      case 'financial':
        icon = Icons.account_balance_wallet_rounded;
        iconColor = C.gold;
        break;
      case 'listing':
        icon = Icons.home_work_rounded;
        iconColor = C.blue;
        break;
      case 'social':
        icon = Icons.favorite_rounded;
        iconColor = C.red;
        break;
      case 'content':
      default:
        icon = Icons.notifications_active_rounded;
        iconColor = C.brand;
    }

    return GestureDetector(
      onTap: () {
        if (!notif.isRead) state.markNotificationAsRead(notif.id);
        // Add specific payload navigation if needed
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: notif.isRead ? Colors.white.withOpacity(0.02) : const Color(0xFF0A0F2C).withOpacity(0.4),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: notif.isRead ? Colors.transparent : C.brand.withOpacity(0.2)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(notif.title, style: syne(sz: 14, w: notif.isRead ? FontWeight.w600 : FontWeight.w900)),
                      if (!notif.isRead)
                        Container(width: 8, height: 8, decoration: BoxDecoration(color: C.brand, shape: BoxShape.circle)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(notif.body, style: dm(sz: 13, c: Colors.white70)),
                  const SizedBox(height: 8),
                  Text('${notif.createdAt.hour}:${notif.createdAt.minute.toString().padLeft(2, '0')}', style: dm(sz: 11, c: Colors.white38)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreatorChatTile extends StatelessWidget {
  final ChatRoom room;
  final AppState state;
  const _CreatorChatTile({required this.room, required this.state});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        state.activeConversation = room;
        await state.fetchMessages(room.id);
        state.go('creator-chat-detail');
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF0A0F2C).withOpacity(0.4),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: const Color(0xFF00E5FF).withOpacity(0.1),
              // CachedNetworkImageProvider — zero repeat egress after first load
              backgroundImage: room.otherAvatar != null
                  ? CachedNetworkImageProvider(room.otherAvatar!)
                  : null,
              child: room.otherAvatar == null
                ? Text(
                    (room.otherName != null && room.otherName!.isNotEmpty)
                        ? room.otherName![0].toUpperCase()
                        : '?',
                    style: syne(c: const Color(0xFF00E5FF), w: FontWeight.bold),
                  )
                : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(room.otherName ?? 'Creator', style: syne(sz: 16, w: FontWeight.bold)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: room.metadata?['interaction_context'] == 'vendor' 
                            ? Colors.amberAccent.withOpacity(0.1) 
                            : const Color(0xFF00E5FF).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          room.metadata?['interaction_context']?.toString().toUpperCase() ?? 'SOCIAL',
                          style: syne(
                            sz: 7, 
                            w: FontWeight.w900, 
                            c: room.metadata?['interaction_context'] == 'vendor' 
                              ? Colors.amberAccent 
                              : const Color(0xFF00E5FF)
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(room.lastMessage ?? 'Start a conversation', maxLines: 1, overflow: TextOverflow.ellipsis, style: dm(sz: 13, c: Colors.white54)),
                ],
              ),
            ),
            if (room.myUnread > 0)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(color: Color(0xFF00E5FF), shape: BoxShape.circle),
                child: Text(room.myUnread.toString(), style: dm(sz: 10, w: FontWeight.bold, c: Colors.black)),
              ),
          ],
        ),
      ),
    );
  }
}
