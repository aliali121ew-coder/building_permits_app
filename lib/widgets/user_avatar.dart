import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';

/// صورة المستخدم: رابط على الخادم (R2) أو ملف محلي، وإلا الحرف الأول من الاسم.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.path, required this.name, this.radius = 22, this.color});

  final String? path;
  final String name;
  final double radius;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    final p = path?.trim() ?? '';
    ImageProvider? image;
    if (p.startsWith('http://') || p.startsWith('https://')) {
      image = NetworkImage(p);
    } else if (p.isNotEmpty && !kIsWeb && File(p).existsSync()) {
      image = FileImage(File(p));
    }
    final initial = name.trim().isNotEmpty ? name.trim().characters.first : '؟';

    return CircleAvatar(
      radius: radius,
      backgroundColor: c.withValues(alpha: 0.15),
      foregroundImage: image,
      onForegroundImageError: image == null ? null : (_, __) {},
      child: Text(
        initial,
        style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: radius * 0.8, fontFamily: 'Cairo'),
      ),
    );
  }
}
