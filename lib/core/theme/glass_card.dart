import 'dart:ui';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

/// كارت زجاجي بتأثير Glassmorphism + ظل 3D خفيف عند الضغط
class GlassCard extends StatefulWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.gradientColors,
    this.onTap,
    this.borderRadius = 22,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final List<Color>? gradientColors;
  final VoidCallback? onTap;
  final double borderRadius;
  final EdgeInsets padding;

  @override
  State<GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends State<GlassCard> with SingleTickerProviderStateMixin {
  double _scale = 1.0;

  void _setPressed(bool pressed) {
    setState(() => _scale = pressed ? 0.96 : 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = widget.gradientColors ?? AppColors.cardGradients.first;

    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            boxShadow: [
              BoxShadow(
                color: colors.first.withValues(alpha: isDark ? 0.28 : 0.45),
                blurRadius: 18,
                offset: const Offset(0, 10),
                spreadRadius: -4,
              ),
              if (!isDark)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                  spreadRadius: -2,
                ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
              child: Container(
                padding: widget.padding,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(widget.borderRadius),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      colors.first.withValues(alpha: isDark ? 0.55 : 1.0),
                      colors.last.withValues(alpha: isDark ? 0.35 : 1.0),
                    ],
                  ),
                  border: Border.all(
                    color: isDark 
                        ? Colors.white.withValues(alpha: 0.12) 
                        : Colors.white.withValues(alpha: 0.75),
                    width: isDark ? 1.2 : 2.2, // حواف ناعمة بارزة 3d
                  ),
                ),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
