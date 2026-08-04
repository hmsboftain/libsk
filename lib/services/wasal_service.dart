import 'package:cloud_functions/cloud_functions.dart';

/// A Wasal delivery area (governorate or neighborhood), bilingual.
class WasalArea {
  final String id;
  final String nameEn;
  final String nameAr;

  const WasalArea({required this.id, required this.nameEn, required this.nameAr});

  String nameFor(String localeCode) =>
      localeCode == 'ar' && nameAr.isNotEmpty ? nameAr : nameEn;
}

class WasalGovernorate extends WasalArea {
  final List<WasalArea> neighborhoods;

  const WasalGovernorate({
    required super.id,
    required super.nameEn,
    required super.nameAr,
    required this.neighborhoods,
  });
}

/// Client for the Wasal delivery Cloud Functions.
///
/// All Wasal API access is server-side (the API key never ships in the app);
/// this service only calls our own callables:
/// - `getWasalAreas` — cached governorate→neighborhood tree for address forms
/// - `getWasalDeliveryFee` — live area fee quote for checkout
/// - `markReadyForPickup` — boutique owner dispatches a delivery
class WasalService {
  final FirebaseFunctions _functions;

  WasalService({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  static final WasalService instance = WasalService();

  List<WasalGovernorate>? _areasCache;

  /// Governorates with their neighborhoods, cached for the app session.
  Future<List<WasalGovernorate>> getAreas() async {
    final cached = _areasCache;
    if (cached != null) return cached;

    final callable = _functions.httpsCallable('getWasalAreas');
    final result = await callable.call<Map<String, dynamic>>({});
    final raw = result.data['governorates'] as List<dynamic>? ?? [];

    final areas = raw.map((g) {
      final gm = Map<String, dynamic>.from(g as Map);
      final ns = (gm['neighborhoods'] as List<dynamic>? ?? []).map((n) {
        final nm = Map<String, dynamic>.from(n as Map);
        return WasalArea(
          id: nm['id']?.toString() ?? '',
          nameEn: nm['nameEn']?.toString() ?? '',
          nameAr: nm['nameAr']?.toString() ?? '',
        );
      }).toList();
      return WasalGovernorate(
        id: gm['id']?.toString() ?? '',
        nameEn: gm['nameEn']?.toString() ?? '',
        nameAr: gm['nameAr']?.toString() ?? '',
        neighborhoods: ns,
      );
    }).toList();

    _areasCache = areas;
    return areas;
  }

  /// Delivery fee (KWD) for one boutique pickup to the given area, or null
  /// when area pricing is unavailable — callers fall back to the flat fee,
  /// mirroring the server's own fallback in createOrder.
  Future<double?> getDeliveryFee({
    required String governorateId,
    required String neighborhoodId,
  }) async {
    try {
      final callable = _functions.httpsCallable('getWasalDeliveryFee');
      final result = await callable.call<Map<String, dynamic>>({
        'governorateId': governorateId,
        'neighborhoodId': neighborhoodId,
      });
      final fee = result.data['fee'];
      if (fee is num) return fee.toDouble();
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Boutique owner: dispatch a Wasal delivery for a packed sub-order.
  /// Returns the Wasal order number. Throws [FirebaseFunctionsException]
  /// with a human-readable message on failure.
  Future<String> markReadyForPickup({required String boutiqueOrderId}) async {
    final callable = _functions.httpsCallable('markReadyForPickup');
    final result = await callable.call<Map<String, dynamic>>({
      'boutiqueOrderId': boutiqueOrderId,
    });
    return result.data['wasalOrderNumber']?.toString() ?? '';
  }
}
