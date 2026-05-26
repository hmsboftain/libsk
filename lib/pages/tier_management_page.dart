import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../navigation/app_header.dart';
import '../services/firestore_service.dart';
import '../widgets/theme.dart';

class TierManagementPage extends StatefulWidget {
  const TierManagementPage({super.key});

  @override
  State<TierManagementPage> createState() => _TierManagementPageState();
}

class _TierManagementPageState extends State<TierManagementPage> {
  bool isYearly = false;
  bool isLoading = false;
  String? currentTier;
  String? boutiqueId;

  final tiers = [
    {
      'name': 'Basic',
      'key': 'basic',
      'monthlyPrice': 40,
      'yearlyPrice': 400,
      'commission': '12%',
      'products': '20 products',
      'images': '3 images/product',
      'collections': '2 collections',
      'analytics': 'Basic analytics',
      'support': 'Standard support',
      'discountCodes': false,
      'verifiedBadge': false,
    },
    {
      'name': 'Pro',
      'key': 'pro',
      'monthlyPrice': 70,
      'yearlyPrice': 700,
      'commission': '8%',
      'products': '100 products',
      'images': '6 images/product',
      'collections': '10 collections',
      'analytics': 'Advanced analytics',
      'support': 'Priority support',
      'discountCodes': true,
      'verifiedBadge': false,
    },
    {
      'name': 'Elite',
      'key': 'elite',
      'monthlyPrice': 120,
      'yearlyPrice': 1200,
      'commission': '4%',
      'products': 'Unlimited',
      'images': '10 images/product',
      'collections': 'Unlimited',
      'analytics': 'Full analytics',
      'support': 'Dedicated support',
      'discountCodes': true,
      'verifiedBadge': true,
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadCurrentTier();
  }

  Future<void> _loadCurrentTier() async {
    try {
      final ownerData = await FirestoreService.getCurrentOwnerData();
      if (!mounted) return;
      setState(() {
        currentTier = ownerData?['tier']?.toString() ?? 'basic';
        boutiqueId = ownerData?['boutiqueId']?.toString();
      });
    } catch (_) {}
  }

  Future<void> _requestUpgrade(String tierKey) async {
    setState(() => isLoading = true);
    try {
      if (boutiqueId != null) {
        await FirebaseFirestore.instance
            .collection('boutiques')
            .doc(boutiqueId)
            .update({
              'pendingTierUpgrade': tierKey,
              'billingCycle': isYearly ? 'yearly' : 'monthly',
              'upgradeRequestedAt': FieldValue.serverTimestamp(),
            });
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Upgrade request submitted. Our team will contact you shortly.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  int _tierIndex(String? tier) {
    switch (tier) {
      case 'pro':
        return 1;
      case 'elite':
        return 2;
      default:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(showBackButton: true),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tier Management', style: AppTextStyles.displayMedium),
                    const SizedBox(height: 4),
                    Text(
                      'View your current plan and upgrade options.',
                      style: AppTextStyles.bodySmall,
                    ),
                    const SizedBox(height: 20),

                    // ── Current Tier ────────────────────────────────
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.selectedSoft,
                        border: Border.all(
                          color: AppColors.deepAccent,
                          width: 0.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check_circle_outline,
                            color: AppColors.deepAccent,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Current plan: ${currentTier?.toUpperCase() ?? '...'}',
                            style: AppTextStyles.labelLarge.copyWith(
                              color: AppColors.deepAccent,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ── Billing Toggle ──────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppColors.field,
                        border: Border.all(color: AppColors.border, width: 0.5),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => isYearly = false),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                color: !isYearly
                                    ? AppColors.deepAccent
                                    : Colors.transparent,
                                child: Center(
                                  child: Text(
                                    'Monthly',
                                    style: AppTextStyles.labelLarge.copyWith(
                                      color: !isYearly
                                          ? Colors.white
                                          : AppColors.secondaryText,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => isYearly = true),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                color: isYearly
                                    ? AppColors.deepAccent
                                    : Colors.transparent,
                                child: Center(
                                  child: Column(
                                    children: [
                                      Text(
                                        'Yearly',
                                        style: AppTextStyles.labelLarge
                                            .copyWith(
                                              color: isYearly
                                                  ? Colors.white
                                                  : AppColors.secondaryText,
                                            ),
                                      ),
                                      Text(
                                        '2 months free',
                                        style: AppTextStyles.bodySmall.copyWith(
                                          fontSize: 10,
                                          color: isYearly
                                              ? Colors.white70
                                              : AppColors.softAccent,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Tier Cards ──────────────────────────────────
                    ...tiers.asMap().entries.map((entry) {
                      final tier = entry.value;
                      final tierKey = tier['key'] as String;
                      final isCurrent = currentTier == tierKey;
                      final isUpgrade =
                          _tierIndex(tierKey) > _tierIndex(currentTier);
                      final monthlyPrice = tier['monthlyPrice'] as int;
                      final yearlyPrice = tier['yearlyPrice'] as int;
                      final displayPrice = isYearly
                          ? yearlyPrice
                          : monthlyPrice;
                      final billingLabel = isYearly ? '/yr' : '/mo';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? AppColors.selectedSoft
                              : AppColors.card,
                          border: Border.all(
                            color: isCurrent
                                ? AppColors.deepAccent
                                : AppColors.border,
                            width: isCurrent ? 1 : 0.5,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  tier['name'] as String,
                                  style: AppTextStyles.headingSmall,
                                ),
                                const SizedBox(width: 8),
                                if (isCurrent)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    color: AppColors.deepAccent,
                                    child: Text(
                                      'CURRENT',
                                      style: AppTextStyles.capsLabel.copyWith(
                                        color: Colors.white,
                                        fontSize: 9,
                                      ),
                                    ),
                                  ),
                                const Spacer(),
                                Text(
                                  'KD $displayPrice$billingLabel',
                                  style: AppTextStyles.labelLarge.copyWith(
                                    color: AppColors.deepAccent,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            const Divider(
                              color: AppColors.border,
                              thickness: 0.5,
                            ),
                            const SizedBox(height: 10),
                            _featureRow(
                              Icons.percent_outlined,
                              '${tier['commission']} commission',
                            ),
                            _featureRow(
                              Icons.inventory_2_outlined,
                              tier['products'] as String,
                            ),
                            _featureRow(
                              Icons.photo_library_outlined,
                              tier['images'] as String,
                            ),
                            _featureRow(
                              Icons.folder_outlined,
                              tier['collections'] as String,
                            ),
                            _featureRow(
                              Icons.analytics_outlined,
                              tier['analytics'] as String,
                            ),
                            _featureRow(
                              Icons.support_agent_outlined,
                              tier['support'] as String,
                            ),
                            if (tier['discountCodes'] == true)
                              _featureRow(
                                Icons.local_offer_outlined,
                                'Discount codes',
                              ),
                            if (tier['verifiedBadge'] == true)
                              _featureRow(
                                Icons.verified_outlined,
                                'LIBSK verified badge',
                              ),
                            if (isUpgrade) ...[
                              const SizedBox(height: 14),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: isLoading
                                      ? null
                                      : () => _requestUpgrade(tierKey),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.deepAccent,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.zero,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                  ),
                                  child: Text(
                                    'Upgrade to ${tier['name']}',
                                    style: AppTextStyles.button,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _featureRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 15, color: AppColors.secondaryText),
          const SizedBox(width: 8),
          Text(text, style: AppTextStyles.bodySmall),
        ],
      ),
    );
  }
}
