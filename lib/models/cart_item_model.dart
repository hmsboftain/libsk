import 'package:cloud_firestore/cloud_firestore.dart';

/// Domain model for a cart item document.
class CartItemModel {
  final String docId;
  final String productId;
  final String boutiqueId;
  final String title;
  final String description;
  final String imageUrl;
  final String size;
  final String color;
  final double price;
  final int quantity;

  const CartItemModel({
    required this.docId,
    required this.productId,
    required this.boutiqueId,
    required this.title,
    required this.description,
    required this.imageUrl,
    required this.size,
    required this.color,
    required this.price,
    required this.quantity,
  });

  factory CartItemModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};

    return CartItemModel(
      docId: doc.id,
      productId: (data['productId'] ?? '').toString(),
      boutiqueId: (data['boutiqueId'] ?? '').toString(),
      title: (data['title'] ?? '').toString(),
      description: (data['description'] ?? '').toString(),
      imageUrl: (data['imageUrl'] ?? '').toString(),
      size: (data['size'] ?? '').toString(),
      color: (data['color'] ?? '').toString(),
      price: _parseDouble(data['price']),
      quantity: _parseInt(data['quantity'], fallback: 1),
    );
  }

  static double _parseDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value == null) return 0;
    return double.tryParse(value.toString()) ?? 0;
  }

  static int _parseInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value == null) return fallback;
    return int.tryParse(value.toString()) ?? fallback;
  }
}
