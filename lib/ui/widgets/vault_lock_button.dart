import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../theme/tokens.dart';
import 'pill_button.dart';

/// 全局上锁按钮：固定在屏幕右上角、悬于所有页面（含遮罩）之上，
/// 由 `MaterialApp.builder` 在导航器外层渲染一次，全应用共用。
///
/// 位置约定：
/// - 右缘 pageEdge（与主页检索行同宽）
/// - 上缘 = 状态栏 + topChromeInset（与主页顶部浮层胶囊同一水平线）
/// - 样式与主页「设置」胶囊一致（PillButton highlight）。
///
/// 设置侧栏展开时不渲染（设置栏内自带同款上锁按钮），其余页面常驻右上角。
/// 仅在已解锁时显示；点击先失焦（触发页面失焦自动保存）→ 等待页面
/// 注册的 beforeLock → 锁定 → 收起所有二级路由回到根页。
class VaultLockButtonOverlay extends StatelessWidget {
  final GlobalKey<NavigatorState> navigatorKey;

  const VaultLockButtonOverlay({super.key, required this.navigatorKey});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (!app.isUnlocked || app.settingsOpen) return const SizedBox.shrink();

    final mq = MediaQuery.of(context);
    return Positioned(
      top: mq.padding.top + AppSizes.topChromeInset,
      right: AppSizes.pageEdge,
      child: PillButton(
        icon: Icons.lock_outline,
        label: '上锁',
        highlight: true,
        onTap: () async {
          FocusManager.instance.primaryFocus?.unfocus();
          await app.beforeLock?.call();
          if (!context.mounted) return;
          await app.lock();
          navigatorKey.currentState?.popUntil((r) => r.isFirst);
        },
      ),
    );
  }
}