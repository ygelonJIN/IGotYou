import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/models/vault_config.dart';
import '../../core/vault_session.dart';
import '../../theme/tokens.dart';
import '../backup_screen.dart';
import 'pill_button.dart';
import 'vault_banner.dart';
import 'vault_button.dart';
import 'vault_field.dart';

/// 设置侧栏：从左侧滑入、覆盖约 75% 屏幕；内部「全屏滚动 + 浮层控制」——
/// 顶部仅标题「设置」，底部工具区（备份 / 清空保险柜）悬浮，
/// 中间内容区全屏滚动。
///
/// 内容自上而下：命中数 K / 每轮机会 M / 冷却后机会 C /
/// 冷却基础序列 / 冷却增长率 / 钥匙列表。
/// 无保存按钮：字段失去焦点即自动保存；校验失败在顶部横幅报错。
/// 收起方式：点击主页遮罩或系统返回键（无返回箭头 / 上锁按钮）。
class SettingsPanel extends StatefulWidget {
  final VoidCallback onClose;

  const SettingsPanel({super.key, required this.onClose});

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
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

  /// 正在进行的保存（供锁定前等待）。
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
    // 全局上锁按钮锁定前：先落盘未保存的配置改动。
    context.read<AppState>().setBeforeLock(_flushSaves);
  }

  @override
  void dispose() {
    context.read<AppState>().setBeforeLock(null);
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

  /// 锁定前等待未完成的保存；还有改动则再保存一次。
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

  void _openBackup() {
    widget.onClose();
    Navigator.of(
      context,
    ).push<void>(MaterialPageRoute<void>(builder: (_) => const BackupScreen()));
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
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final session = app.session!;
    final keys = session.keyEntries;
    final mq = MediaQuery.of(context);
    final topInset = mq.padding.top + AppSizes.settingsTopInset;
    final bottomInset = mq.padding.bottom + AppSizes.settingsBottomInset;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          right: BorderSide(
            color: AppColors.textSecondary.withValues(alpha: 0.45),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 28,
            offset: const Offset(8, 0),
          ),
        ],
      ),
      // 全屏通栏：阴影从顶到底无缝（不套 SafeArea，各浮层自管安全区）。
      child: Stack(
        children: [
          // 全屏滚动内容（从标题浮层之下开始）
          Positioned.fill(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.unit4,
                topInset,
                AppSpacing.unit4,
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
                  const Text(
                    '设置失焦即自动保存',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.meta,
                  ),
                ],
              ),
            ),
          ),
          // 顶部渐隐（与面板同色，不再出现其它颜色色带）
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: AppSizes.settingsTopScrim,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: AppGradients.surfaceTopScrim,
                ),
              ),
            ),
          ),
          // 顶部浮层：标题「设置」+ 右上角上锁胶囊。
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.unit4,
                  AppSizes.topChromeInset,
                  AppSpacing.unit4,
                  AppSpacing.unit2,
                ),
                child: Row(
                  children: [
                    Text('设置', style: AppTextStyles.title),
                    const Spacer(),
                    SizedBox(
                      width: 94,
                      child: PillButton(
                        icon: Icons.lock_outline,
                        label: '上锁',
                        highlight: true,
                        onTap: () async {
                          FocusManager.instance.primaryFocus?.unfocus();
                          final app = context.read<AppState>();
                          await app.beforeLock?.call();
                          if (!context.mounted) return;
                          await app.lock();
                          Navigator.of(context).popUntil((r) => r.isFirst);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 底部渐隐（与面板同色）
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: AppSizes.settingsBottomScrim,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: AppGradients.surfaceBottomScrim,
                ),
              ),
            ),
          ),
          // 底部浮层：备份 / 重置（同一行，一左一右）。
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.unit4,
                  AppSpacing.unit4,
                  AppSpacing.unit4,
                  AppSpacing.unit4,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: VaultDangerButton(
                        label: '备份',
                        onPressed: _openBackup,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.unit2),
                    Expanded(
                      child: VaultDangerButton(
                        label: '重置',
                        onPressed: _confirmClear,
                      ),
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

  /// 顶部渐隐：与面板 `surface` 同色，从实心平滑淡出（无其它颜色色带）。
  static final LinearGradient _surfaceTopScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      AppColors.surface.withValues(alpha: 1),
      AppColors.surface.withValues(alpha: 0.92),
      AppColors.surface.withValues(alpha: 0),
    ],
    stops: const [0.0, 0.6, 1.0],
  );

  /// 底部渐隐：与面板 `surface` 同色，从实心平滑淡出。
  static final LinearGradient _surfaceBottomScrim = LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: [
      AppColors.surface.withValues(alpha: 1),
      AppColors.surface.withValues(alpha: 0.92),
      AppColors.surface.withValues(alpha: 0),
    ],
    stops: const [0.0, 0.6, 1.0],
  );

  /// 字段标签 / 小字备注（统一小字样式）。
  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.unit2),
      child: Text(text, style: AppTextStyles.meta),
    );
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