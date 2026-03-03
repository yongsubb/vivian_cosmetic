import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../constants/app_colors.dart';

/// Optimized image widget with caching and error handling
class OptimizedImage extends StatelessWidget {
  final String? imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? placeholder;
  final Widget? errorWidget;

  const OptimizedImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholder,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.isEmpty) {
      return _buildErrorWidget(context);
    }

    Widget imageWidget;

    if (imageUrl!.startsWith('http')) {
      // Network image with caching
      imageWidget = CachedNetworkImage(
        imageUrl: imageUrl!,
        width: width,
        height: height,
        fit: fit,
        placeholder: (context, url) =>
            placeholder ?? _buildPlaceholder(context),
        errorWidget: (context, url, error) =>
            errorWidget ?? _buildErrorWidget(context),
        memCacheWidth: width?.toInt(),
        memCacheHeight: height?.toInt(),
        maxWidthDiskCache: 800,
        maxHeightDiskCache: 800,
      );
    } else {
      // Asset or file image
      imageWidget = Image.asset(
        imageUrl!,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (context, error, stackTrace) {
          return errorWidget ?? _buildErrorWidget(context);
        },
      );
    }

    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: imageWidget);
    }

    return imageWidget;
  }

  Widget _buildPlaceholder(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: width,
      height: height,
      color: isDark ? AppColors.darkSurfaceVariant : AppColors.secondary,
      child: Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(
            isDark ? AppColors.primary : AppColors.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildErrorWidget(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: width,
      height: height,
      color: isDark ? AppColors.darkSurfaceVariant : AppColors.secondary,
      child: Icon(
        Icons.image_not_supported,
        size: 40,
        color: isDark ? AppColors.darkTextLight : AppColors.textLight,
      ),
    );
  }
}

/// Product image widget with optimizations
class ProductImage extends StatelessWidget {
  final String? imageUrl;
  final double size;
  final bool showBadge;
  final String? badgeText;

  const ProductImage({
    super.key,
    required this.imageUrl,
    this.size = 120,
    this.showBadge = false,
    this.badgeText,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        OptimizedImage(
          imageUrl: imageUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          borderRadius: BorderRadius.circular(12),
        ),
        if (showBadge && badgeText != null)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                badgeText!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// User avatar with caching
class CachedAvatar extends StatelessWidget {
  final String? imageUrl;
  final double radius;
  final String? fallbackText;

  const CachedAvatar({
    super.key,
    this.imageUrl,
    this.radius = 20,
    this.fallbackText,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.primary,
        child: Text(
          _getInitials(),
          style: TextStyle(
            color: Colors.white,
            fontSize: radius * 0.6,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    return CachedNetworkImage(
      imageUrl: imageUrl!,
      imageBuilder: (context, imageProvider) =>
          CircleAvatar(radius: radius, backgroundImage: imageProvider),
      placeholder: (context, url) => CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.primaryLight,
        child: SizedBox(
          width: radius,
          height: radius,
          child: const CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      errorWidget: (context, url, error) => CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.primary,
        child: Text(
          _getInitials(),
          style: TextStyle(
            color: Colors.white,
            fontSize: radius * 0.6,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  String _getInitials() {
    if (fallbackText == null || fallbackText!.isEmpty) return '?';

    final words = fallbackText!.trim().split(' ');
    if (words.length >= 2) {
      return '${words[0][0]}${words[1][0]}'.toUpperCase();
    }
    return fallbackText![0].toUpperCase();
  }
}
