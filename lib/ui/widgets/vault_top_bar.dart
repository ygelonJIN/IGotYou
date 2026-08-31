import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../theme/tokens.dart';
import 'vault_button.dart';

/// 页面顶部覆盖栏：渐变遮罩 + 上锁按钮 +（可选）返回箭头 / 标题。
/// 所有页面（主页 / 设置 / 备份 / 编辑）共用同一个组件、同一个位置：
/// 上锁按钮始终在顶部同一高度，渐变区高度统一用 AppSizes.scrimHeight，全局只调一处。
/// [onBack] 由页面决定是否先保存再返回（配合 PopScope）。
/// [leading] 自定义前置按钮；默认返回箭头，传 null 则留占位。
/// [onBeforeLock] 锁定前回调（如等待未保存内容落盘）；null 直接锁定。
class VaultTopBar extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  final Widget? leading;
  final bool showBack;
  final bool showTitleRow;
  final Future<void> Function()? onBeforeLock;

  const VaultTopBar({
    super.key,
    required this.title,
    required this.onBack,
    this.leading,
    this.showBack = true,
    this.showTitleRow = true,
    this.onBeforeLock,
  });

  /// 页面 body 应让出的顶部高度：等于顶部渐变遮罩总高（渐变完全透明处）。
  /// 与主页共用 AppSizes.scrimHeight，全局只调这一处。
  static double totalHeight(MediaQueryData mq) =>
      mq.padding.top + AppSizes.scrimHeight;

  Future<void> _lock(BuildContext context) async {
    await onBeforeLock?.call();
    if (!context.mounted) return;
    final app = context.read<AppState>();
    await app.lock();
    if (context.mounted) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final scrimH = totalHeight(mq);
    return SizedBox(
      height: scrimH,
      child: Stack(
        children: [
          // 渐变遮罩：整块高度 = 统一渐变区（safeTop + scrimHeight）。
          Positioned.fill(
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: AppGradients.topScrim,
              ),
            ),
          ),
          // 可交互内容：上锁贴顶，返回/标题行在其下方。
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.unit4,
                AppSpacing.unit3,
                AppSpacing.unit4,
                AppSizes.tileGap,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 上锁：所有页面统一在顶部同一位置。
                  VaultButton(
                    label: '上锁',
                    height: AppSizes.heroButtonHeight,
                    onPressed: () => _lock(context),
                  ),
                  if (showTitleRow) ...[
                    const SizedBox(height: AppSpacing.unit3),
                    Row(
                      children: [
                        if (leading != null)
                          leading!
                        else if (showBack)
                          IconButton(
                            icon: const Icon(
                              Icons.arrow_back,
                              color: AppColors.gold,
                              size: AppSizes.topBarIconSize,
                            ),
                            tooltip: '返回',
                            onPressed: onBack,
                          )
                        else
                          const SizedBox(width: AppSizes.topBarLeadingWidth),
                        const SizedBox(width: AppSpacing.unit2),
                        Text(title, style: AppTextStyles.title),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
