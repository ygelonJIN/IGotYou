import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/models/entry.dart';
import '../core/vault_session.dart';
import '../theme/tokens.dart';
import 'backup_screen.dart';
import 'entry_edit_screen.dart';
import 'settings_screen.dart';
import 'widgets/vault_banner.dart';
import 'widgets/vault_bottom_scrim.dart';
import 'widgets/vault_button.dart';
import 'widgets/vault_entry_tile.dart';
import 'widgets/vault_field.dart';
import 'widgets/vault_top_bar.dart';

/// 保险柜主页：全屏覆盖布局。
/// - 顶部：统一顶栏组件（上锁 + 渐变遮罩，与各页面同一位置）。
/// - 全屏条目列表（滚动穿过面板，条目从上下遮罩下透出渐隐）。
/// - 底部：渐隐遮罩（IgnorePointer）+ 检索框/设置/备份/添加浮层，
///   浮层直接压在遮罩之上；条目可滑入遮罩下方淡出（非硬切）。
class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final session = app.session!;
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? session.entries
        : session.entries
              .where((e) => e.name.toLowerCase().contains(q))
              .toList();

    final mq = MediaQuery.of(context);
    // 顶部渐变区总高：统一顶栏（VaultTopBar.totalHeight = safeTop + scrimHeight），
    // 与各页面同一数值，全局只调 AppSizes.scrimHeight。
    final topInset = VaultTopBar.totalHeight(mq);
    // 底部列表留白：略高于检索浮层顶（safeBottom + homeListBottomInset），
    // 让条目可滑入底部渐隐遮罩下方再淡出，而不是硬切。
    final bottomInset = mq.padding.bottom + AppSizes.homeListBottomInset;

    return Scaffold(
      body: Stack(
        children: [
          // 全屏条目列表（顶部从面板下开始，底部让出检索框区）
          Positioned.fill(
            child: GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              behavior: HitTestBehavior.translucent,
              child: filtered.isEmpty
                  ? const Center(
                      child: Text('暂无条目', style: AppTextStyles.bodySecondary),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.only(
                        top: topInset,
                        bottom: bottomInset,
                        left: AppSpacing.unit4,
                        right: AppSpacing.unit4,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final e = filtered[i];
                        return Padding(
                          padding: const EdgeInsets.only(
                            bottom: AppSizes.tileGap,
                          ),
                          child: VaultEntryTile(
                            entry: e,
                            onTap: () => _openEdit(session, e),
                            onToggleKey: () {
                              _toggleKey(session, e);
                            },
                          ),
                        );
                      },
                    ),
            ),
          ),
          // 顶部：统一顶栏组件（上锁 + 渐变遮罩），与设置/备份/编辑页同一位置。
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: VaultTopBar(
              title: '',
              showBack: false,
              showTitleRow: false,
              onBack: () {},
            ),
          ),
          // 底部渐隐遮罩：仅视觉（IgnorePointer），条目滚动经过时透出渐隐。
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: const VaultBottomScrim(),
          ),
          // 底部浮层：设置/备份/添加 + 检索框，直接压在渐隐遮罩之上。
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.unit4,
                  AppSpacing.unit3,
                  AppSpacing.unit4,
                  AppSpacing.unit4,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 设置 / 备份 / 添加
                    Row(
                      children: [
                        _TopNavButton(
                          '设置',
                          () => _openSettings(context),
                        ),
                        const SizedBox(width: AppSpacing.unit2),
                        _TopNavButton(
                          '备份',
                          () => _openBackup(context),
                        ),
                        const SizedBox(width: AppSpacing.unit2),
                        _TopNavButton(
                          '添加',
                          () => _openEdit(session, null),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.unit3),
                    // 检索框
                    VaultField(
                      controller: _search,
                      hint: '检索',
                      icon: Icons.search,
                      textInputAction: TextInputAction.search,
                      onChanged: (v) => setState(() => _query = v),
                      onSubmitted: () => FocusScope.of(context).unfocus(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleKey(VaultSession session, Entry entry) async {
    final target = !entry.isKey;
    // 二次加密钥匙条目未查看（密钥未缓存）时，重切份额需要先输入其密钥；
    // 每次缺失引导输入后重试，可连续补齐多把（最多 8 轮防御死循环）。
    for (var attempt = 0; attempt < 8; attempt++) {
      try {
        final adjustedK = session.setEntryKey(entry, target);
        // 先刷新 UI 再保存：重切分份额（Argon2id 派生）耗时较长，
        // 若等保存完再 setState，点击后界面会长时间无变化。
        if (!mounted) return;
        setState(() {});
        try {
          await session.save();
        } catch (_) {
          // 保存失败（如二次加密钥匙密钥缺失）：回滚内存状态，界面恢复原状。
          session.setEntryKey(entry, entry.isKey);
          if (mounted) setState(() {});
          rethrow;
        }
        if (!mounted) return;
        if (adjustedK != null) {
          showVaultBanner(context, '钥匙数减少，命中数已调整为 $adjustedK');
        }
        return;
      } on VaultKeyMissingException catch (e) {
        // 引导输入缺失的二次加密条目密钥；取消则放弃本次切换。
        final ok = await _promptMissingDoubleKey(session, e.entryName);
        if (!ok || !mounted) return;
      } on StateError catch (e) {
        if (mounted) showVaultBanner(context, e.message);
        return;
      } catch (_) {
        if (mounted) showVaultBanner(context, '保存失败');
        return;
      }
    }
  }

  /// 二次加密钥匙条目密钥缺失时，弹窗输入并验证缓存（DEVELOPMENT 17.13）。
  /// 返回 true 表示已输入正确密钥，可重试份额重切。
  Future<bool> _promptMissingDoubleKey(
    VaultSession session,
    String entryName,
  ) async {
    final entry = session.entries.where((e) => e.name == entryName).firstOrNull;
    if (entry == null) return false;
    final ctrl = TextEditingController();
    String? error;
    while (true) {
      if (!mounted) {
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
        if (!mounted) return false;
      }
    }
  }

  Future<void> _openEdit(VaultSession session, Entry? entry) async {
    // 先收起焦点，避免从子页面返回时检索框自动激活。
    FocusManager.instance.primaryFocus?.unfocus();
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => EntryEditScreen(entry: entry, session: session),
      ),
    );
    if (mounted) setState(() {});
  }

  void _openSettings(BuildContext context) {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
  }

  void _openBackup(BuildContext context) {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(
      context,
    ).push<void>(MaterialPageRoute<void>(builder: (_) => const BackupScreen()));
  }
}

/// 顶部小导航按钮（覆盖层用）。
class _TopNavButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _TopNavButton(this.label, this.onPressed);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppSizes.navButtonHeight,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          // 与检索框同款边框背景；字体金色（DEVELOPMENT 8.13）。
          foregroundColor: AppColors.gold,
          backgroundColor: AppColors.surface,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.unit4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(AppRadius.button)),
            side: const BorderSide(
              color: AppColors.goldDim,
              width: AppBorder.width,
            ),
          ),
          textStyle: AppTextStyles.buttonLabel,
        ),
        child: Text(label),
      ),
    );
  }
}
