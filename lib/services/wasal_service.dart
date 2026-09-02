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

  /// Customer live tracking for one of their own orders — the delivery
  /// timeline (statusHistory) plus the driver's latest location. The server
  /// verifies the caller owns [orderId] and fetches everything from Wasal with
  /// the merchant key (never shipped to the app). An order can carry more than
  /// one delivery (multi-boutique), so this returns a list. Throws
  /// [FirebaseFunctionsException] on failure so callers can fall back to the
  /// last-known status.
  Future<List<WasalDeliveryTracking>> getTracking({
    required String orderId,
  }) async {
    final callable = _functions.httpsCallable('getWasalTracking');
    final result = await callable.call<Map<String, dynamic>>({
      'orderId': orderId,
    });
    final raw = result.data['deliveries'] as List<dynamic>? ?? [];
    return raw
        .map((d) => WasalDeliveryTracking.fromMap(Map<String, dynamic>.from(d as Map)))
        .toList();
  }
}

/// The driver's latest known position for a delivery.
class WasalAgentLocation {
  final double lat;
  final double lng;
  final String? lastSeen;

  const WasalAgentLocation({required this.lat, required this.lng, this.lastSeen});
}

/// One entry in a delivery's status timeline.
class WasalStatusEvent {
  final String status;
  final DateTime? timestamp;
  final String? note;

  const WasalStatusEvent({required this.status, this.timestamp, this.note});
}

/// Live tracking for a single delivery, from the `getWasalTracking` callable.
///
/// Note: the server also returns the driver's phone, but it is deliberately not
/// modelled or surfaced here — showing a driver's personal number to customers
/// is a separate product decision.
class WasalDeliveryTracking {
  final String wasalOrderNumber;
  final String status;
  final WasalAgentLocation? agentLocation;
  final List<WasalStatusEvent> statusHistory;
  final bool isActiveDelivery;

  const WasalDeliveryTracking({
    required this.wasalOrderNumber,
    required this.status,
    required this.agentLocation,
    required this.statusHistory,
    required this.isActiveDelivery,
  });

  /// Terminal delivery states — polling should stop once every delivery is here.
  static const terminalStatuses = {
    'delivered',
    'failed',
    'returned',
    'cancelled',
  };

  bool get isTerminal => terminalStatuses.contains(status);

  factory WasalDeliveryTracking.fromMap(Map<String, dynamic> data) {
    WasalAgentLocation? loc;
    final rawLoc = data['agentLocation'];
    if (rawLoc is Map) {
      final lat = rawLoc['lat'];
      final lng = rawLoc['lng'];
      if (lat is num && lng is num) {
        loc = WasalAgentLocation(
          lat: lat.toDouble(),
          lng: lng.toDouble(),
          lastSeen: rawLoc['lastSeen']?.toString(),
        );
      }
    }

    final rawHistory = data['statusHistory'] as List<dynamic>? ?? [];
    final history = rawHistory.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      return WasalStatusEvent(
        status: m['status']?.toString() ?? '',
        timestamp: DateTime.tryParse(m['timestamp']?.toString() ?? '')?.toLocal(),
        note: m['note']?.toString(),
      );
    }).where((e) => e.status.isNotEmpty).toList();

    return WasalDeliveryTracking(
      wasalOrderNumber: data['wasalOrderNumber']?.toString() ?? '',
      status: data['status']?.toString() ?? '',
      agentLocation: loc,
      statusHistory: history,
      isActiveDelivery: data['isActiveDelivery'] == true,
    );
  }
}
