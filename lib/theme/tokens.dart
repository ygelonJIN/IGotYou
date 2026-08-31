import 'package:flutter/material.dart';

// ───── 9.2 黑金色彩体系 ─────
class AppColors {
  AppColors._();

  static const Color bg = Color(0xFF0D0D0D);
  static const Color surface = Color(0xFF161616);
  static const Color surfaceAlt = Color(0xFF1E1E1E);
  static const Color gold = Color(0xFFC9A227);
  static const Color goldDim = Color(0xFF8A7120);
  static const Color textPrimary = Color(0xFFEDE8DC);
  static const Color textSecondary = Color(0xFF8F8A80);

  /// gold 底上的前景文字（主按钮 / 主操作大按钮用）。
  static const Color onGold = bg;
}

// ───── 9.3 字号 token ─────
class AppFontSizes {
  AppFontSizes._();
  static const double title = 20;
  static const double heading = 16;
  static const double body = 14;
  static const double meta = 12;
  static const double mono = 14;

  /// 标题（IGotYou 字标）字距。
  static const double titleSpacing = 4;
}

// ───── 9.3b 字重 token ─────
class AppFontWeights {
  AppFontWeights._();
  static const FontWeight strong = FontWeight.w600; // 标题 / 主按钮
  static const FontWeight normal = FontWeight.w400; // 正文
}

// ───── 9.3c 字体 token ─────
class AppFontFamilies {
  AppFontFamilies._();

  /// 加密内容等宽字体（便于辨认字符）。
  static const String mono = 'monospace';
}

// ───── 9.3d 组合文本样式 token ─────
/// 页面 / 组件**禁止自行组装** `TextStyle`，一律引用这里的组合样式。
class AppTextStyles {
  AppTextStyles._();

  /// 字标：IGotYou（唯一带字距的标题）。
  static const TextStyle wordmark = TextStyle(
    fontSize: AppFontSizes.title,
    fontWeight: AppFontWeights.strong,
    color: AppColors.gold,
    letterSpacing: AppFontSizes.titleSpacing,
  );

  /// 页面大标题（金色）。
  static const TextStyle title = TextStyle(
    fontSize: AppFontSizes.title,
    fontWeight: AppFontWeights.strong,
    color: AppColors.gold,
    decoration: TextDecoration.none,
  );

  /// 块标题（主文字）。
  static const TextStyle heading = TextStyle(
    fontSize: AppFontSizes.heading,
    fontWeight: AppFontWeights.strong,
    color: AppColors.textPrimary,
    decoration: TextDecoration.none,
  );

  /// 块标题（金色，条目名称行）。
  static const TextStyle headingGold = TextStyle(
    fontSize: AppFontSizes.heading,
    fontWeight: AppFontWeights.strong,
    color: AppColors.gold,
    decoration: TextDecoration.none,
  );

  /// 正文（主文字）。
  static const TextStyle body = TextStyle(
    fontSize: AppFontSizes.body,
    fontWeight: AppFontWeights.normal,
    color: AppColors.textPrimary,
    decoration: TextDecoration.none,
  );

  /// 正文（次级文字 / 占位 / 空态）。
  static const TextStyle bodySecondary = TextStyle(
    fontSize: AppFontSizes.body,
    fontWeight: AppFontWeights.normal,
    color: AppColors.textSecondary,
    decoration: TextDecoration.none,
  );

  /// 正文强调（金色，如钥匙"开"）。
  static const TextStyle bodyGold = TextStyle(
    fontSize: AppFontSizes.body,
    fontWeight: AppFontWeights.normal,
    color: AppColors.gold,
    decoration: TextDecoration.none,
  );

  /// 小字（次级文字）。
  static const TextStyle meta = TextStyle(
    fontSize: AppFontSizes.meta,
    fontWeight: AppFontWeights.normal,
    color: AppColors.textSecondary,
    decoration: TextDecoration.none,
  );

  /// 小字强调（金色，如钥匙"开"）。
  static const TextStyle metaGold = TextStyle(
    fontSize: AppFontSizes.meta,
    fontWeight: AppFontWeights.normal,
    color: AppColors.gold,
    decoration: TextDecoration.none,
  );

  /// 小字暗金（重复标注等辅助说明）。
  static const TextStyle metaDim = TextStyle(
    fontSize: AppFontSizes.meta,
    fontWeight: AppFontWeights.normal,
    color: AppColors.goldDim,
    decoration: TextDecoration.none,
  );

  /// 等宽正文（加密内容）。
  static const TextStyle mono = TextStyle(
    fontSize: AppFontSizes.mono,
    fontWeight: AppFontWeights.normal,
    color: AppColors.textPrimary,
    fontFamily: AppFontFamilies.mono,
    decoration: TextDecoration.none,
  );

  /// 按钮文字（颜色由按钮前景色决定，勿在此写死颜色）。
  static const TextStyle buttonLabel = TextStyle(
    fontSize: AppFontSizes.body,
    fontWeight: AppFontWeights.strong,
    decoration: TextDecoration.none,
  );
}

// ───── 9.4 间距 / 圆角 / 边框 ─────
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

  /// 保险柜门面（VaultGate）圆角。
  static const double gate = 2;
}

class AppBorder {
  AppBorder._();
  static const double width = 1;
  static const Color color = AppColors.goldDim;
  static const Color activeColor = AppColors.gold;

  /// 保险柜门面（VaultGate）边框宽度。
  static const double gateWidth = 1;
}

// ───── 9.4b 渐变 token ─────
class AppGradients {
  AppGradients._();

  /// 保险柜门面金属渐变：上亮下暗，模拟金属柜门受光。
  static const LinearGradient gateMetal = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [AppColors.surfaceAlt, AppColors.surface, AppColors.bg],
    stops: [0.0, 0.55, 1.0],
  );

  /// 顶部覆盖遮罩（主页/设置/备份/编辑页顶栏）：顶部实心 → 向下平滑淡出。
  /// 条目滚动到顶栏下方时透出渐隐，不是实心遮挡。
  static const LinearGradient topScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      AppColors.bg,
      Color(0xE60D0D0D), // bg @ 0.90
      Color(0x7A0D0D0D), // bg @ 0.48
      Color(0x000D0D0D), // bg @ 0.00 → 透明
    ],
    stops: [0.0, 0.34, 0.72, 1.0],
  );

  /// 底部渐隐遮罩（主页/设置/备份/编辑页）：底部实心 → 向上平滑淡出。
  /// 条目滚动到检索浮层下方时透出渐隐。
  static const LinearGradient bottomScrim = LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: [
      AppColors.bg,
      Color(0xE60D0D0D), // bg @ 0.90
      Color(0x7A0D0D0D), // bg @ 0.48
      Color(0x000D0D0D), // bg @ 0.00 → 透明
    ],
    stops: [0.0, 0.34, 0.72, 1.0],
  );
}

// ───── 9.4c 时长 token（DEVELOPMENT 9.4c）─────
class AppDurations {
  AppDurations._();

  /// 冷却倒计时刷新间隔（解锁页每秒刷新按钮上的冷却文案）。
  static const Duration cooldownTick = Duration(seconds: 1);

  /// 顶部提示横幅滑入时长。
  static const Duration bannerIn = Duration(milliseconds: 240);

  /// 顶部提示横幅滑出时长。
  static const Duration bannerOut = Duration(milliseconds: 200);

  /// 顶部提示横幅停留时长。
  static const Duration bannerHold = Duration(milliseconds: 2600);
}

// ───── 9.4d 阴影 token ─────
class AppShadows {
  AppShadows._();

  /// 顶部提示横幅投影：弥散柔和的悬浮感，不在文字下方形成"下划线"。
  static const BoxShadow banner = BoxShadow(
    color: Color(0x30000000),
    blurRadius: 20,
    offset: Offset(0, 2),
  );
}

// ───── 9.5 尺寸 token ─────
class AppSizes {
  AppSizes._();
  static const double buttonHeight = 48;

  /// 主操作大按钮（锁定 / 打开）高度。
  static const double heroButtonHeight = 56;
  static const double inputHeight = 48;

  /// 输入框前缀图标尺寸。
  static const double iconSize = 18;

  /// 输入框前缀图标槽位宽度（vault_field 用）。
  static const double fieldPrefixWidth = 40;

  /// 顶部小导航按钮（主页设置/备份/添加）高度。
  static const double navButtonHeight = 34;

  /// 顶栏（VaultTopBar）内容行高度。
  static const double topBarHeight = 48;

  /// 顶栏前置按钮尺寸（返回箭头 / 关闭叉）。
  static const double topBarIconSize = 24;

  /// 顶栏无前置按钮时的占位宽度（保持标题对齐）。
  static const double topBarLeadingWidth = 48;

  /// 顶部渐变遮罩总高度（不含状态栏安全区）。
  /// 所有页面（主页面板 / 各页面顶栏）共用同一数值，全局调整只改此处。
  static const double scrimHeight = 136;

  /// 顶部/底部覆盖遮罩的过渡区高度。
  static const double scrimFade = 48;

  /// 底部渐隐遮罩总高度（不含底部安全区）：比顶栏高，容纳检索浮层的淡出区。
  static const double bottomMaskHeight = 180;

  /// 底部检索+按钮浮层内容高度（不含底部安全区）。
  static const double bottomChromeHeight = 110;

  /// 主页列表底部留白（不含底部安全区）：略高于检索浮层顶（+18 呼吸余量），
  /// 让条目可滑入底部渐隐遮罩下方再淡出，而不是硬切。
  static const double homeListBottomInset = bottomChromeHeight + 18;

  /// 顶部提示横幅最大宽度。
  static const double bannerMaxWidth = 480;

  /// 列表条目间距。
  static const double tileGap = 8;

  /// 条目左侧钥匙图标点击区宽度（与条目卡片同高、方形反馈）。
  static const double tileKeyWidth = 56;

  /// 条目左侧钥匙图标尺寸（金色实心锁 = 作为钥匙 / 灰色开锁 = 不作为）。
  static const double tileKeyIconSize = 24;

  /// 保险柜门面（VaultGate）最大宽度，居中表单区。
  static const double gateMaxWidth = 360;

  /// 保险柜门面（VaultGate）内边距。
  static const double gatePadding = 32;

  /// 门面内输入区与主按钮间距。
  static const double gateGap = 24;
}

// ───── 9.5b 保险柜门面 尺寸 token ─────
// （保险柜门面相关尺寸已并入上方 AppSizes / AppRadius / AppBorder）
