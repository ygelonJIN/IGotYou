import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// 顶部悬浮提示横幅：统一提示/报错样式，全部使用金色模板。
/// 金属渐变底 + 柔和阴影，从屏幕最上方滑入，自动消失。
/// 不区分成功/失败：统一金色锁图标 + 金色正文。
void showVaultBanner(BuildContext context, String text) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _VaultBanner(text: text, onDone: () => entry.remove()),
  );
  overlay.insert(entry);
}

class _VaultBanner extends StatefulWidget {
  final String text;
  final VoidCallback onDone;

  const _VaultBanner({required this.text, required this.onDone});

  @override
  State<_VaultBanner> createState() => _VaultBannerState();
}

class _VaultBannerState extends State<_VaultBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: AppDurations.bannerIn,
    reverseDuration: AppDurations.bannerOut,
  )..forward();
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, -1.4),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
  Timer? _timer;
  double _dragDy = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer(AppDurations.bannerHold, () => _dismiss());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  /// 上滑手动消失；也用于自动到时消失。
  void _dismiss() {
    if (_ctrl.status == AnimationStatus.dismissed) return;
    _timer?.cancel();
    _ctrl.reverse().then((_) {
      if (mounted) widget.onDone();
    });
  }

  /// 上滑手势：向上拖过阈值即消失，否则弹回。
  void _onVerticalDragEnd(DragEndDetails d) {
    final up = d.primaryVelocity ?? (_dragDy < 0 ? -1.0 : 0.0);
    _dragDy = 0;
    if (up < -150) {
      _dismiss();
    } else {
      _ctrl.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top + AppSpacing.unit2;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: GestureDetector(
        onVerticalDragUpdate: (d) => _dragDy = d.delta.dy,
        onVerticalDragEnd: _onVerticalDragEnd,
        child: FadeTransition(
          opacity: _ctrl,
          child: SlideTransition(
            position: _slide,
            child: Padding(
              padding: EdgeInsets.only(top: top),
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.unit4,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.unit4,
                    vertical: AppSpacing.unit3,
                  ),
                  constraints: const BoxConstraints(
                    maxWidth: AppSizes.bannerMaxWidth,
                  ),
                  decoration: BoxDecoration(
                    gradient: AppGradients.gateMetal,
                    borderRadius: BorderRadius.all(
                      Radius.circular(AppRadius.gate),
                    ),
                    boxShadow: const [AppShadows.banner],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.lock_outline,
                        size: AppSizes.iconSize,
                        color: AppColors.gold,
                      ),
                      const SizedBox(width: AppSpacing.unit3),
                      Flexible(
                        child: Text(widget.text, style: AppTextStyles.bodyGold),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
