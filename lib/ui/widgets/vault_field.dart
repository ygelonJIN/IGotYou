import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// 输入框：surface 底、1px goldDim 描边、直角（DEVELOPMENT 9.5）。
/// [mono] 为 true 时使用加密内容样式（全局同字体，仅尺寸/字重区分）。
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

  /// 紧凑模式（主页检索框用）：更矮的输入区，与两侧图标按钮同高对齐。
  final bool compact;

  /// 输入区右侧的内嵌小按钮（可选）。
  final Widget? trailing;

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
    this.compact = false,
    this.trailing,
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
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.input)),
        border: Border.all(color: AppColors.goldDim, width: AppBorder.width),
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        obscureText: widget.obscure,
        maxLines: widget.maxLines,
        onChanged: widget.onChanged,
        textInputAction: widget.textInputAction,
        onSubmitted: (_) => widget.onSubmitted?.call(),
        autocorrect: false,
        enableSuggestions: false,
        style: widget.mono ? AppTextStyles.mono : AppTextStyles.body,
        decoration: InputDecoration(
          hintText: widget.hint,
          prefixIcon: widget.icon == null
              ? null
              : Icon(
                  widget.icon,
                  size: AppSizes.iconSize,
                  color: AppColors.goldDim,
                ),
          prefixIconConstraints: BoxConstraints(
            minWidth: widget.compact
                ? AppSizes.fieldPrefixWidthCompact
                : AppSizes.fieldPrefixWidth,
          ),
          hintStyle: AppTextStyles.bodySecondary,
          filled: true,
          fillColor: AppColors.surface,
          isDense: true,
          suffixIcon: widget.trailing == null
              ? null
              : Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  child: widget.trailing,
                ),
          contentPadding: widget.compact
              ? const EdgeInsets.symmetric(
                  horizontal: AppSpacing.unit4,
                  vertical: AppSpacing.unit2,
                )
              : const EdgeInsets.symmetric(
                  horizontal: AppSpacing.unit4,
                  vertical: AppSpacing.unit3,
                ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
      ),
    );
  }
}

/// 检索浮层：检索框 + 右侧同款视觉小按钮。
class VaultSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSubmitted;
  final Widget? trailing;

  const VaultSearchBar({
    super.key,
    required this.controller,
    required this.hint,
    this.onChanged,
    this.onSubmitted,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return VaultField(
      controller: controller,
      hint: hint,
      icon: Icons.search,
      compact: true,
      trailing: trailing,
      textInputAction: TextInputAction.search,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
    );
  }
}

/// 字段分组分隔线：细横线 + 上下留白，用于分隔不同字段（名称 / 密钥 / 内容）。
/// 仅表达横向视觉边界，不能交互。
class VaultFieldDivider extends StatelessWidget {
  final EdgeInsetsGeometry padding;

  const VaultFieldDivider({
    super.key,
    this.padding = const EdgeInsets.symmetric(vertical: AppSpacing.unit4),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.unit2),
        height: 1,
        color: AppColors.goldDim.withValues(alpha: 0.32),
      ),
    );
  }
}