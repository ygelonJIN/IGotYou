import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_state.dart';
import '../theme/tokens.dart';
import 'widgets/vault_banner.dart';
import 'widgets/vault_bottom_scrim.dart';
import 'widgets/vault_button.dart';
import 'widgets/vault_top_bar.dart';

/// 备份页：导出 .igotyou 通过系统分享，导入备份库文件。
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final topInset = VaultTopBar.totalHeight(mq);
    // 底部遮罩区高度：与顶部渐变区对称（VaultBottomScrim.height = bottom + bottomMaskHeight）。
    final bottomInset = VaultBottomScrim.height(mq);

    return Scaffold(
      body: Stack(
        children: [
          // 全屏内容（从顶栏遮罩淡出区之下开始，在底部遮罩之上垂直居中）
          Positioned.fill(
            child: SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.unit6,
                  topInset,
                  AppSpacing.unit6,
                  bottomInset,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Spacer(),
                    VaultButton(
                      label: '导出备份',
                      onPressed: _busy ? null : _export,
                    ),
                    const SizedBox(height: AppSpacing.unit4),
                    VaultButton(
                      label: '导入备份',
                      onPressed: _busy ? null : _import,
                    ),
                    const SizedBox(height: AppSpacing.unit6),
                    const Text(
                      '备份即加密库文件，复用同一套钥匙',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.meta,
                    ),
                    const Spacer(),
                  ],
                ),
              ),
            ),
          ),
          // 顶部覆盖栏（统一组件：上锁 + 返回/标题，与主页同一位置）
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: VaultTopBar(
              title: '备份',
              onBack: () => Navigator.of(context).pop(),
            ),
          ),
          // 底部统一遮罩（与顶部渐变区对称）
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: const VaultBottomScrim(),
          ),
        ],
      ),
    );
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final src = File('${dir.path}/vault.igotyou');
      if (!await src.exists()) {
        _msg('文件不存在');
        return;
      }
      await SharePlus.instance.share(
        ShareParams(files: [XFile(src.path)], subject: 'IGotYou 备份'),
      );
      _msg('已导出');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      final files = await FilePickerPlatform.instance.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['igotyou'],
      );
      if (files.isEmpty) return;
      final picked = File(files.single.path!);
      if (!mounted) return;

      // 替换确认（DEVELOPMENT 8.7：默认替换）。
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: const Text('导入将替换当前保险柜，确认？', style: AppTextStyles.body),
          actions: [
            VaultTextButton(
              label: '取消',
              onPressed: () => Navigator.of(ctx).pop(false),
            ),
            VaultTextButton(
              label: '替换',
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;

      // 校验 magic/版本失败会抛异常。
      await context.read<AppState>().importVault(picked);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      _msg(e is Exception ? '$e' : '文件损坏');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _msg(String text) {
    if (!mounted) return;
    showVaultBanner(context, text);
  }
}
