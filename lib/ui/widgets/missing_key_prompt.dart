import 'package:flutter/material.dart';

import '../../core/vault_session.dart';
import '../../theme/tokens.dart';
import 'vault_button.dart';
import 'vault_field.dart';

/// 二次加密钥匙条目明文密钥缺失时，弹窗输入并验证缓存（份额重切前补齐）。
/// 返回 true 表示已输入正确密钥（已缓存），可重试保存。
Future<bool> promptMissingDoubleKey(
  BuildContext context,
  VaultSession session,
  String entryName,
) async {
  final entry = session.entries.where((e) => e.name == entryName).firstOrNull;
  if (entry == null) return false;
  final ctrl = TextEditingController();
  String? error;
  while (true) {
    if (!context.mounted) {
      ctrl.dispose();
      return false;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '需要条目「$entryName」的加密密钥：'
              '输入后即可重切份额（该条目为二次加密钥匙）。',
              style: AppTextStyles.body,
            ),
            const SizedBox(height: AppSpacing.unit4),
            VaultField(
              controller: ctrl,
              hint: '加密密钥',
              mono: true,
              obscure: true,
              onSubmitted: () => Navigator.of(ctx).pop(true),
            ),
            if (error != null) ...[
              const SizedBox(height: AppSpacing.unit2),
              Text(error, style: AppTextStyles.bodySecondary),
            ],
          ],
        ),
        actions: [
          VaultTextButton(
            label: '取消',
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          VaultTextButton(
            label: '确认',
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    final key = ctrl.text.trim();
    ctrl.clear();
    if (ok != true || key.isEmpty) {
      ctrl.dispose();
      return false;
    }
    try {
      await session.unlockDoubleLock(entry, key);
      ctrl.dispose();
      return true;
    } on StateError {
      // 密钥不正确：关闭当前对话框，重新弹出让用户再输。
      error = '加密密钥不正确';
      if (!context.mounted) return false;
    }
  }
}
