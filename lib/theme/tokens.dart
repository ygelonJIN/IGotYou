import 'package:flutter/material.dart';

/// IGotYou 主题令牌：深墨金色体系（论对错 · 法庭之秤）。
class AppColors {
  AppColors._();

  static const Color bg = Color(0xFF1C1B1E);
  static const Color surface = Color(0xFF2D2A24);
  static const Color surfaceAlt = Color(0xFF241F1A);
  static const Color gold = Color(0xFFE0AE40);
  static const Color goldDim = Color(0xFFB09B74);
  static const Color textPrimary = Color(0xFFF2E9D6);
  static const Color textSecondary = Color(0xFFB09B74);

  /// 钥匙未选中态图标色：比 textSecondary 更灰，与金色明显区分。
  static const Color keyOff = Color(0xFF6F6B60);

  /// gold 底上的前景文字（主按钮 / 主操作大按钮用）。
  static const Color onGold = Color(0xFF241C07);
}

class AppFontSizes {
  AppFontSizes._();
  static const double title = 20;
  static const double heading = 16;
  static const double body = 14;
  static const double meta = 12;
  static const double mono = 14;
  static const double titleSpacing = 4;
}

class AppFontWeights {
  AppFontWeights._();
  static const FontWeight strong = FontWeight.w600;
  static const FontWeight normal = FontWeight.w400;
}

class AppFontFamilies {
  AppFontFamilies._();

  /// 全局唯一字体：Noto Serif SC（theme.dart 注册，所有文字共用）。
  static const String serif = 'Noto Serif SC';
}

/// 页面 / 组件**禁止自行组装** `TextStyle`，一律引用这里的组合样式。
class AppTextStyles {
  AppTextStyles._();

  static const TextStyle wordmark = TextStyle(
    fontSize: AppFontSizes.title,
    fontWeight: AppFontWeights.strong,
    color: AppColors.gold,
    letterSpacing: AppFontSizes.titleSpacing,
  );

  /// 页面大标题（米白正文色，金色留给强调元素）。
  static const TextStyle title = TextStyle(
    fontSize: AppFontSizes.title,
    fontWeight: AppFontWeights.strong,
    color: AppColors.textPrimary,
    decoration: TextDecoration.none,
  );

  static const TextStyle heading = TextStyle(
    fontSize: AppFontSizes.heading,
    fontWeight: AppFontWeights.strong,
    color: AppColors.textPrimary,
    decoration: TextDecoration.none,
  );

  static const TextStyle headingGold = TextStyle(
    fontSize: AppFontSizes.heading,
    fontWeight: AppFontWeights.strong,
    color: AppColors.gold,
    decoration: TextDecoration.none,
  );

  static const TextStyle body = TextStyle(
    fontSize: AppFontSizes.body,
    fontWeight: AppFontWeights.normal,
    color: AppColors.textPrimary,
    decoration: TextDecoration.none,
  );

  static const TextStyle bodySecondary = TextStyle(
    fontSize: AppFontSizes.body,
    fontWeight: AppFontWeights.normal,
    color: AppColors.textSecondary,
    decoration: TextDecoration.none,
  );

  static const TextStyle bodyGold = TextStyle(
    fontSize: AppFontSizes.body,
    fontWeight: AppFontWeights.normal,
    color: AppColors.gold,
    decoration: TextDecoration.none,
  );

  static const TextStyle meta = TextStyle(
    fontSize: AppFontSizes.meta,
    fontWeight: AppFontWeights.normal,
    color: AppColors.textSecondary,
    decoration: TextDecoration.none,
  );

  static const TextStyle metaGold = TextStyle(
    fontSize: AppFontSizes.meta,
    fontWeight: AppFontWeights.normal,
    color: AppColors.gold,
    decoration: TextDecoration.none,
  );

  static const TextStyle metaDim = TextStyle(
    fontSize: AppFontSizes.meta,
    fontWeight: AppFontWeights.normal,
    color: AppColors.goldDim,
    decoration: TextDecoration.none,
  );

  /// 加密内容（全局同字体，不再切等宽）。
  static const TextStyle mono = TextStyle(
    fontSize: AppFontSizes.mono,
    fontWeight: AppFontWeights.normal,
    color: AppColors.textPrimary,
    decoration: TextDecoration.none,
  );

  static const TextStyle buttonLabel = TextStyle(
    fontSize: AppFontSizes.body,
    fontWeight: AppFontWeights.strong,
    // 显式锁定主题字体：所有按钮（主/危险/文字）字型完全一致。
    fontFamily: AppFontFamilies.serif,
    decoration: TextDecoration.none,
  );
}

class AppSpacing {
  AppSpacing._();
  static const double unit = 4;
  static const double unit2 = 8;
  static const double unit3 = 12;
  static const double unit4 = 16;
  static const double unit6 = 24;
}

class AppRadius {
  AppRadius._();
  static const double input = 2;
  static const double card = 2;
  static const double button = 2;
  static const double dialog = 2;
  static const double gate = 2;
}

class AppBorder {
  AppBorder._();
  static const double width = 1;
  static const Color color = AppColors.goldDim;
  static const Color activeColor = AppColors.gold;
  static const double gateWidth = 1;
}

class AppGradients {
  AppGradients._();

  static const LinearGradient gateMetal = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [AppColors.surfaceAlt, AppColors.surface, AppColors.bg],
    stops: [0.0, 0.55, 1.0],
  );

  static const LinearGradient topScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      AppColors.bg,
      Color(0xE61C1B1E),
      Color(0x7A1C1B1E),
      Color(0x001C1B1E),
    ],
    stops: [0.0, 0.34, 0.72, 1.0],
  );

  static const LinearGradient bottomScrim = LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: [
      AppColors.bg,
      Color(0xE61C1B1E),
      Color(0x7A1C1B1E),
      Color(0x001C1B1E),
    ],
    stops: [0.0, 0.34, 0.72, 1.0],
  );

  /// 侧栏 / 面板顶部渐隐：与面板 `surface` 同色（不出现其它颜色色带）。
  static final LinearGradient surfaceTopScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      AppColors.surface.withValues(alpha: 1),
      AppColors.surface.withValues(alpha: 0.92),
      AppColors.surface.withValues(alpha: 0),
    ],
    stops: const [0.0, 0.6, 1.0],
  );

  /// 侧栏 / 面板底部渐隐：与面板 `surface` 同色。
  static final LinearGradient surfaceBottomScrim = LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: [
      AppColors.surface.withValues(alpha: 1),
      AppColors.surface.withValues(alpha: 0.92),
      AppColors.surface.withValues(alpha: 0),
    ],
    stops: const [0.0, 0.6, 1.0],
  );
}

class AppDurations {
  AppDurations._();
  static const Duration cooldownTick = Duration(seconds: 1);
  static const Duration bannerIn = Duration(milliseconds: 240);
  static const Duration bannerOut = Duration(milliseconds: 200);
  static const Duration bannerHold = Duration(milliseconds: 2600);
}

class AppShadows {
  AppShadows._();
  static const BoxShadow banner = BoxShadow(
    color: Color(0x30000000),
    blurRadius: 20,
    offset: Offset(0, 2),
  );
}

class AppSizes {
  AppSizes._();

  // ── 全局页面模板（以条目主页为基准，所有页面 / 未来页面统一）──
  static const double pageEdge = 16; // 页面水平边距
  static const double contentTopInset = 140; // 首条目距顶（自屏幕顶端固定）
  static const double contentBottomInset = 236; // 内容底部留白
  static const double topScrimHeight = 170; // 顶部遮罩高（固定，不含安全区）
  static const double bottomScrimHeight = 180; // 底部遮罩高（不含底部安全区）
  static const double topChromeInset = 8; // 顶栏胶囊距顶

  // 设置侧栏（侧滑面板，surface 同色遮罩，独立于整页模板）
  static const double settingsTopInset = 80; // 内容顶部 = 状态栏 + 80
  static const double settingsBottomInset = 150; // 内容底部 = 安全区 + 150
  static const double settingsTopScrim = 150; // 顶部遮罩高
  static const double settingsBottomScrim = 220; // 底部遮罩高

  // 全局上锁按钮距底（加号上方：16 底边距 + 44 加号高 + 8 间距）
  static const double lockButtonBottomOffset = 72;

  static const double buttonHeight = 48;
  static const double heroButtonHeight = 56;
  static const double inputHeight = 48;
  static const double searchBarHeight = 44;
  static const double iconSize = 18;
  static const double fieldPrefixWidth = 40;
  static const double fieldPrefixWidthCompact = 32;
  static const double navButtonHeight = 34;
  static const double navIconButtonSize = 40;
  static const double topBarHeight = 48;
  static const double topBarIconSize = 24;
  static const double topBarLeadingWidth = 48;
  static const double scrimFade = 48;
  static const double bannerMaxWidth = 480;
  static const double tileGap = 8;
  static const double tileKeyWidth = 56;
  static const double tileKeyIconSize = 24;
  static const double gateMaxWidth = 360;
  static const double gatePadding = 32;
  static const double gateGap = 24;
}
