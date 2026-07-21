import 'package:flutter/material.dart';
import '../../../core/theme/glass_card.dart';

/// كارت الإحصائيات الرسمي والفاخر بالخط العربي والرمز ممركزين بالوسط
class GlassStatCard extends StatelessWidget {
  const GlassStatCard({
    super.key,
    required this.icon,
    required this.title,
    this.value,
    required this.gradientColors,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? value;
  final List<Color> gradientColors;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      gradientColors: gradientColors,
      onTap: onTap,
      borderRadius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // الأيقونة في الأعلى ممركزة بالوسط
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.28),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 12),
          // النص في الأسفل ممركز بالوسط بخط عربي رسمي
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'Cairo',
                  shadows: [
                    Shadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
