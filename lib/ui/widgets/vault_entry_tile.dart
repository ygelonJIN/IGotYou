import 'package:flutter/material.dart';

import '../../core/models/entry.dart';
import '../../theme/tokens.dart';

/// 条目行：左侧独立钥匙图标（大点击区，金色=钥匙 / 灰=否），右侧名称卡片。
/// 卡片视觉：深墨卡底 + 弱金描边 + 方形直角 + 金色标题。
/// 二次加密条目：钥匙图标改为两把上下排列（不加金边框）。
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
    final keyColor = entry.isKey ? AppColors.gold : AppColors.keyOff;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 钥匙图标：独立在卡片外，方形反馈、与卡片同高、整列可点击。
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
                ),
                child: entry.doubleLocked
                    // 二次加密：两把钥匙上下排列、居中（紧贴不重叠）。
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.key,
                            size: AppSizes.tileKeyIconSize,
                            color: keyColor,
                          ),
                          Icon(
                            Icons.key,
                            size: AppSizes.tileKeyIconSize,
                            color: keyColor,
                          ),
                        ],
                      )
                    : Icon(
                        Icons.key,
                        size: AppSizes.tileKeyIconSize,
                        color: keyColor,
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
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.all(
                    Radius.circular(AppRadius.card),
                  ),
                  border: Border.all(
                    color: AppColors.goldDim.withValues(alpha: 0.45),
                    width: AppBorder.width,
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