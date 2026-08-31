import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// 保险柜门面（DEVELOPMENT 9.5b）：解锁 / 创建页的视觉主体。
///
/// 居中的金属柜门面板：上亮下暗渐变 + 金色边框，内放输入区与主按钮。
class VaultGate extends StatelessWidget {
  final Widget child;

  const VaultGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.unit4,
          vertical: AppSpacing.unit6,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSizes.gateMaxWidth),
          child: Container(
            padding: const EdgeInsets.all(AppSizes.gatePadding),
            decoration: BoxDecoration(
              gradient: AppGradients.gateMetal,
              border: Border.all(
                color: AppColors.gold,
                width: AppBorder.gateWidth,
              ),
              borderRadius: BorderRadius.all(Radius.circular(AppRadius.gate)),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
