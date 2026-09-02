import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/unlock/unlock_engine.dart';
import '../theme/tokens.dart';
import 'widgets/vault_banner.dart';
import 'widgets/vault_button.dart';
import 'widgets/vault_field.dart';
import 'widgets/vault_gate.dart';

/// 解锁 / 首次创建页（DEVELOPMENT 8.1 / 8.2）：
/// 保险柜门面（VaultGate）内仅放输入区与主按钮，其余信息一律不出现。
/// - 解锁页：一个密码输入框 + 主按钮；回车 = 提交（相当于点击解锁）。
///   盲输原则：按钮平时不高亮、不可点击，只显示剩余机会 / 冷却；
///   提交成功后不自动进入主页，按钮变为金色高亮「解锁」，人工点击才进入。
/// - 创建页：名称 / 加密内容 / 内容 三个输入框 + 创建按钮；
///   回车焦点依次 名称→加密内容→内容，最后手动点创建。
class UnlockScreen extends StatefulWidget {
  final bool showCreate;

  const UnlockScreen({super.key, required this.showCreate});

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _input = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _secretCtrl = TextEditingController();

  /// 内容多行框：一行一框，末尾空框用于继续添加（与查看/添加页一致）。
  final List<TextEditingController> _noteCtrls = [TextEditingController()];
  final List<FocusNode> _noteFoci = [FocusNode()];
  final _nameFocus = FocusNode();
  final _secretFocus = FocusNode();
  bool _busy = false;
  bool _entering = false;
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    _input.dispose();
    _nameCtrl.dispose();
    _secretCtrl.dispose();
    for (final c in _noteCtrls) {
      c.dispose();
    }
    for (final f in _noteFoci) {
      f.dispose();
    }
    _nameFocus.dispose();
    _secretFocus.dispose();
    super.dispose();
  }

  void _addNoteBox(String text) {
    _noteCtrls.add(TextEditingController(text: text));
    _noteFoci.add(FocusNode());
  }

  /// 内容框拼装回单行字符串（空行丢弃，行间以换行连接）。
  String get _noteText =>
      _noteCtrls.map((c) => c.text.trim()).where((s) => s.isNotEmpty).join('\n');

  /// 内容框内容变化：末尾框出现内容时追加一个空框；
  /// 其余框清空后删除（保持末尾始终只有一个空框）。
  void _onNoteChanged(int index) {
    final text = _noteCtrls[index].text;
    if (index == _noteCtrls.length - 1) {
      if (text.trim().isNotEmpty) {
        setState(() => _addNoteBox(''));
      }
    } else if (text.trim().isEmpty) {
      setState(() {
        _noteCtrls.removeAt(index).dispose();
        _noteFoci.removeAt(index).dispose();
      });
    }
  }

  /// 内容框回车：统一收起键盘，不跳转下一框。
  void _onNoteSubmitted(int index) {
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final engine = app.engine;
    _syncTicker(engine);

    final Widget body;
    if (widget.showCreate) {
      body = _buildCreateForm(context);
    } else if (engine != null) {
      body = _buildUnlockForm(context, engine);
    } else {
      body = const SizedBox.shrink();
    }

    return Scaffold(
      body: SafeArea(child: VaultGate(child: body)),
    );
  }

  // ── 首次创建表单 ──
  // 回车焦点流转：名称→加密内容→内容；内容回车收起键盘，手动点创建。

  Widget _buildCreateForm(BuildContext context) {
    final app = context.read<AppState>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        VaultField(
          controller: _nameCtrl,
          hint: '名称',
          icon: Icons.label_outline,
          focusNode: _nameFocus,
          textInputAction: TextInputAction.next,
          onSubmitted: () => FocusScope.of(context).requestFocus(_secretFocus),
          onChanged: (_) => setState(() {}),
        ),
        const VaultFieldDivider(),
        VaultField(
          controller: _secretCtrl,
          hint: '加密密钥',
          mono: true,
          obscure: true,
          icon: Icons.key_outlined,
          focusNode: _secretFocus,
          textInputAction: TextInputAction.next,
          onSubmitted: () {
            if (_noteFoci.isNotEmpty) {
              FocusScope.of(context).requestFocus(_noteFoci.first);
            }
          },
          onChanged: (_) => setState(() {}),
        ),
        const VaultFieldDivider(),
        // 内容多行框：一行一框，末尾空框用于继续添加。
        for (var i = 0; i < _noteCtrls.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.unit2),
          VaultField(
            controller: _noteCtrls[i],
            hint: i == _noteCtrls.length - 1 ? '新增内容条目' : '内容（可选）',
            icon: i == 0 ? Icons.notes : null,
            focusNode: _noteFoci[i],
            textInputAction: TextInputAction.done,
            onSubmitted: () => _onNoteSubmitted(i),
            onChanged: (_) => _onNoteChanged(i),
          ),
        ],
        const SizedBox(height: AppSizes.gateGap),
        VaultButton(
          label: '创建',
          height: AppSizes.heroButtonHeight,
          onPressed:
              _nameCtrl.text.trim().isEmpty ||
                  _secretCtrl.text.trim().isEmpty ||
                  _busy
              ? null
              : () => _create(app),
        ),
      ],
    );
  }

  Future<void> _create(AppState app) async {
    setState(() => _busy = true);
    try {
      await app.createVault(
        name: _nameCtrl.text.trim(),
        secret: _secretCtrl.text,
        note: _noteText,
      );
    } catch (_) {
      _showMessage('创建失败');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── 盲输解锁表单 ──
  // 回车 = 提交（相当于点击解锁）。按钮平时不高亮、不可点击（仅作状态显示）；
  // 提交成功后不自动进入主页，按钮变为金色高亮「解锁」，只有人工点击才进入。

  Widget _buildUnlockForm(BuildContext context, UnlockEngine engine) {
    final inCooldown = engine.inCooldown;
    final cooldownMs = engine.state.remainingCooldownMs(DateTime.now());
    final inCooldownActive = inCooldown && cooldownMs > 0;
    // 引擎已解锁（MK 已重构）：等待人工点击高亮按钮进入主页。
    final opened = engine.isUnlocked || _entering;

    final String buttonLabel;
    final bool buttonEnabled;
    final bool highlighted;
    if (opened) {
      buttonLabel = '解锁';
      buttonEnabled = true;
      highlighted = true;
    } else if (inCooldownActive) {
      buttonLabel = '冷却 ${_formatCooldown(cooldownMs)}';
      buttonEnabled = false;
      highlighted = false;
    } else {
      // 盲输：不高亮、不可点击，只显示剩余机会数。
      buttonLabel = _busy ? '解锁' : '解锁（剩余 ${engine.remainingChances} 次）';
      buttonEnabled = false;
      highlighted = false;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        VaultField(
          controller: _input,
          hint: '密码',
          mono: true,
          obscure: true,
          icon: Icons.lock_outline,
          textInputAction: TextInputAction.done,
          onSubmitted: () => _submitInput(engine),
        ),
        const SizedBox(height: AppSizes.gateGap),
        VaultButton(
          label: buttonLabel,
          height: AppSizes.heroButtonHeight,
          highlighted: highlighted,
          onPressed: buttonEnabled ? () => _enterVault(engine) : null,
        ),
      ],
    );
  }

  /// 提交当前输入（回车触发）。成功后不自动进入主页：
  /// 引擎转为已解锁态，按钮变金色高亮，等待人工点击 [VaultButton]。
  Future<void> _submitInput(UnlockEngine engine) async {
    final raw = _input.text;
    if (raw.trim().isEmpty || _busy || engine.isUnlocked) return;
    _input.clear();
    setState(() => _busy = true);
    try {
      final result = await engine.submit(raw);
      if (!mounted || !context.mounted) return;
      if (result.success) {
        _showMessage('打开成功');
      } else if (result.needsRepair) {
        // 份额多项式阶数 > 当前 K（存量库）：静默继续，不显示任何提示——
        // 盲输原则（3.4）禁止泄露命中信息；引擎会继续累积份额直到 MK 验证通过。
      } else if (result.failed) {
        _showMessage('打开失败');
      } else if (result.rejected) {
        _showMessage('冷却中');
      }
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) _showMessage('打开失败');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 人工点击高亮「解锁」按钮后进入主页。
  Future<void> _enterVault(UnlockEngine engine) async {
    if (_busy || _entering) return;
    setState(() => _entering = true);
    try {
      final app = context.read<AppState>();
      await app.unlockWith(
        engine.takeMk(),
        repairShares: engine.repairedShares,
        hitPasswords: engine.hitPasswords,
      );
    } catch (_) {
      if (mounted) _showMessage('打开失败');
    } finally {
      if (mounted) setState(() => _entering = false);
    }
  }

  String _formatCooldown(int ms) {
    final total = (ms / 1000).ceil();
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  void _syncTicker(UnlockEngine? engine) {
    final needTicker = engine != null && engine.inCooldown;
    if (needTicker && _ticker == null) {
      _ticker = Timer.periodic(AppDurations.cooldownTick, (_) {
        if (mounted) setState(() {});
      });
    } else if (!needTicker && _ticker != null) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  void _showMessage(String text) {
    showVaultBanner(context, text);
  }
}
