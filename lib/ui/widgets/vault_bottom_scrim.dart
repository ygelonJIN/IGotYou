import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// 页面底部覆盖遮罩：与顶部渐变区同款平滑黑金渐变（自下而上淡出）。
/// 只做视觉遮罩（[IgnorePointer]，不拦截点击），不承载交互内容；
/// 交互内容（如主页检索框 + 设置/备份/添加）由页面在遮罩之上单独浮层承载。
/// 所有页面统一使用，高度全局只调 [AppSizes.bottomMaskHeight]。
class VaultBottomScrim extends StatelessWidget {
  const VaultBottomScrim({super.key});

  /// 底部遮罩区总高度（底部安全区 + 统一渐变高度，与顶部 totalHeight 对称）。
  static double height(MediaQueryData mq) =>
      mq.padding.bottom + AppSizes.bottomMaskHeight;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        height: height(MediaQuery.of(context)),
        child: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppGradients.bottomScrim),
        ),
      ),
    );
  }
}
