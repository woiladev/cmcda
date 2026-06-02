import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';

/// Wraps [child] in a themed shimmer sweep. Use as the base for any skeleton
/// loading state so the whole app shares one shimmer look.
class AppShimmer extends StatelessWidget {
  const AppShimmer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.border.withValues(alpha: 0.55),
      highlightColor: AppColors.surface,
      period: const Duration(milliseconds: 1300),
      child: child,
    );
  }
}

/// A single rounded placeholder block. Already self-shimmers, so it can be
/// dropped anywhere without an enclosing [AppShimmer].
class ShimmerBox extends StatelessWidget {
  const ShimmerBox({
    super.key,
    this.width = double.infinity,
    required this.height,
    this.radius = AppConstants.radiusMD,
    this.shimmer = true,
  });

  final double width;
  final double height;
  final double radius;
  final bool shimmer;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.border.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
    return shimmer ? AppShimmer(child: box) : box;
  }
}

/// Vertical list of identical rounded skeleton rows under one shimmer sweep.
class ShimmerList extends StatelessWidget {
  const ShimmerList({
    super.key,
    this.itemCount = 3,
    this.itemHeight = 72,
    this.gap = AppConstants.spaceSM,
    this.radius = AppConstants.radiusLG,
  });

  final int itemCount;
  final double itemHeight;
  final double gap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: Column(
        children: List.generate(
          itemCount,
          (i) => Padding(
            padding: EdgeInsets.only(bottom: i < itemCount - 1 ? gap : 0),
            child: ShimmerBox(
              height: itemHeight,
              radius: radius,
              shimmer: false,
            ),
          ),
        ),
      ),
    );
  }
}
