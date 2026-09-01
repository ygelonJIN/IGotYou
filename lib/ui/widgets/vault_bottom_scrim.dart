import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// 页面底部覆盖遮罩：与顶部渐变区同款平滑深墨金渐变（自下而上淡出）。
/// 只做视觉遮罩（[IgnorePointer]，不拦截点击），不承载交互内容。
/// 全局统一高度：bottomScrimHeight（180）+ 底部安全区，与主页一致。
class VaultBottomScrim extends StatelessWidget {
  const VaultBottomScrim({super.key});

  /// 底部遮罩区总高度（底部安全区 + bottomScrimHeight）。
  static double totalHeight(MediaQueryData mq) =>
      mq.padding.bottom + AppSizes.bottomScrimHeight;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        height: totalHeight(MediaQuery.of(context)),
        child: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppGradients.bottomScrim),
        ),
      ),
    );
  }
}