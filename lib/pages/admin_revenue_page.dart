import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../navigation/app_header.dart';
import '../widgets/theme.dart';

class AdminRevenuePage extends StatefulWidget {
  const AdminRevenuePage({super.key});

  @override
  State<AdminRevenuePage> createState() => _AdminRevenuePageState();
}

class _AdminRevenuePageState extends State<AdminRevenuePage> {
  String _period = 'This Month';
  final periods = ['Today', 'This Week', 'This Month', 'This Year', 'All Time'];

  // Firestore-driven totals
  double commissionsTotal = 0;
  double subscriptionsTotal = 0;
  double promoSlotsTotal = 0;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchRevenue();
  }

  Future<void> _fetchRevenue() async {
    setState(() => isLoading = true);
    try {
      // Commissions from global_orders
      final ordersSnap = await FirebaseFirestore.instance
          .collection('global_orders')
          .get();

      double commissions = 0;
      for (final doc in ordersSnap.docs) {
        final data = doc.data();
        final commission = data['commissionAmount'] ?? 0;
        commissions += commission is num ? commission.toDouble() : 0;
      }

      // Subscriptions from subscription_payments
      final subsSnap = await FirebaseFirestore.instance
          .collection('subscription_payments')
          .get();

      double subscriptions = 0;
      for (final doc in subsSnap.docs) {
        final data = doc.data();
        final amount = data['amount'] ?? 0;
        subscriptions += amount is num ? amount.toDouble() : 0;
      }

      // Promo slots from promo_slot_payments
      final promoSnap = await FirebaseFirestore.instance
          .collection('promo_slot_payments')
          .get();

      double promoSlots = 0;
      for (final doc in promoSnap.docs) {
        final data = doc.data();
        final amount = data['amount'] ?? 0;
        promoSlots += amount is num ? amount.toDouble() : 0;
      }

      if (!mounted) return;
      setState(() {
        commissionsTotal = commissions;
        subscriptionsTotal = subscriptions;
        promoSlotsTotal = promoSlots;
        isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => isLoading = false);
    }
  }

  double get grandTotal =>
      commissionsTotal + subscriptionsTotal + promoSlotsTotal;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(showBackButton: true),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.deepAccent,
                onRefresh: _fetchRevenue,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Revenue Breakdown',
                        style: AppTextStyles.displayMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Platform earnings across all revenue streams.',
                        style: AppTextStyles.bodySmall,
                      ),
                      const SizedBox(height: 20),

                      // ── Period selector ─────────────────────────────
                      SizedBox(
                        height: 36,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: periods.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final p = periods[index];
                            final isSelected = _period == p;
                            return GestureDetector(
                              onTap: () {
                                setState(() => _period = p);
                                _fetchRevenue();
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.deepAccent
                                      : Colors.transparent,
                                  border: Border.all(
                                    color: isSelected
                                        ? AppColors.deepAccent
                                        : AppColors.border,
                                    width: 0.5,
                                  ),
                                ),
                                child: Text(
                                  p,
                                  style: AppTextStyles.capsLabel.copyWith(
                                    fontSize: 10,
                                    color: isSelected
                                        ? Colors.white
                                        : AppColors.secondaryText,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                      const SizedBox(height: 20),

                      if (isLoading)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 60),
                            child: CircularProgressIndicator(
                              color: AppColors.deepAccent,
                              strokeWidth: 1.5,
                            ),
                          ),
                        )
                      else ...[
                        // ── Total card ──────────────────────────────
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppColors.deepAccent,
                            border: Border.all(
                              color: AppColors.deepAccent,
                              width: 0.5,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'TOTAL REVENUE',
                                style: AppTextStyles.capsLabel.copyWith(
                                  color: Colors.white70,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'KD ${grandTotal.toStringAsFixed(2)}',
                                style: AppTextStyles.displayMedium.copyWith(
                                  color: Colors.white,
                                  fontStyle: FontStyle.normal,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _period,
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: Colors.white60,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 14),

                        // ── Breakdown cards ─────────────────────────
                        _revenueCard(
                          icon: Icons.percent_outlined,
                          label: 'Commissions',
                          subtitle: 'Earned from boutique sales',
                          amount: commissionsTotal,
                          percentage: grandTotal > 0
                              ? (commissionsTotal / grandTotal * 100)
                              : 0,
                        ),
                        _revenueCard(
                          icon: Icons.subscriptions_outlined,
                          label: 'Subscriptions',
                          subtitle: 'Monthly & yearly tier fees',
                          amount: subscriptionsTotal,
                          percentage: grandTotal > 0
                              ? (subscriptionsTotal / grandTotal * 100)
                              : 0,
                        ),
                        _revenueCard(
                          icon: Icons.campaign_outlined,
                          label: 'Promo Slots',
                          subtitle: 'Banners, featured listings & search',
                          amount: promoSlotsTotal,
                          percentage: grandTotal > 0
                              ? (promoSlotsTotal / grandTotal * 100)
                              : 0,
                        ),

                        const SizedBox(height: 20),

                        // ── Promo slot breakdown ─────────────────────
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            border: Border.all(
                              color: AppColors.border,
                              width: 0.5,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'PROMO SLOT TYPES',
                                style: AppTextStyles.capsLabel,
                              ),
                              const SizedBox(height: 14),
                              _promoRow(
                                'Homepage Banner',
                                'KD 12/day · KD 65/week',
                              ),
                              _promoRow(
                                'Featured Boutiques',
                                'KD 7/day · KD 38/week',
                              ),
                              _promoRow(
                                'Featured Products',
                                'KD 4/day · KD 22/week',
                              ),
                              _promoRow(
                                'Search Placement',
                                'KD 5/day · KD 28/week',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _revenueCard({
    required IconData icon,
    required String label,
    required String subtitle,
    required double amount,
    required double percentage,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.deepAccent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: AppTextStyles.labelLarge),
                    Text(subtitle, style: AppTextStyles.bodySmall),
                  ],
                ),
              ),
              Text(
                'KD ${amount.toStringAsFixed(2)}',
                style: AppTextStyles.headingSmall,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Progress bar
          ClipRect(
            child: Align(
              alignment: Alignment.centerLeft,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    children: [
                      Container(
                        width: constraints.maxWidth,
                        height: 4,
                        color: AppColors.field,
                      ),
                      Container(
                        width:
                            constraints.maxWidth *
                            (percentage / 100).clamp(0.0, 1.0),
                        height: 4,
                        color: AppColors.deepAccent,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${percentage.toStringAsFixed(1)}% of total revenue',
            style: AppTextStyles.bodySmall.copyWith(fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _promoRow(String type, String pricing) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(child: Text(type, style: AppTextStyles.bodyMedium)),
          Text(pricing, style: AppTextStyles.bodySmall),
        ],
      ),
    );
  }
}
