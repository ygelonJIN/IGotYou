import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// 主按钮：gold 底、黑字、高 48、圆角 2（DEVELOPMENT 9.5）。
/// 禁用态降为 surfaceAlt 底 + textSecondary 字。
/// [highlighted] 高亮态：金色粗边框，用于"只差最后一步"的解锁按钮。
class VaultButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool expanded;
  final double height;
  final bool highlighted;

  const VaultButton({
    super.key,
    required this.label,
    this.onPressed,
    this.expanded = true,
    this.height = AppSizes.buttonHeight,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return SizedBox(
      height: height,
      width: expanded ? double.infinity : null,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: enabled ? AppColors.gold : AppColors.surfaceAlt,
          foregroundColor: enabled ? AppColors.onGold : AppColors.textSecondary,
          disabledBackgroundColor: AppColors.surfaceAlt,
          disabledForegroundColor: AppColors.textSecondary,
          side: highlighted
              ? const BorderSide(color: AppColors.gold, width: 2)
              : null,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(AppRadius.button)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.unit4),
          textStyle: AppTextStyles.buttonLabel,
        ),
        child: Text(label),
      ),
    );
  }
}

/// 危险操作按钮（清空/删除等）：与导航按钮同风格——暗金底 + 白字，全宽。
/// 不做红色区分（DEVELOPMENT 8.12：全应用去除红色，统一主题）。
class VaultDangerButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const VaultDangerButton({super.key, required this.label, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: AppSizes.buttonHeight,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: AppColors.goldDim,
          foregroundColor: AppColors.textPrimary,
          disabledBackgroundColor: AppColors.surfaceAlt,
          disabledForegroundColor: AppColors.textSecondary,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(AppRadius.button)),
          ),
          textStyle: AppTextStyles.buttonLabel,
        ),
        child: Text(label),
      ),
    );
  }
}

/// 次按钮（文字按钮）：无底色、gold 文字（DEVELOPMENT 9.5）。
class VaultTextButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Color color;

  const VaultTextButton({
    super.key,
    required this.label,
    this.onPressed,
    this.color = AppColors.gold,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color,
        disabledForegroundColor: AppColors.textSecondary,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.unit3,
          vertical: AppSpacing.unit2,
        ),
        textStyle: AppTextStyles.buttonLabel,
      ),
      child: Text(label),
    );
  }
}
