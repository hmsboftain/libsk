/// Typed view of the `getPromoAvailability` Cloud Function response.
///
/// PRICE INTEGRITY: every price the dashboard shows comes from the
/// server-computed `priceByDays` / `priceByPosts` tables in this payload — the
/// same `promoPrice()` logic `createPromoBooking` charges through. Nothing in
/// the Flutter layer multiplies a daily rate or re-derives a weekly total, so
/// the number on screen can never drift from what Payzah bills. Callers must
/// only ever *look up* a price here, never compute one.
library;

/// Day indices are Sun=0 … Sat=6 throughout, matching the server (Kuwait's week
/// runs Sunday–Saturday).
class PromoAvailability {
  final DateTime weekStart;
  final DateTime weekEnd;
  final int globalCap;

  /// Remaining day-placement slots this boutique may still take, per day (len 7).
  final List<int> globalRemainingPerDay;
  final Map<String, PromoPlacement> placements;

  /// Live, spendable founding-partner promo credit in KWD (0 if none). Computed
  /// server-side from the actual unexpired grants, so it matches what a booking
  /// would really apply. Drives the "Use promo credit" checkbox at booking.
  final double promoCreditBalance;

  const PromoAvailability({
    required this.weekStart,
    required this.weekEnd,
    required this.globalCap,
    required this.globalRemainingPerDay,
    required this.placements,
    required this.promoCreditBalance,
  });

  factory PromoAvailability.fromMap(Map<String, dynamic> data) {
    final placements = <String, PromoPlacement>{};
    final raw = Map<String, dynamic>.from(data['placements'] as Map? ?? {});
    raw.forEach((type, value) {
      placements[type] = PromoPlacement.fromMap(
        type,
        Map<String, dynamic>.from(value as Map),
      );
    });
    return PromoAvailability(
      weekStart: _asDate(data['weekStart']),
      weekEnd: _asDate(data['weekEnd']),
      globalCap: (data['globalCap'] as num?)?.toInt() ?? 3,
      globalRemainingPerDay: _asIntList(data['globalRemainingPerDay']),
      placements: placements,
      promoCreditBalance: (data['promoCreditBalance'] as num?)?.toDouble() ?? 0,
    );
  }

  PromoPlacement? placement(String type) => placements[type];
}

/// Availability + the authoritative price table for one placement.
class PromoPlacement {
  final String type;

  /// false only for `feed_sponsored` (week-only, no day picker).
  final bool dayBased;

  /// Price by number of days, index 1..7 (index 0 unused). Day placements only.
  final List<double?> priceByDays;

  /// Price by number of feed posts (1 or 2). `feed_sponsored` only.
  final Map<int, double> priceByPosts;

  // Normal day placements (home_banner, featured_product, featured_boutique):
  final List<int> remainingPerDay; // len 7, or empty
  final List<int> minePerDay; // len 7, or empty
  final int? perBoutique;

  // top_of_category (counted in items, per category, per day):
  final bool perCategory;
  final int? perCategoryCapacity;
  final int? perCategoryPerBoutique;
  final Map<String, PromoCategoryUsage> categories;

  // feed_sponsored:
  final bool unlimited;
  final int mineHeld;

  const PromoPlacement({
    required this.type,
    required this.dayBased,
    required this.priceByDays,
    required this.priceByPosts,
    required this.remainingPerDay,
    required this.minePerDay,
    required this.perBoutique,
    required this.perCategory,
    required this.perCategoryCapacity,
    required this.perCategoryPerBoutique,
    required this.categories,
    required this.unlimited,
    required this.mineHeld,
  });

  factory PromoPlacement.fromMap(String type, Map<String, dynamic> m) {
    final isFeed = m['weekly'] == true; // only feed sets weekly:true here
    final priceByPosts = <int, double>{};
    if (m['priceByPosts'] is Map) {
      Map<String, dynamic>.from(m['priceByPosts'] as Map).forEach((k, v) {
        final posts = int.tryParse(k);
        if (posts != null && v is num) priceByPosts[posts] = v.toDouble();
      });
    }
    final categories = <String, PromoCategoryUsage>{};
    if (m['categories'] is Map) {
      Map<String, dynamic>.from(m['categories'] as Map).forEach((cat, v) {
        categories[cat] = PromoCategoryUsage.fromMap(Map<String, dynamic>.from(v as Map));
      });
    }
    return PromoPlacement(
      type: type,
      dayBased: !isFeed,
      priceByDays: _asDoubleNullableList(m['priceByDays']),
      priceByPosts: priceByPosts,
      remainingPerDay: _asIntList(m['remainingPerDay']),
      minePerDay: _asIntList(m['minePerDay']),
      perBoutique: (m['perBoutique'] as num?)?.toInt(),
      perCategory: m['perCategory'] != null || m['perCategoryCapacity'] != null,
      perCategoryCapacity: (m['perCategoryCapacity'] as num?)?.toInt(),
      perCategoryPerBoutique: (m['perCategoryPerBoutique'] as num?)?.toInt(),
      categories: categories,
      unlimited: m['unlimited'] == true,
      mineHeld: (m['mineHeld'] as num?)?.toInt() ?? 0,
    );
  }

  /// Server-computed price for [numDays] (1..7). Never computed client-side.
  double? priceForDays(int numDays) {
    if (numDays < 1 || numDays >= priceByDays.length) return null;
    return priceByDays[numDays];
  }

  /// Server-computed price for [posts] feed posts (1 or 2).
  double? priceForPosts(int posts) => priceByPosts[posts];

  /// The flat full-week price, if offered (used by the "extend to full week"
  /// nudge). Still a lookup — never recomputed.
  double? get fullWeekPrice => priceForDays(7);

  /// Whether booking the full week is cheaper than [numDays] separate days —
  /// the intentional "6 days can cost more than 7" case. Pure comparison of two
  /// server prices.
  bool fullWeekIsCheaperThan(int numDays) {
    if (numDays >= 7) return false;
    final part = priceForDays(numDays);
    final full = fullWeekPrice;
    if (part == null || full == null) return false;
    return full < part;
  }

  // ── Per-day availability for the calendar picker ──────────────────────────

  int _at(List<int> list, int day) =>
      (day >= 0 && day < list.length) ? list[day] : 0;

  /// Can this boutique add one booking of this normal day-placement on [day]?
  /// (home_banner / featured_product / featured_boutique.)
  bool normalDayOpen(int day, {required List<int> globalRemainingPerDay}) {
    if (_at(globalRemainingPerDay, day) < 1) return false; // global cap
    if (_at(remainingPerDay, day) < 1) return false; // placement capacity
    final lim = perBoutique;
    if (lim != null && _at(minePerDay, day) >= lim) return false; // own limit
    return true;
  }

  /// Remaining promoted items in [category] on [day] (missing category = fully
  /// open, so remaining = full capacity).
  int categoryRemainingItems(String category, int day) {
    final cap = perCategoryCapacity ?? 0;
    final used = categories[category]?.usedOn(day) ?? 0;
    final r = cap - used;
    return r < 0 ? 0 : r;
  }

  /// Can this boutique pin [itemCount] products in [category] on [day]?
  bool categoryDayOpen(
    String category,
    int day,
    int itemCount, {
    required List<int> globalRemainingPerDay,
  }) {
    if (_at(globalRemainingPerDay, day) < 1) return false;
    if (categoryRemainingItems(category, day) < itemCount) return false;
    final mine = categories[category]?.mineOn(day) ?? 0;
    final lim = perCategoryPerBoutique ?? 0;
    if (mine + itemCount > lim) return false;
    return true;
  }
}

class PromoCategoryUsage {
  final List<int> usedPerDay;
  final List<int> minePerDay;
  const PromoCategoryUsage(this.usedPerDay, this.minePerDay);

  factory PromoCategoryUsage.fromMap(Map<String, dynamic> m) => PromoCategoryUsage(
        _asIntList(m['usedPerDay']),
        _asIntList(m['minePerDay']),
      );

  int usedOn(int d) => (d >= 0 && d < usedPerDay.length) ? usedPerDay[d] : 0;
  int mineOn(int d) => (d >= 0 && d < minePerDay.length) ? minePerDay[d] : 0;
}

DateTime _asDate(dynamic v) => v is num
    ? DateTime.fromMillisecondsSinceEpoch(v.toInt())
    : DateTime.now();

List<int> _asIntList(dynamic v) => v is List
    ? v.map((e) => (e as num?)?.toInt() ?? 0).toList()
    : const [];

List<double?> _asDoubleNullableList(dynamic v) => v is List
    ? v.map((e) => (e as num?)?.toDouble()).toList()
    : const [];
