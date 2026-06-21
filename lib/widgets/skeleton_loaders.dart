import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import 'theme.dart';

/// Single shimmering rectangle used as a building block for higher level
/// skeletons. Always pulls from existing design tokens.
class SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const SkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.imagePlaceholder,
      highlightColor: AppColors.border,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: AppColors.imagePlaceholder,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
    );
  }
}

/// Skeleton for a single product card (matches the 2-col grid layout used in
/// the home page and storefront).
class ProductCardSkeleton extends StatelessWidget {
  const ProductCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Expanded(
          child: SkeletonBox(width: double.infinity, height: double.infinity),
        ),
        SizedBox(height: 8),
        SkeletonBox(width: 60, height: 10),
        SizedBox(height: 4),
        SkeletonBox(width: 120, height: 14),
        SizedBox(height: 5),
        SkeletonBox(width: 50, height: 14),
        SizedBox(height: 8),
      ],
    );
  }
}

/// Skeleton for a single boutique list row.
class BoutiqueRowSkeleton extends StatelessWidget {
  const BoutiqueRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.imagePlaceholder,
      highlightColor: AppColors.border,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(
          children: [
            Container(width: 52, height: 52, color: AppColors.imagePlaceholder),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  SkeletonBox(width: 140, height: 14),
                  SizedBox(height: 6),
                  SkeletonBox(width: 80, height: 10),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Skeleton for the home page featured products grid (4 placeholders).
class FeaturedProductsGridSkeleton extends StatelessWidget {
  const FeaturedProductsGridSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 4,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.62,
        ),
        itemBuilder: (_, __) => const ProductCardSkeleton(),
      ),
    );
  }
}

/// Skeleton for a boutiques list — 5 rows.
class BoutiquesListSkeleton extends StatelessWidget {
  const BoutiquesListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(5, (_) => const BoutiqueRowSkeleton()),
    );
  }
}

/// Skeleton for a single feed card — mirrors the [FeedCard] layout: boutique
/// header, 4:5 image, name/price row, and the two action buttons.
class FeedCardSkeleton extends StatelessWidget {
  const FeedCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
            child: Row(
              children: [
                const SkeletonBox(width: 30, height: 30, borderRadius: 15),
                const SizedBox(width: 9),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SkeletonBox(width: 100, height: 10),
                    SizedBox(height: 5),
                    SkeletonBox(width: 60, height: 9),
                  ],
                ),
                const Spacer(),
                const SkeletonBox(width: 64, height: 30),
              ],
            ),
          ),
          // Image
          const AspectRatio(
            aspectRatio: 4 / 5,
            child: SkeletonBox(width: double.infinity, height: double.infinity),
          ),
          // Name + price
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 0),
            child: Row(
              children: const [
                SkeletonBox(width: 130, height: 16),
                Spacer(),
                SkeletonBox(width: 60, height: 14),
              ],
            ),
          ),
          // Actions
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(
              children: const [
                Expanded(
                  child: SkeletonBox(width: double.infinity, height: 46),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: SkeletonBox(width: double.infinity, height: 46),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Skeleton for the home feed — 2 feed cards.
class FeedSkeleton extends StatelessWidget {
  const FeedSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        2,
        (_) => const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: FeedCardSkeleton(),
        ),
      ),
    );
  }
}

/// Skeleton for a single product list row — mirrors the owner/boutique product
/// card: image on the left, details + two action buttons on the right.
class ProductListRowSkeleton extends StatelessWidget {
  const ProductListRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.imagePlaceholder,
      highlightColor: AppColors.border,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 80,
              height: 100,
              color: AppColors.imagePlaceholder,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  SkeletonBox(width: 150, height: 14),
                  SizedBox(height: 8),
                  SkeletonBox(width: double.infinity, height: 10),
                  SizedBox(height: 5),
                  SkeletonBox(width: 110, height: 10),
                  SizedBox(height: 12),
                  SkeletonBox(width: 70, height: 14),
                  SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: SkeletonBox(width: double.infinity, height: 34),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: SkeletonBox(width: double.infinity, height: 34),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Skeleton for a product list — [count] row placeholders.
class ProductListSkeleton extends StatelessWidget {
  final int count;
  const ProductListSkeleton({super.key, this.count = 4});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(count, (_) => const ProductListRowSkeleton()),
    );
  }
}

/// Skeleton for a single boutique sales row — mirrors the boutique sales card:
/// circular avatar, name + order-count lines, a progress bar, and a trailing
/// total amount.
class SalesRowSkeleton extends StatelessWidget {
  const SalesRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.imagePlaceholder,
      highlightColor: AppColors.border,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(
                color: AppColors.imagePlaceholder,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  SkeletonBox(width: 130, height: 14),
                  SizedBox(height: 6),
                  SkeletonBox(width: 80, height: 10),
                  SizedBox(height: 10),
                  SkeletonBox(width: double.infinity, height: 4),
                ],
              ),
            ),
            const SizedBox(width: 14),
            const SkeletonBox(width: 56, height: 14),
          ],
        ),
      ),
    );
  }
}

/// Skeleton for the boutique sales list — [count] row placeholders.
class SalesListSkeleton extends StatelessWidget {
  final int count;
  const SalesListSkeleton({super.key, this.count = 5});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
      child: Column(
        children: List.generate(count, (_) => const SalesRowSkeleton()),
      ),
    );
  }
}

/// Skeleton for the orders list — 4 card rows.
class OrdersListSkeleton extends StatelessWidget {
  const OrdersListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.imagePlaceholder,
      highlightColor: AppColors.border,
      child: Column(
        children: List.generate(
          4,
          (_) => Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.card,
              border: Border.all(color: AppColors.border, width: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SkeletonBox(width: 120, height: 12),
                SizedBox(height: 8),
                SkeletonBox(width: 200, height: 14),
                SizedBox(height: 6),
                SkeletonBox(width: 80, height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
