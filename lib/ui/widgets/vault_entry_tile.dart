import 'package:flutter/material.dart';

import '../../core/models/entry.dart';
import '../../theme/tokens.dart';

/// 条目行：左侧独立钥匙图标（大点击区，金色=钥匙 / 灰色=否），右侧名称卡片。
/// 列表不显示加密内容与内容（进入编辑页可见）。
class VaultEntryTile extends StatelessWidget {
  final Entry entry;
  final VoidCallback? onTap;
  final VoidCallback? onToggleKey;

  const VaultEntryTile({
    super.key,
    required this.entry,
    this.onTap,
    this.onToggleKey,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 钥匙图标：独立在卡片外，方形反馈、与卡片同高、整列可点击。
          // 金色钥匙 = 作为钥匙；灰色钥匙 = 不作为钥匙（更灰以区分）。
          // 二次加密条目（doubleLocked）的钥匙框带金色边框。
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onToggleKey,
              borderRadius: BorderRadius.all(Radius.circular(AppRadius.card)),
              child: Container(
                width: AppSizes.tileKeyWidth,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: entry.isKey
                      ? AppColors.surfaceAlt
                      : AppColors.surface,
                  border: entry.doubleLocked
                      ? Border.all(
                          color: AppColors.gold,
                          width: AppBorder.width,
                        )
                      : null,
                ),
                child: Icon(
                  Icons.key,
                  size: AppSizes.tileKeyIconSize,
                  color: entry.isKey ? AppColors.gold : AppColors.textSecondary,
                ),
              ),
            ),
          ),
          // 名称卡片（与钥匙图标紧贴，无间距）
          Expanded(
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.unit4,
                  vertical: AppSpacing.unit4,
                ),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.all(
                    Radius.circular(AppRadius.card),
                  ),
                ),
                child: Text(
                  entry.name,
                  style: AppTextStyles.headingGold,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}