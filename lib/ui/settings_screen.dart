import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/models/vault_config.dart';
import '../core/vault_session.dart';
import '../theme/tokens.dart';
import 'widgets/vault_banner.dart';
import 'widgets/vault_bottom_scrim.dart';
import 'widgets/vault_button.dart';
import 'widgets/vault_field.dart';
import 'widgets/vault_top_bar.dart';

/// 设置页：命中数 K、机会 M、冷却后机会 C、冷却基础序列、冷却增长率。
/// 无保存按钮：字段失去焦点即自动保存；校验失败在顶部横幅报错。
/// 清空保险柜使用统一的危险操作按钮。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _kCtrl;
  late final TextEditingController _mCtrl;
  late final TextEditingController _cCtrl;
  late final TextEditingController _baseCtrl;
  late final TextEditingController _growthCtrl;
  late final FocusNode _kFocus;
  late final FocusNode _mFocus;
  late final FocusNode _cFocus;
  late final FocusNode _baseFocus;
  late final FocusNode _growthFocus;
  bool _dirty = false;
  bool _saving = false;
  bool _allowPop = false;

  /// 正在进行的保存（供锁定/返回等待）。
  Future<void>? _inFlightSave;

  @override
  void initState() {
    super.initState();
    final cfg = context.read<AppState>().session!.config;
    _kCtrl = TextEditingController(text: '${cfg.hitCount}');
    _mCtrl = TextEditingController(text: '${cfg.roundChances}');
    _cCtrl = TextEditingController(text: '${cfg.cooldownChances}');
    _baseCtrl = TextEditingController(text: cfg.cooldownBase.join(','));
    _growthCtrl = TextEditingController(text: '${cfg.cooldownGrowth}');
    _kFocus = FocusNode()..addListener(() => _onLostFocus(_kFocus));
    _mFocus = FocusNode()..addListener(() => _onLostFocus(_mFocus));
    _cFocus = FocusNode()..addListener(() => _onLostFocus(_cFocus));
    _baseFocus = FocusNode()..addListener(() => _onLostFocus(_baseFocus));
    _growthFocus = FocusNode()..addListener(() => _onLostFocus(_growthFocus));
  }

  @override
  void dispose() {
    _kCtrl.dispose();
    _mCtrl.dispose();
    _cCtrl.dispose();
    _baseCtrl.dispose();
    _growthCtrl.dispose();
    _kFocus.dispose();
    _mFocus.dispose();
    _cFocus.dispose();
    _baseFocus.dispose();
    _growthFocus.dispose();
    super.dispose();
  }

  /// 字段失去焦点即自动保存（有改动才保存）。
  void _onLostFocus(FocusNode node) {
    if (node.hasFocus || !_dirty || _saving) return;
    _inFlightSave = _trySave();
  }

  void _markDirty() => setState(() => _dirty = true);

  VaultConfig? _buildConfig() {
    final hit = int.tryParse(_kCtrl.text.trim());
    if (hit == null || hit < 1) {
      _banner('命中数请输入正整数');
      return null;
    }
    final m = int.tryParse(_mCtrl.text.trim());
    if (m == null || m < 1) {
      _banner('每轮机会请输入正整数');
      return null;
    }
    final c = int.tryParse(_cCtrl.text.trim());
    if (c == null || c < 1) {
      _banner('冷却后机会请输入正整数');
      return null;
    }
    final growth = int.tryParse(_growthCtrl.text.trim());
    if (growth == null || growth < 1) {
      _banner('冷却增长率请输入正整数');
      return null;
    }
    final baseParts = _baseCtrl.text
        .split(RegExp(r'[,，\s]+'))
        .map((s) => int.tryParse(s.trim()))
        .toList();
    if (baseParts.isEmpty || baseParts.any((v) => v == null || v < 1)) {
      _banner('冷却序列请输入正整数，如 1 或 10,10,10');
      return null;
    }
    return VaultConfig(
      hitCount: hit,
      roundChances: m,
      cooldownChances: c,
      cooldownBase: baseParts.cast<int>(),
      cooldownGrowth: growth,
    );
  }

  /// 校验并保存配置；返回是否成功。
  Future<bool> _trySave() async {
    final session = context.read<AppState>().session!;
    final cfg = _buildConfig();
    if (cfg == null) return false;
    final err = session.updateConfig(cfg);
    if (err != null) {
      _banner(err);
      return false;
    }
    _saving = true;
    try {
      await session.save();
      if (mounted) setState(() => _dirty = false);
      return true;
    } catch (_) {
      if (mounted) _banner('保存失败');
      return false;
    } finally {
      _saving = false;
    }
  }

  /// 等待未完成的保存；还有改动则再保存一次（锁定前调用）。
  Future<void> _flushSaves() async {
    if (_inFlightSave != null) {
      await _inFlightSave;
      _inFlightSave = null;
    }
    if (_dirty && !_saving) {
      _inFlightSave = _trySave();
      await _inFlightSave;
      _inFlightSave = null;
    }
  }

  /// 返回前保存；保存成功才真正退出。
  Future<void> _handlePop() async {
    if (_dirty) {
      final ok = await _trySave();
      if (!ok || !mounted) return;
    }
    if (!mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _toggleKey(VaultSession session, String id) async {
    final entry = session.entryById(id);
    if (entry == null) return;
    try {
      final adjustedK = session.setEntryKey(entry, !entry.isKey);
      // 先刷新 UI 再保存：重切分份额（Argon2id 派生）耗时较长。
      if (mounted) setState(() {});
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
        _banner('钥匙数减少，命中数已调整为 $adjustedK');
      }
    } on VaultKeyMissingException catch (e) {
      if (mounted) _banner('$e');
    } on StateError catch (e) {
      if (mounted) _banner(e.message);
    } catch (_) {
      if (mounted) _banner('保存失败');
    }
  }

  void _banner(String text) {
    if (mounted) showVaultBanner(context, text);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final session = app.session!;
    final keys = session.keyEntries;
    final mq = MediaQuery.of(context);
    final topInset = VaultTopBar.totalHeight(mq);
    // 底部遮罩区高度：与顶部渐变区对称（VaultBottomScrim.height = bottom + bottomMaskHeight）。
    final bottomInset = VaultBottomScrim.height(mq);

    return Scaffold(
      body: PopScope(
        canPop: _allowPop,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          _handlePop();
        },
        child: Stack(
          children: [
            // 全屏内容：从顶栏遮罩淡出区之下开始滚动
            Positioned.fill(
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.unit6,
                    topInset,
                    AppSpacing.unit6,
                    bottomInset,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _label('命中数 K'),
                      _label('解锁需要命中的不同密码数量'),
                      const SizedBox(height: AppSpacing.unit2),
                      VaultField(
                        controller: _kCtrl,
                        hint: '如 3',
                        focusNode: _kFocus,
                        onChanged: (_) => _markDirty(),
                      ),
                      const SizedBox(height: AppSpacing.unit6),
                      _label('每轮机会 M'),
                      _label('每轮最多可输入次数，机会耗尽进入冷却'),
                      const SizedBox(height: AppSpacing.unit2),
                      VaultField(
                        controller: _mCtrl,
                        hint: '如 30',
                        focusNode: _mFocus,
                        onChanged: (_) => _markDirty(),
                      ),
                      const SizedBox(height: AppSpacing.unit6),
                      _label('冷却后机会 C'),
                      _label('冷却结束后每轮的机会数'),
                      const SizedBox(height: AppSpacing.unit2),
                      VaultField(
                        controller: _cCtrl,
                        hint: '如 1',
                        focusNode: _cFocus,
                        onChanged: (_) => _markDirty(),
                      ),
                      const SizedBox(height: AppSpacing.unit6),
                      _label('冷却基础序列（分钟）'),
                      _label('每次失败的冷却时长，如 1 或 10,10,10'),
                      const SizedBox(height: AppSpacing.unit2),
                      VaultField(
                        controller: _baseCtrl,
                        hint: '如 1 或 10,10,10',
                        focusNode: _baseFocus,
                        onChanged: (_) => _markDirty(),
                      ),
                      const SizedBox(height: AppSpacing.unit6),
                      _label('冷却增长率'),
                      _label('冷却时长按此倍数递增，1 为固定不变'),
                      const SizedBox(height: AppSpacing.unit2),
                      VaultField(
                        controller: _growthCtrl,
                        hint: '如 2',
                        focusNode: _growthFocus,
                        onChanged: (_) => _markDirty(),
                      ),
                      const SizedBox(height: AppSpacing.unit6),
                      _label(
                        '钥匙（${session.distinctKeyCount} 种密码 / ${keys.length} 个）',
                      ),
                      const SizedBox(height: AppSpacing.unit2),
                      if (keys.isEmpty)
                        const Text('暂无钥匙', style: AppTextStyles.meta)
                      else
                        for (final e in keys)
                          GestureDetector(
                            onTap: () => _toggleKey(session, e.id),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.unit2,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      e.name,
                                      style: AppTextStyles.body,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    '作为钥匙：${e.isKey ? '开' : '关'}',
                                    style: e.isKey
                                        ? AppTextStyles.metaGold
                                        : AppTextStyles.meta,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      const SizedBox(height: AppSpacing.unit6),
                      VaultDangerButton(
                        label: '清空保险柜',
                        onPressed: () => _confirmClear(),
                      ),
                      const SizedBox(height: AppSpacing.unit2),
                      const Text(
                        '清空后所有条目与设置将删除，无法恢复',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.meta,
                      ),
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
                title: '设置',
                onBack: _handlePop,
                onBeforeLock: _flushSaves,
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
      ),
    );
  }

  /// 字段标签 / 小字备注（统一小字样式）。
  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.unit2),
      child: Text(text, style: AppTextStyles.meta),
    );
  }

  /// 清空保险柜：需输入"清空"二字确认（DEVELOPMENT 8.6）。
  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => const _ClearVaultDialog(),
    );
    if (confirmed != true || !mounted) return;
    final app = context.read<AppState>();
    await app.clearVault();
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }
}

/// 清空保险柜确认对话框：必须输入"清空"才能确认。
class _ClearVaultDialog extends StatefulWidget {
  const _ClearVaultDialog();

  @override
  State<_ClearVaultDialog> createState() => _ClearVaultDialogState();
}

class _ClearVaultDialogState extends State<_ClearVaultDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canConfirm = _ctrl.text.trim() == '清空';
    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('清空保险柜？所有条目与设置将删除，无法恢复', style: AppTextStyles.body),
          const SizedBox(height: AppSpacing.unit4),
          VaultField(
            controller: _ctrl,
            hint: '输入"清空"确认',
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        VaultTextButton(
          label: '取消',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        VaultTextButton(
          label: '清空',
          onPressed: canConfirm ? () => Navigator.of(context).pop(true) : null,
        ),
      ],
    );
  }
}
