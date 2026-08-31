import 'package:flutter/material.dart';
import 'tokens.dart';

ThemeData buildVaultTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.gold,
      secondary: AppColors.gold,
      surface: AppColors.surface,
      error: AppColors.gold,
    ),
    textTheme: const TextTheme(
      titleLarge: AppTextStyles.title,
      titleMedium: AppTextStyles.heading,
      bodyLarge: AppTextStyles.body,
      bodyMedium: AppTextStyles.meta,
      labelLarge: AppTextStyles.buttonLabel,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      centerTitle: true,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.dialog)),
        side: BorderSide(color: AppColors.goldDim, width: AppBorder.width),
      ),
    ),
  );
}