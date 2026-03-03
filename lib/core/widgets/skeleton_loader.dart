import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Skeleton loader widgets for showing loading states
class SkeletonLoader {
  /// Create a skeleton box
  static Widget box({
    double? width,
    double? height = 16,
    BorderRadius? borderRadius,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: borderRadius ?? BorderRadius.circular(4),
      ),
    );
  }

  /// Create a skeleton circle (for avatars)
  static Widget circle({double size = 40}) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
    );
  }

  /// Wrap widget in shimmer effect
  static Widget shimmer({
    required Widget child,
    required BuildContext context,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Shimmer.fromColors(
      baseColor: isDark ? Colors.grey[850]! : Colors.grey[300]!,
      highlightColor: isDark ? Colors.grey[800]! : Colors.grey[100]!,
      child: child,
    );
  }
}

/// Product card skeleton
class ProductCardSkeleton extends StatelessWidget {
  const ProductCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonLoader.shimmer(
      context: context,
      child: Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image placeholder
            AspectRatio(
              aspectRatio: 1,
              child: SkeletonLoader.box(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Product name
                  SkeletonLoader.box(width: double.infinity, height: 16),
                  const SizedBox(height: 8),
                  // Price
                  SkeletonLoader.box(width: 80, height: 20),
                  const SizedBox(height: 8),
                  // Stock
                  SkeletonLoader.box(width: 60, height: 14),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Transaction list item skeleton
class TransactionItemSkeleton extends StatelessWidget {
  const TransactionItemSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonLoader.shimmer(
      context: context,
      child: Card(
        child: ListTile(
          leading: SkeletonLoader.circle(size: 48),
          title: SkeletonLoader.box(width: double.infinity, height: 16),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              SkeletonLoader.box(width: 150, height: 14),
              const SizedBox(height: 4),
              SkeletonLoader.box(width: 100, height: 14),
            ],
          ),
          trailing: SkeletonLoader.box(width: 60, height: 20),
        ),
      ),
    );
  }
}

/// List skeleton with multiple items
class ListSkeleton extends StatelessWidget {
  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;

  const ListSkeleton({
    super.key,
    this.itemCount = 5,
    required this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: itemCount,
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemBuilder: itemBuilder,
    );
  }
}

/// Grid skeleton with multiple items
class GridSkeleton extends StatelessWidget {
  final int itemCount;
  final int crossAxisCount;
  final Widget Function(BuildContext, int) itemBuilder;

  const GridSkeleton({
    super.key,
    this.itemCount = 6,
    this.crossAxisCount = 2,
    required this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: 0.75,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: itemCount,
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemBuilder: itemBuilder,
    );
  }
}

/// Product grid skeleton
class ProductGridSkeleton extends StatelessWidget {
  final int itemCount;
  final int crossAxisCount;

  const ProductGridSkeleton({
    super.key,
    this.itemCount = 6,
    this.crossAxisCount = 2,
  });

  @override
  Widget build(BuildContext context) {
    return GridSkeleton(
      itemCount: itemCount,
      crossAxisCount: crossAxisCount,
      itemBuilder: (context, index) => const ProductCardSkeleton(),
    );
  }
}

/// Transaction list skeleton
class TransactionListSkeleton extends StatelessWidget {
  final int itemCount;

  const TransactionListSkeleton({super.key, this.itemCount = 5});

  @override
  Widget build(BuildContext context) {
    return ListSkeleton(
      itemCount: itemCount,
      itemBuilder: (context, index) => const TransactionItemSkeleton(),
    );
  }
}

/// Detail page skeleton
class DetailPageSkeleton extends StatelessWidget {
  const DetailPageSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonLoader.shimmer(
      context: context,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            AspectRatio(
              aspectRatio: 16 / 9,
              child: SkeletonLoader.box(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            const SizedBox(height: 16),
            // Title
            SkeletonLoader.box(width: double.infinity, height: 24),
            const SizedBox(height: 12),
            // Subtitle
            SkeletonLoader.box(width: 200, height: 16),
            const SizedBox(height: 24),
            // Content lines
            SkeletonLoader.box(width: double.infinity, height: 14),
            const SizedBox(height: 8),
            SkeletonLoader.box(width: double.infinity, height: 14),
            const SizedBox(height: 8),
            SkeletonLoader.box(width: 250, height: 14),
            const SizedBox(height: 24),
            // Action buttons
            Row(
              children: [
                Expanded(child: SkeletonLoader.box(height: 48)),
                const SizedBox(width: 12),
                Expanded(child: SkeletonLoader.box(height: 48)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Chart skeleton
class ChartSkeleton extends StatelessWidget {
  final double height;

  const ChartSkeleton({super.key, this.height = 250});

  @override
  Widget build(BuildContext context) {
    return SkeletonLoader.shimmer(
      context: context,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}
