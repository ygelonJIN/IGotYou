import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// 输入框：surface 底、1px goldDim 边框、聚焦时 gold 边框（DEVELOPMENT 9.5）。
/// [mono] 为 true 时使用等宽字体（加密内容用，DEVELOPMENT 9.3）。
class VaultField extends StatefulWidget {
  final TextEditingController? controller;
  final String hint;
  final bool mono;
  final bool obscure;
  final int? maxLines;
  final IconData? icon;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  final VoidCallback? onSubmitted;

  const VaultField({
    super.key,
    this.controller,
    required this.hint,
    this.mono = false,
    this.obscure = false,
    this.maxLines = 1,
    this.icon,
    this.onChanged,
    this.focusNode,
    this.textInputAction,
    this.onSubmitted,
  });

  @override
  State<VaultField> createState() => _VaultFieldState();
}

class _VaultFieldState extends State<VaultField> {
  late final FocusNode _focusNode;
  late final bool _ownsFocus;

  @override
  void initState() {
    super.initState();
    _ownsFocus = widget.focusNode == null;
    _focusNode = widget.focusNode ?? FocusNode();
  }

  @override
  void dispose() {
    if (_ownsFocus) _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      focusNode: _focusNode,
      obscureText: widget.obscure,
      maxLines: widget.maxLines,
      onChanged: widget.onChanged,
      textInputAction: widget.textInputAction,
      onSubmitted: (_) => widget.onSubmitted?.call(),
      // 禁用拼写检查/智能下划线（避免输入内容下方出现 iOS 系统下划线）。
      autocorrect: false,
      enableSuggestions: false,
      style: widget.mono ? AppTextStyles.mono : AppTextStyles.body,
      decoration: InputDecoration(
        hintText: widget.hint,
        prefixIcon: widget.icon == null
            ? null
            : Icon(widget.icon, size: AppSizes.iconSize, color: AppColors.goldDim),
        prefixIconConstraints: const BoxConstraints(minWidth: AppSizes.fieldPrefixWidth),
        hintStyle: AppTextStyles.bodySecondary,
        filled: true,
        fillColor: AppColors.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.unit4,
          vertical: AppSpacing.unit3,
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.input)),
          borderSide: BorderSide(color: AppColors.goldDim, width: AppBorder.width),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.input)),
          borderSide: BorderSide(color: AppColors.gold, width: AppBorder.width),
        ),
      ),
    );
  }
}
