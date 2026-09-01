import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// 胶囊形态的通用按钮，用于顶部浮层等处的次要操作。
///
/// 视觉由 `AppColors` 令牌驱动：
/// - `highlight = true`：主色填充（选中 / 强调态）
/// - `highlight = false`：表面色填充（普通态）
/// 方角胶囊（直角）。
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.icon,
    required this.label,
    this.highlight = false,
    this.compact = false,
    this.onTap,
  });

  final IconData icon;
  final String label;

  /// 是否高亮（主色填充）。
  final bool highlight;

  /// 是否紧凑（更小的内边距，用于日期等次要信息）。
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = highlight ? AppColors.onGold : AppColors.textPrimary;
    final background = highlight ? AppColors.gold : AppColors.surface;
    final borderColor = (highlight ? AppColors.gold : AppColors.goldDim);

    return Material(
      color: background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.button),
        side: BorderSide(color: borderColor, width: 1),
      ),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.button),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 14 : 16,
            vertical: compact ? 9 : 10,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: foreground),
              if (label.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: foreground,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}