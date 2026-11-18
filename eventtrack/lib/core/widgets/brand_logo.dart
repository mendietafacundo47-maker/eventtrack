import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Símbolo de EventTrack: pin GPS + check de cumplimiento + referencia a
/// fotografía (§4.1.3).
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 64});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Logotipo de EventTrack',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(size * 0.28),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(Icons.location_on, size: size * 0.78, color: AppColors.action),
            Positioned(
              top: size * 0.17,
              child: Icon(
                Icons.check_rounded,
                size: size * 0.32,
                color: AppColors.success,
              ),
            ),
            Positioned(
              right: size * 0.06,
              bottom: size * 0.06,
              child: Icon(
                Icons.photo_camera,
                size: size * 0.26,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
