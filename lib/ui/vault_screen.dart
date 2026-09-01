import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/models/entry.dart';
import '../core/vault_session.dart';
import '../theme/tokens.dart';
import 'entry_edit_screen.dart';
import 'widgets/pill_button.dart';
import 'widgets/settings_panel.dart';
import 'widgets/vault_banner.dart';
import 'widgets/vault_bottom_scrim.dart';
import 'widgets/vault_entry_tile.dart';
import 'widgets/vault_field.dart';
import 'widgets/missing_key_prompt.dart';

/// 保险柜主页：全屏覆盖布局。
/// - 顶部浮层：设置胶囊。
/// - 全屏条目列表（滚动穿过面板，条目从上下遮罩下透出渐隐）。
/// - 底部：渐隐遮罩（IgnorePointer）+ 检索浮层（检索框 + 右侧添加胶囊），
///   浮层直接压在遮罩之上；条目可滑入遮罩下方淡出（非硬切）。
/// - 设置页从左侧滑入（75% 面板 + 遮罩），收起沿浮层控制。
/// - 「上锁」不在页内，由全局 `VaultLockButtonOverlay` 渲染在右上角
///   （与主页顶部胶囊同一水平线），设置页展开时隐藏。
class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  final _search = TextEditingController();
  String _query = '';
  bool _settingsOpen = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _openSettings() {
    if (_settingsOpen) return;
    context.read<AppState>().setSettingsOpen(true);
    FocusScope.of(context).unfocus();
    setState(() => _settingsOpen = true);
  }

  void _closeSettings() {
    if (!_settingsOpen) return;
    context.read<AppState>().setSettingsOpen(false);
    FocusScope.of(context).unfocus();
    setState(() => _settingsOpen = false);
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

    return PopScope(
      canPop: !_settingsOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _settingsOpen) _closeSettings();
      },
      child: Scaffold(
        body: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final settingsWidth = width * 0.75;

            return Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                // 主页主内容：设置展开时右移 75%，仅左侧 1/4 可见。
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 340),
                  curve: Curves.easeOutCubic,
                  left: _settingsOpen ? settingsWidth : 0,
                  top: 0,
                  bottom: 0,
                  width: width,
                  child: _buildHomeBody(
                    context,
                    session: session,
                    filtered: filtered,
                  ),
                ),
                // 遮罩：盖住可见的主页区，点击收起设置。
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: !_settingsOpen,
                    child: AnimatedOpacity(
                      opacity: _settingsOpen ? 1 : 0,
                      duration: const Duration(milliseconds: 340),
                      curve: Curves.easeOutCubic,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _closeSettings,
                        child: ColoredBox(
                          color: Colors.black.withValues(alpha: 0.26),
                        ),
                      ),
                    ),
                  ),
                ),
                // 设置页（左侧 75%），从左侧滑入。
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 340),
                  curve: Curves.easeOutCubic,
                  left: _settingsOpen ? 0 : -settingsWidth,
                  top: 0,
                  bottom: 0,
                  width: settingsWidth,
                  child: SettingsPanel(
                    onClose: _closeSettings,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 主页主内容（全屏列表 + 浮层控制）。
  Widget _buildHomeBody(
    BuildContext context, {
    required VaultSession session,
    required List<Entry> filtered,
  }) {
    return Stack(
      children: [
        Positioned.fill(child: Container(color: AppColors.bg)),
        // 全屏条目列表（顶部从浮层下开始，底部让出检索框区）
        Positioned.fill(
          child: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            behavior: HitTestBehavior.translucent,
            child: filtered.isEmpty
                ? const _EmptyVaultState()
                : ListView.builder(
                    padding: EdgeInsets.fromLTRB(
                      AppSizes.pageEdge,
                      AppSizes.contentTopInset,
                      AppSizes.pageEdge,
                      AppSizes.contentBottomInset,
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
        // 顶部遮罩：压在滚动内容之上，让滚到顶栏下的条目柔和淡出。
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: AppSizes.topScrimHeight,
          child: IgnorePointer(
            child: const DecoratedBox(
              decoration: BoxDecoration(gradient: AppGradients.topScrim),
            ),
          ),
        ),
        // 顶部浮层：设置胶囊（上锁由全局 VaultLockButtonOverlay 渲染，避免动画双按钮）。
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                AppSizes.pageEdge,
                AppSizes.topChromeInset,
                AppSizes.pageEdge,
                0,
              ),
              child: Row(
                children: [
                  PillButton(
                    icon: Icons.menu_rounded,
                    label: '设置',
                    highlight: true,
                    onTap: _openSettings,
                  ),
                ],
              ),
            ),
          ),
        ),
        // 底部遮罩：只做视觉（IgnorePointer），条目滚动经过时透出渐隐。
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: const VaultBottomScrim(),
        ),
        // 底部浮层：检索框（外置添加按钮，不并入检索框内），
        // 直接压在渐隐遮罩之上。
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                AppSizes.pageEdge,
                12,
                AppSizes.pageEdge,
                16,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: AppSizes.searchBarHeight,
                      child: VaultField(
                        controller: _search,
                        hint: '检索',
                        icon: Icons.search,
                        compact: true,
                        textInputAction: TextInputAction.search,
                        onChanged: (v) => setState(() => _query = v),
                        onSubmitted: () => FocusScope.of(context).unfocus(),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.unit2),
                  SizedBox(
                    width: 94,
                    child: _SearchAddChip(
                      onTap: () => _openEdit(session, null),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
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
        final ok = await promptMissingDoubleKey(context, session, e.entryName);
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
}

/// 检索浮层右侧的「添加」胶囊：与设置按钮同样的布局风格、同宽。
class _SearchAddChip extends StatelessWidget {
  final VoidCallback onTap;

  const _SearchAddChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PillButton(
      icon: Icons.add_rounded,
      label: '添加',
      highlight: true,
      onTap: onTap,
    );
  }
}

/// 保险柜还没有任何条目时的空白态：两行克制引文。
class _EmptyVaultState extends StatelessWidget {
  const _EmptyVaultState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 200, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '重要的，只交给自己。',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 24,
              fontWeight: AppFontWeights.strong,
              height: 1,
            ),
          ),
          SizedBox(height: 20),
          Text(
            '这里不解释，只守口如瓶。',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 20,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}