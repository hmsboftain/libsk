import 'package:cloud_firestore/cloud_firestore.dart';

/// Domain model for a boutique document stored under `boutiques/{id}`.
class Boutique {
  final String id;
  final String name;
  final String description;
  final String logoPath;
  final String bannerPath;
  final String tier;
  final bool isApproved;
  final bool isVisibleOnHome;
  final int homeOrder;
  final DateTime? homeExpiresAt;

  const Boutique({
    required this.id,
    required this.name,
    required this.description,
    required this.logoPath,
    required this.bannerPath,
    required this.tier,
    required this.isApproved,
    required this.isVisibleOnHome,
    required this.homeOrder,
    required this.homeExpiresAt,
  });

  factory Boutique.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};

    return Boutique(
      id: doc.id,
      name: (data['name'] ?? '').toString(),
      description: (data['description'] ?? '').toString(),
      logoPath: (data['logoPath'] ?? '').toString(),
      bannerPath: (data['bannerPath'] ?? '').toString(),
      tier: (data['tier'] ?? '').toString(),
      isApproved: data['isApproved'] == true,
      isVisibleOnHome: data['isVisibleOnHome'] == true,
      homeOrder: _parseInt(data['homeOrder']),
      homeExpiresAt: _parseTimestamp(data['homeExpiresAt']),
    );
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
