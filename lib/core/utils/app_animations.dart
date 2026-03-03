import 'package:flutter/material.dart';
import 'package:animations/animations.dart';

/// Animation utilities for smooth transitions and micro-interactions
class AppAnimations {
  // Animation durations
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 350);

  /// Fade transition for route changes
  static Widget fadeTransition({
    required Widget child,
    required Animation<double> animation,
  }) {
    return FadeTransition(opacity: animation, child: child);
  }

  /// Slide transition from bottom
  static Widget slideUpTransition({
    required Widget child,
    required Animation<double> animation,
  }) {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.1),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
      child: FadeTransition(opacity: animation, child: child),
    );
  }

  /// Scale transition
  static Widget scaleTransition({
    required Widget child,
    required Animation<double> animation,
  }) {
    return ScaleTransition(
      scale: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: child,
    );
  }

  /// Shared axis transition (Material motion)
  static Widget sharedAxisTransition({
    required Widget child,
    required Animation<double> animation,
    SharedAxisTransitionType transitionType =
        SharedAxisTransitionType.horizontal,
  }) {
    return SharedAxisTransition(
      animation: animation,
      secondaryAnimation: Tween<double>(begin: 0, end: 1).animate(animation),
      transitionType: transitionType,
      child: child,
    );
  }

  /// Fade through transition (Material motion)
  static Widget fadeThroughTransition({
    required Widget child,
    required Animation<double> animation,
  }) {
    return FadeThroughTransition(
      animation: animation,
      secondaryAnimation: Tween<double>(begin: 0, end: 1).animate(animation),
      child: child,
    );
  }
}

/// Custom page route with fade transition
class FadePageRoute<T> extends PageRouteBuilder<T> {
  final Widget page;
  final Duration duration;

  FadePageRoute({required this.page, this.duration = AppAnimations.normal})
    : super(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionDuration: duration,
        reverseTransitionDuration: duration,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      );
}

/// Custom page route with slide transition
class SlidePageRoute<T> extends PageRouteBuilder<T> {
  final Widget page;
  final Duration duration;
  final Offset begin;

  SlidePageRoute({
    required this.page,
    this.duration = AppAnimations.normal,
    this.begin = const Offset(1, 0),
  }) : super(
         pageBuilder: (context, animation, secondaryAnimation) => page,
         transitionDuration: duration,
         reverseTransitionDuration: duration,
         transitionsBuilder: (context, animation, secondaryAnimation, child) {
           return SlideTransition(
             position: Tween<Offset>(begin: begin, end: Offset.zero).animate(
               CurvedAnimation(parent: animation, curve: Curves.easeOut),
             ),
             child: child,
           );
         },
       );
}

/// Custom page route with scale transition
class ScalePageRoute<T> extends PageRouteBuilder<T> {
  final Widget page;
  final Duration duration;

  ScalePageRoute({required this.page, this.duration = AppAnimations.normal})
    : super(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionDuration: duration,
        reverseTransitionDuration: duration,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return ScaleTransition(
            scale: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: FadeTransition(opacity: animation, child: child),
          );
        },
      );
}

/// Material page route (shared axis transition)
class MaterialPageRoute<T> extends PageRouteBuilder<T> {
  final Widget page;
  final SharedAxisTransitionType transitionType;

  MaterialPageRoute({
    required this.page,
    this.transitionType = SharedAxisTransitionType.horizontal,
  }) : super(
         pageBuilder: (context, animation, secondaryAnimation) => page,
         transitionDuration: AppAnimations.normal,
         reverseTransitionDuration: AppAnimations.normal,
         transitionsBuilder: (context, animation, secondaryAnimation, child) {
           return SharedAxisTransition(
             animation: animation,
             secondaryAnimation: secondaryAnimation,
             transitionType: transitionType,
             child: child,
           );
         },
       );
}

/// Animated list item with slide and fade
class AnimatedListItem extends StatelessWidget {
  final Widget child;
  final int index;
  final Duration delay;
  final Duration duration;

  const AnimatedListItem({
    super.key,
    required this.child,
    required this.index,
    this.delay = const Duration(milliseconds: 50),
    this.duration = AppAnimations.normal,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: duration,
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// Bouncing animation for buttons
class BounceAnimation extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const BounceAnimation({super.key, required this.child, this.onTap});

  @override
  State<BounceAnimation> createState() => _BounceAnimationState();
}

class _BounceAnimationState extends State<BounceAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    _controller.forward();
  }

  void _onTapUp(TapUpDetails details) {
    _controller.reverse();
    widget.onTap?.call();
  }

  void _onTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: ScaleTransition(scale: _scaleAnimation, child: widget.child),
    );
  }
}

/// Shimmer effect for loading states
class ShimmerLoading extends StatefulWidget {
  final Widget child;

  const ShimmerLoading({super.key, required this.child});

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: const [Colors.grey, Colors.white, Colors.grey],
              stops: [
                _controller.value - 0.3,
                _controller.value,
                _controller.value + 0.3,
              ],
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
