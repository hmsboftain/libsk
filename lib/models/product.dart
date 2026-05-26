import 'package:cloud_firestore/cloud_firestore.dart';

/// Domain model for a product document stored under
/// `boutiques/{boutiqueId}/products/{productId}`.
///
/// All Firestore parsing lives in [Product.fromFirestore]. Pages should never
/// pull raw `Map<String, dynamic>` fields directly.
class Product {
  final String id;
  final String boutiqueId;
  final String boutiqueName;
  final String title;
  final String description;
  final double price;
  final int stock;
  final String imageUrl;
  final List<String> imageUrls;
  final List<String> sizes;
  final List<String> categories;
  final List<String> colors;
  final bool madeToOrder;
  final String? deliveryTimeframe;

  const Product({
    required this.id,
    required this.boutiqueId,
    required this.boutiqueName,
    required this.title,
    required this.description,
    required this.price,
    required this.stock,
    required this.imageUrl,
    required this.imageUrls,
    required this.sizes,
    required this.categories,
    required this.colors,
    required this.madeToOrder,
    required this.deliveryTimeframe,
  });

  factory Product.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    // Products live under boutiques/{boutiqueId}/products/{productId}, so the
    // parent's parent gives us the owning boutique id when available.
    final boutiqueId = doc.reference.parent.parent?.id ?? '';

    return Product(
      id: doc.id,
      boutiqueId: boutiqueId,
      boutiqueName: (data['boutiqueName'] ?? '').toString(),
      title: (data['title'] ?? '').toString(),
      description: (data['description'] ?? '').toString(),
      price: _parseDouble(data['price']),
      stock: _parseInt(data['stock']),
      imageUrl: (data['imageUrl'] ?? '').toString(),
      imageUrls: _parseStringList(data['imageUrls']),
      sizes: _parseStringList(data['sizes']),
      categories: _parseStringList(data['categories']),
      colors: _parseStringList(data['colors']),
      madeToOrder: data['madeToOrder'] == true,
      deliveryTimeframe: data['deliveryTimeframe']?.toString(),
    );
  }

  String get displayImageUrl =>
      imageUrls.isNotEmpty ? imageUrls.first : imageUrl;

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

  static List<String> _parseStringList(dynamic value) {
    if (value is List) {
      return value
          .map((e) => e?.toString() ?? '')
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return const [];
  }
}
