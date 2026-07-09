import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../app_state.dart';

class OrderTrackingService {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  final AppState state;

  OrderTrackingService(this.state);

  // ── ORDER CREATION (The Financial Handshake) ──────────────────
  Future<String> createOrder({
    required Map<String, dynamic> listing,
    required double totalAmount,
    required String deliveryAddress,
    required String paymentMethod,
  }) async {
    final orderId = 'ORD-${DateTime.now().millisecondsSinceEpoch}';
    final userId = state.user?.id ?? 'anonymous';

    final orderData = {
      'order_id': orderId,
      'customer_id': userId,
      'vendor_id': listing['user_id'],
      'listing_id': listing['id'],
      'product_title': listing['title'],
      'product_thumbnail': (listing['photos'] as List?)?.first ?? listing['media_url'],
      'amount': totalAmount,
      'status': 'pending_payment',
      'payment_method': paymentMethod,
      'delivery_address': deliveryAddress,
      'created_at': FieldValue.serverTimestamp(),
      'driver_id': null,      // 🚚 To be assigned
      'driver_name': null,
      'driver_phone': null,
      'driver_lat': null,
      'driver_lng': null,
      'tracking_history': [
        {
          'status': 'Order Placed',
          'timestamp': DateTime.now().toIso8601String(),
          'message': 'Your order has been received and is awaiting payment confirmation.',
        }
      ],
    };

    try {
      await _firestore.collection('orders').doc(orderId).set(orderData);
      debugPrint('🔥 Firebase: Order $orderId created successfully.');
      return orderId;
    } catch (e) {
      debugPrint('❌ Firebase Order Error: $e');
      throw Exception('Failed to finalize order: $e');
    }
  }

  // ── LIVE TRACKING STREAM ──────────────────────────────────────
  Stream<DocumentSnapshot> streamOrder(String orderId) {
    return _firestore.collection('orders').doc(orderId).snapshots();
  }

  // ── STATUS UPDATES (For Vendor/Logistics Side) ────────────────
  Future<void> updateOrderStatus(String orderId, String newStatus, String message) async {
    await _firestore.collection('orders').doc(orderId).update({
      'status': newStatus,
      'tracking_history': FieldValue.arrayUnion([
        {
          'status': newStatus,
          'timestamp': DateTime.now().toIso8601String(),
          'message': message,
        }
      ]),
    });
  }
  
  // ── DRIVER COORDINATION ───────────────────────────────────────
  Future<void> assignDriver(String orderId, Map<String, dynamic> driverInfo) async {
    await _firestore.collection('orders').doc(orderId).update({
      'driver_id':    driverInfo['id'],
      'driver_name':  driverInfo['name'],
      'driver_phone': driverInfo['phone'],
      'status':       'driver_assigned',
      'tracking_history': FieldValue.arrayUnion([
        {
          'status': 'Driver Assigned',
          'timestamp': DateTime.now().toIso8601String(),
          'message': '${driverInfo['name']} is heading to pick up your order.',
        }
      ]),
    });
  }

  Future<void> updateDriverLocation(String orderId, double lat, double lng) async {
    await _firestore.collection('orders').doc(orderId).update({
      'driver_lat': lat,
      'driver_lng': lng,
    });
  }

  Stream<QuerySnapshot> streamUserOrders() {
    final userId = state.user?.id ?? 'anonymous';
    return _firestore
        .collection('orders')
        .where('customer_id', isEqualTo: userId)
        .orderBy('created_at', descending: true)
        .snapshots();
  }

  // ── VENDOR ORDER QUEUE ────────────────────────────────────────
  Stream<QuerySnapshot> streamVendorOrders() {
    final userId = state.user?.id ?? 'anonymous';
    return _firestore
        .collection('orders')
        .where('vendor_id', isEqualTo: userId)
        .orderBy('created_at', descending: true)
        .snapshots();
  }
}
