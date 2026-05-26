import 'package:cloud_firestore/cloud_firestore.dart';

/// Domain model for an order document.
///
/// Named [AppOrder] to avoid clashing with `dart:core`'s implicit `Order`
/// concept; the factory name in the spec ([Order.fromFirestore]) is preserved
/// via a type alias for backwards compatibility with callers that already
/// import this file.
class AppOrder {
  final String id;
  final String orderNumber;
  final String status;
  final double total;
  final int itemCount;
  final String deliveryMethod;
  final String paymentMethod;
  final DateTime? createdAt;
  final List<Map<String, dynamic>> items;

  const AppOrder({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.total,
    required this.itemCount,
    required this.deliveryMethod,
    required this.paymentMethod,
    required this.createdAt,
    required this.items,
  });

  factory AppOrder.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final rawItems = data['items'];
    final items = rawItems is List
        ? rawItems
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList()
        : <Map<String, dynamic>>[];

    return AppOrder(
      id: doc.id,
      orderNumber: (data['orderNumber'] ?? '').toString(),
      status: (data['status'] ?? '').toString(),
      total: _parseDouble(data['total']),
      itemCount: _parseInt(data['itemCount']),
      deliveryMethod: (data['deliveryMethod'] ?? '').toString(),
      paymentMethod: (data['paymentMethod'] ?? '').toString(),
      createdAt: _parseTimestamp(data['createdAt']),
      items: items,
    );
  }

  static double _parseDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value == null) return 0;
    return double.tryParse(value.toString()) ?? 0;
  }

  static int _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value == null) return 0;
    return int.tryParse(value.toString()) ?? 0;
  }

  static DateTime? _parseTimestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}

/// Convenience alias matching the spec name.
typedef Order = AppOrder;
