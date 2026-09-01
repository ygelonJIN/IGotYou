import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import 'pill_button.dart';

/// 页面顶部覆盖栏：渐变遮罩 + 左上角「返回胶囊（设置同款）+ 纯文字标题」。
/// 所有二级页（备份 / 编辑 / 门禁）共用同一个组件、同一个位置——
/// 与主页「设置」胶囊完全对齐（SafeArea + 16/8/16/0）。
/// 「上锁」不在此处，由全局 `VaultLockButtonOverlay` 统一渲染在右下角。
///
/// 顶栏是盖在内容上的浮层，渐变遮罩让滚动到顶栏下方的条目柔和淡出。
class VaultTopBar extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  final Widget? leading;
  final bool showBack;
  final bool showTitleRow;

  const VaultTopBar({
    super.key,
    required this.title,
    required this.onBack,
    this.leading,
    this.showBack = true,
    this.showTitleRow = true,
  });

  /// 页面 body 应让出的顶部高度：与主页首个条目位置一致（contentTopInset）。
  static double totalHeight(MediaQueryData mq) => AppSizes.contentTopInset;

  /// 顶部渐变遮罩总高：与主页一致（topScrimHeight，固定不含安全区）。
  static double totalScrimHeight(MediaQueryData mq) => AppSizes.topScrimHeight;

  @override
  Widget build(BuildContext context) {
    final scrimH = totalScrimHeight(MediaQuery.of(context));
    return SizedBox(
      height: scrimH,
      child: Stack(
        children: [
          // 渐变遮罩：与主页同款（topScrimHeight 固定高度）。
          Positioned.fill(
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: AppGradients.topScrim,
              ),
            ),
          ),
          // 可交互内容：返回胶囊 + 标题，与主页「设置」胶囊同一位置。
          SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                AppSizes.pageEdge,
                AppSizes.topChromeInset,
                AppSizes.pageEdge,
                0,
              ),
              child: Row(
                children: [
                  if (leading != null)
                    leading!
                  else if (showBack)
                    PillButton(
                      icon: Icons.arrow_back_rounded,
                      label: '',
                      highlight: true,
                      onTap: onBack,
                    )
                  else
                    const SizedBox(width: AppSizes.topBarLeadingWidth),
                  if (showTitleRow) ...[
                    const SizedBox(width: AppSpacing.unit2),
                    Text(title, style: AppTextStyles.title),
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