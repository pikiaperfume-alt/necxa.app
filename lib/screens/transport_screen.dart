import 'package:flutter/material.dart';
import 'dart:ui';
import '../theme.dart';
import '../data.dart';
import '../app_state.dart';
import '../models/transport_models.dart';
import '../services/logistics_engine.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as cloud;

class TransportScreen extends StatefulWidget {
  final AppState state;
  const TransportScreen({super.key, required this.state});

  @override
  State<TransportScreen> createState() => _TransportScreenState();
}

class _TransportScreenState extends State<TransportScreen> {
  int _activeTab = 0; // 0: Marketplace, 1: Orders, 2: Hub
  final _pickupCtrl = TextEditingController(text: 'Kampala Central');
  final _dropoffCtrl = TextEditingController(text: 'Nakawa Hub');

  @override
  void initState() {
    super.initState();
    widget.state.fetchAvailableDrivers();
    widget.state.fetchMyOrders();
    widget.state.checkDriverStatus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      body: Column(
        children: [
          _buildModularHeader(),
          _buildAppTabs(),
          Expanded(
            child: Stack(
              children: [
                _buildBackgroundGlow(),
                Column(
                  children: [
                    _buildSubTabs(),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: _buildTabContent(),
                      ),
                    ),
                  ],
                ),
                _buildModularBottomNav(),
                
                // 🚀 SMART SYNC INDICATOR (Transport Edition)
                Positioned(
                  top: 10, left: 0, right: 0,
                  child: ListenableBuilder(
                    listenable: widget.state,
                    builder: (context, _) {
                      if (!widget.state.isTransportSyncing) return const SizedBox.shrink();
                      return Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(204),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: C.brand.withAlpha(77)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: C.brand)),
                              const SizedBox(width: 10),
                              Text('Syncing Logistics...', style: dm(sz: 10, w: FontWeight.bold, c: Colors.white)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Modular Header (Matches Home/Profile) ──
  Widget _buildModularHeader() {
    return Container(
      color: C.card,
      padding: const EdgeInsets.fromLTRB(18, 52, 18, 12),
      child: Row(
        children: [
          const NecxaLogo(size: 42, shadow: false),
          const SizedBox(width: 10),
          Text('TRANSPORT', style: syne(sz: 18, w: FontWeight.w800, ls: -.5)),
          const Spacer(),
          _joinFleetBtn(),
        ],
      ),
    );
  }

  Widget _joinFleetBtn() {
    if (widget.state.isDriver) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: C.green.withAlpha(26),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: C.green.withAlpha(77)),
        ),
        child: Row(
          children: [
            const Icon(Icons.verified, color: C.green, size: 12),
            const SizedBox(width: 4),
            Text('VERIFIED', style: syne(sz: 9, w: FontWeight.w900, c: C.green)),
          ],
        ),
      );
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => widget.state.go('driver-registration'),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: C.brand.withAlpha(26),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: C.brand.withAlpha(77)),
          ),
          child: Row(
            children: [
              const Icon(Icons.local_shipping_outlined, color: C.brand, size: 16),
              const SizedBox(width: 6),
              Text('JOIN FLEET', style: syne(sz: 11, w: FontWeight.w800, c: C.brand)),
            ],
          ),
        ),
      ),
    );
  }

  // ── Shared App Tabs ──
  Widget _buildAppTabs() {
    final tabs = [
      ('home', '🏠', 'Property'),
      ('transport', '🚚', 'Transport'),
      ('upload', '➕', 'Upload'),
      ('profile', '👤', 'Profile'),
    ];
    return Container(
      decoration: BoxDecoration(color: C.card, border: Border(bottom: BorderSide(color: C.border))),
      child: Row(
        children: tabs.map((t) {
          final active = t.$1 == 'transport';
          return Expanded(
            child: GestureDetector(
              onTap: () => widget.state.go(t.$1),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: active ? C.brand : Colors.transparent, width: 2)),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    Text('${t.$2} ${t.$3}',
                        textAlign: TextAlign.center,
                        style: dm(sz: 10, w: active ? FontWeight.w800 : FontWeight.w500, c: active ? C.brand : C.dim)),
                    if (t.$1 == 'transport' && (widget.state.pendingVendorOrders > 0 || widget.state.activeBuyerTransportCount > 0))
                      Positioned(
                        top: -4, right: -12,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                          child: Text('${widget.state.pendingVendorOrders + widget.state.activeBuyerTransportCount}', style: syne(sz: 8, w: FontWeight.bold, c: Colors.white)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Transport Sub-Tabs ──
  Widget _buildSubTabs() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: C.cardDk, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          _subTabItem(0, 'Marketplace', Icons.explore_outlined),
          _subTabItem(1, 'Orders', Icons.assignment_outlined, hasBadge: widget.state.pendingVendorOrders > 0 || widget.state.activeBuyerTransportCount > 0),
          if (widget.state.isDriver) _subTabItem(2, 'Control', Icons.dashboard_customize_outlined),
        ],
      ),
    );
  }

  Widget _subTabItem(int index, String label, IconData icon, {bool hasBadge = false}) {
    bool active = _activeTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _activeTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? C.card : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: active ? C.brand : C.dim),
              const SizedBox(width: 6),
              Text(label, style: dm(sz: 11, w: active ? FontWeight.w700 : FontWeight.w500, c: active ? Colors.white : C.dim)),
              if (hasBadge) ...[
                const SizedBox(width: 6),
                Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle)),
              ]
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBackgroundGlow() {
    return Positioned(
      top: 40, right: -40,
      child: Container(
        width: 250,
        height: 250,
        decoration: BoxDecoration(shape: BoxShape.circle, color: C.brand.withAlpha(13)),
        child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60), child: const SizedBox()),
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_activeTab) {
      case 0: return _buildMarketplace();
      case 1: return _buildOrders();
      case 2: return _buildDriverHub();
      default: return const SizedBox();
    }
  }

  Widget _buildMarketplace() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildSearchCard(),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Verified Carriers', style: syne(sz: 14, w: FontWeight.w800)),
            Text('${widget.state.availableDrivers.length} Online', style: dm(sz: 10, c: C.brand, w: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 12),
        if (widget.state.availableDrivers.isEmpty)
          _buildEmpty('No Active Carriers', 'Check back shortly for nearby fleet availability.')
        else
          ...widget.state.availableDrivers.map((d) => _DriverCard(driver: d, state: widget.state, p: _pickupCtrl.text, d: _dropoffCtrl.text)),
        const SizedBox(height: 100),
      ],
    );
  }

  Widget _buildSearchCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(20), border: Border.all(color: C.border)),
      child: Column(
        children: [
          _field('Origin Point', Icons.circle_outlined, _pickupCtrl),
          const SizedBox(height: 12),
          _field('Destination', Icons.location_on_outlined, _dropoffCtrl),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () {},
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(color: C.brand, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: C.brand.withAlpha(77), blurRadius: 10)]),
              child: Center(child: Text('EXPLORE ROUTES', style: syne(sz: 12, w: FontWeight.w800, c: Colors.white))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(String label, IconData icon, TextEditingController ctrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: syne(sz: 9, c: C.dim)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: C.cardDk, borderRadius: BorderRadius.circular(10), border: Border.all(color: C.border)),
          child: TextField(
            controller: ctrl,
            style: dm(sz: 13),
            decoration: InputDecoration(icon: Icon(icon, size: 16, color: C.brand), border: InputBorder.none, hintStyle: dm(sz: 13, c: C.dim)),
          ),
        ),
      ],
    );
  }

  Widget _buildOrders() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Vendor Sales Queue
        Row(
          children: [
            Text('Vendor Sales', style: syne(sz: 14, w: FontWeight.w800)),
            if (widget.state.pendingVendorOrders > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.redAccent.withAlpha(51), borderRadius: BorderRadius.circular(10)),
                child: Text('${widget.state.pendingVendorOrders} PENDING', style: dm(sz: 9, w: FontWeight.bold, c: Colors.redAccent)),
              ),
            ]
          ],
        ),
        const SizedBox(height: 12),
        StreamBuilder<cloud.QuerySnapshot>(
          stream: widget.state.orders.streamVendorOrders(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const SizedBox();
            final docs = snapshot.data?.docs ?? [];
            if (docs.isEmpty) {
              return _buildEmpty('No Active Sales', 'When someone buys your products, the order will appear here.');
            }
            return Column(
              children: docs.map((d) => _EcomOrderCard(data: d.data() as Map<String, dynamic>, state: widget.state)).toList(),
            );
          },
        ),
        const SizedBox(height: 32),
        
        // Active Logistics (Buyer Perspective)
        Row(
          children: [
            Text('Active Logistics', style: syne(sz: 14, w: FontWeight.w800)),
            if (widget.state.activeBuyerTransportCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: C.brand.withAlpha(51), borderRadius: BorderRadius.circular(10)),
                child: Text('${widget.state.activeBuyerTransportCount} ACTIVE', style: dm(sz: 9, w: FontWeight.bold, c: C.brand)),
              ),
            ]
          ],
        ),
        const SizedBox(height: 12),
        if (widget.state.myTransportOrders.isEmpty)
          _buildEmpty('No Active Missions', 'Your booking history will populate here.')
        else
          ...widget.state.myTransportOrders.map((o) => _OrderCard(order: o, state: widget.state)),
        const SizedBox(height: 100),
      ],
    );
  }

  Widget _buildDriverHub() {
    final d = widget.state.currentDriverProfile;
    if (d == null) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildHubStatus(d),
        const SizedBox(height: 24),
        Text('Mission Queue', style: syne(sz: 14, w: FontWeight.w800)),
        const SizedBox(height: 12),
        if (widget.state.myDriverOrders.isEmpty)
          _buildEmpty('Awaiting Assignments', 'Online drivers appear in the marketplace instantly.')
        else
          ...widget.state.myDriverOrders.map((o) => _OrderCard(order: o, state: widget.state, isDriver: true)),
        const SizedBox(height: 100),
      ],
    );
  }

  Widget _buildHubStatus(TransportDriver d) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(20), border: Border.all(color: C.brand.withAlpha(77))),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(backgroundColor: C.brand, child: Text(d.name[0], style: syne(sz: 18, c: Colors.white))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.name, style: syne(sz: 16, w: FontWeight.w700)),
                    Text('${d.vehicleType.name.toUpperCase()} • ${d.numberPlate}', style: dm(sz: 11, c: C.dim)),
                  ],
                ),
              ),
              Switch(value: d.isAvailable, onChanged: (v) => widget.state.toggleDriverAvailability(v), activeThumbColor: C.brand),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(String t, String s) {
    return Padding(padding: const EdgeInsets.only(top: 80), child: Center(child: Column(
      children: [
        Icon(Icons.layers_clear_outlined, size: 48, color: C.border),
        const SizedBox(height: 16),
        Text(t, style: syne(sz: 14, w: FontWeight.w700)),
        const SizedBox(height: 4),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 40), child: Text(s, textAlign: TextAlign.center, style: dm(sz: 12, c: C.dim))),
      ],
    )));
  }

  Widget _buildModularBottomNav() {
    return Positioned(
      bottom: 20, left: 20, right: 20,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(color: C.card.withAlpha(217), border: Border.all(color: Colors.white.withAlpha(26)), borderRadius: BorderRadius.circular(20)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _navItem(Icons.home_outlined, 'Property', false, 'home'),
                _navItem(Icons.flash_on_outlined, 'Community', false, 'community'),
                _navItem(Icons.assignment_outlined, 'Listings', false, 'list'),
                _navItem(Icons.chat_bubble_outline, 'Chat', false, 'chat'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem(IconData icon, String label, bool active, String route) {
    return GestureDetector(
      onTap: () => widget.state.go(route),
      child: Column(mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: active ? C.brand : C.dim, size: 20),
          const SizedBox(height: 4),
          Text(label, style: dm(sz: 9, w: FontWeight.w600, c: active ? C.brand : C.dim)),
        ],
      ),
    );
  }
}

class _DriverCard extends StatelessWidget {
  final TransportDriver driver;
  final AppState state;
  final String p, d;
  const _DriverCard({required this.driver, required this.state, required this.p, required this.d});

  @override
  Widget build(BuildContext context) {
    double fare = LogisticsEngine.calculateFare(pickup: p, dropoff: d, vehicleType: driver.vehicleType);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.border)),
      child: Row(
        children: [
          CircleAvatar(backgroundColor: C.cardDk, child: Text(driver.name[0], style: syne(c: C.brand))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(driver.name, style: syne(sz: 13, w: FontWeight.w700)),
              Text('${driver.vehicleType.name.toUpperCase()} • Verified', style: dm(sz: 10, c: C.dim)),
            ],
          )),
          Column(crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(ugx(fare), style: syne(sz: 14, c: C.brand)),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () => _handshake(context, fare),
                child: Container(decoration: BoxDecoration(color: C.brand, borderRadius: BorderRadius.circular(6)), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), child: Text('BOOK', style: syne(sz: 9, c: Colors.white))),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _handshake(BuildContext context, double fare) {
    showModalBottomSheet(context: context, backgroundColor: Colors.transparent, builder: (_) => Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(color: C.bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
      child: Column(mainAxisSize: MainAxisSize.min,
        children: [
          Text('CONFIRM BOOKING', style: syne(sz: 18)),
          const SizedBox(height: 24),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Fare', style: dm(c: C.dim)), Text(ugx(fare), style: syne(sz: 18, c: C.brand))]),
          const SizedBox(height: 32),
          GestureDetector(
            onTap: () { state.createTransportOrder(driver: driver, pickup: p, dropoff: d, price: fare); Navigator.pop(context); },
            child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 16), decoration: BoxDecoration(color: C.brand, borderRadius: BorderRadius.circular(12)), child: Center(child: Text('AUTHORIZE', style: syne(sz: 14, c: Colors.white)))),
          ),
        ],
      ),
    ));
  }
}

class _OrderCard extends StatelessWidget {
  final TransportOrder order;
  final AppState state;
  final bool isDriver;
  const _OrderCard({required this.order, required this.state, this.isDriver = false});

  @override
  Widget build(BuildContext context) {
    Color col = order.status == OrderStatus.pending ? C.orange : order.status == OrderStatus.accepted ? C.brand : C.green;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.border)),
      child: Column(
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('ID: ${order.id.substring(0, 6).toUpperCase()}', style: dm(sz: 10, c: C.dim)),
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: col.withAlpha(26), borderRadius: BorderRadius.circular(10)), child: Text(order.status.name.toUpperCase(), style: dm(sz: 9, c: col, w: FontWeight.w700))),
            ],
          ),
          const SizedBox(height: 12),
          _row(Icons.circle_outlined, order.pickupLocation, C.brand),
          const SizedBox(height: 6),
          _row(Icons.place_outlined, order.dropoffLocation, C.red),
          const Divider(height: 24),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Fare: ${ugx(order.price)}', style: syne(sz: 13, c: C.brand)),
              if (isDriver && order.status == OrderStatus.pending)
                GestureDetector(
                  onTap: () async {
                    // 🚚 DRIVER HANDSHAKE: Lock mission and assign driver info
                    final driver = state.currentDriverProfile;
                    if (driver == null) return;
                    
                    await state.orders.assignDriver(order.id, {
                      'id': driver.id,
                      'name': driver.name,
                      'phone': driver.phone,
                    });
                  }, 
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6), 
                    decoration: BoxDecoration(color: C.brand, borderRadius: BorderRadius.circular(8)), 
                    child: Text('ACCEPT MISSION', style: syne(sz: 10, c: Colors.white, w: FontWeight.bold))
                  )
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(IconData i, String v, Color c) => Row(children: [Icon(i, size: 14, color: c), const SizedBox(width: 8), Text(v, style: dm(sz: 12))]);
}

class _EcomOrderCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final AppState state;
  const _EcomOrderCard({required this.data, required this.state});

  @override
  State<_EcomOrderCard> createState() => _EcomOrderCardState();
}

class _EcomOrderCardState extends State<_EcomOrderCard> {
  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final status = data['status'] ?? 'pending';
    final isPending = status == 'pending_payment' || status == 'processing' || status == 'pending';
    final col = isPending ? C.orange : (status == 'delivered' ? C.green : C.brand);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.border)),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('ORD: ${data['order_id'].toString().substring(0, 8)}', style: dm(sz: 10, c: C.dim)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: col.withAlpha(26), borderRadius: BorderRadius.circular(10)),
                child: Text(status.toUpperCase().replaceAll('_', ' '), style: dm(sz: 9, c: col, w: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  image: data['product_thumbnail'] != null ? DecorationImage(image: NetworkImage(data['product_thumbnail']), fit: BoxFit.cover) : null,
                  color: Colors.white10,
                ),
                child: data['product_thumbnail'] == null ? const Icon(Icons.inventory_2_outlined, color: Colors.white38) : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(data['product_title'] ?? 'Product Item', style: syne(sz: 13, w: FontWeight.w700)),
                    Text(data['delivery_address']?.toString().replaceAll('\n', ', ') ?? 'No address provided', maxLines: 1, overflow: TextOverflow.ellipsis, style: dm(sz: 11, c: C.dim)),
                  ],
                ),
              ),
            ],
          ),
          
          // 🚚 LOGISTICS PARTNER (Vendor Side)
          if (data['driver_id'] != null) ...[
            const Divider(height: 24, color: Colors.white10),
            Row(
              children: [
                const Icon(Icons.local_shipping_outlined, color: Color(0xFF00E5FF), size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('LOGISTICS PARTNER', style: syne(sz: 8, w: FontWeight.w900, c: const Color(0xFF00E5FF), ls: 1)),
                      Text(data['driver_name'] ?? 'Driver Assigned', style: syne(sz: 12, w: FontWeight.bold)),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    // Open chat with driver
                    // In AppState or similar
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E5FF).withAlpha(26),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF00E5FF).withAlpha(51)),
                    ),
                    child: Text('CHAT', style: syne(sz: 9, w: FontWeight.bold, c: const Color(0xFF00E5FF))),
                  ),
                ),
              ],
            ),
          ],

          const Divider(height: 24, color: Colors.white10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Earnings: ${ugx((data['amount'] as num).toDouble())}', style: syne(sz: 13, c: C.green)),
              if (isPending)
                GestureDetector(
                  onTap: () async {
                    // 🚀 VENDOR HANDSHAKE: Trigger Logistics Engine
                    final orderId = data['order_id'];
                    await widget.state.orders.updateOrderStatus(
                      orderId, 
                      'processing', 
                      'Vendor has prepared the item and is requesting a delivery partner.'
                    );
                    // Refresh view
                    setState(() {});
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(color: C.brand, borderRadius: BorderRadius.circular(8)),
                    child: Text('READY FOR PICKUP', style: syne(sz: 10, w: FontWeight.bold, c: Colors.white)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
