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
/// - 解锁页：一个密码输入框 + 主按钮（按钮本身显示剩余机会 / 冷却）；
///   回车仅收一条密码（清空输入框等下一条），按按钮才真正校验。
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
  final _noteCtrl = TextEditingController();
  final _nameFocus = FocusNode();
  final _secretFocus = FocusNode();
  final _noteFocus = FocusNode();
  final List<String> _pending = [];
  bool _busy = false;
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    _input.dispose();
    _nameCtrl.dispose();
    _secretCtrl.dispose();
    _noteCtrl.dispose();
    _nameFocus.dispose();
    _secretFocus.dispose();
    _noteFocus.dispose();
    super.dispose();
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
        const SizedBox(height: AppSizes.gateGap),
        VaultField(
          controller: _secretCtrl,
          hint: '加密密钥',
          mono: true,
          obscure: true,
          icon: Icons.key_outlined,
          focusNode: _secretFocus,
          textInputAction: TextInputAction.next,
          onSubmitted: () => FocusScope.of(context).requestFocus(_noteFocus),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSizes.gateGap),
        VaultField(
          controller: _noteCtrl,
          hint: '内容（可选）',
          icon: Icons.notes,
          focusNode: _noteFocus,
          onSubmitted: () => FocusScope.of(context).unfocus(),
        ),
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
        note: _noteCtrl.text.trim(),
      );
    } catch (_) {
      _showMessage('创建失败');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── 盲输解锁表单 ──
  // 回车 = 收一条密码（不清机会、不校验），按钮 = 批量提交校验。

  Widget _buildUnlockForm(BuildContext context, UnlockEngine engine) {
    final inCooldown = engine.inCooldown;
    final cooldownMs = engine.state.remainingCooldownMs(DateTime.now());
    final inCooldownActive = inCooldown && cooldownMs > 0;

    final String buttonLabel;
    final bool buttonEnabled;
    final bool highlighted;
    if (inCooldownActive) {
      buttonLabel = '冷却 ${_formatCooldown(cooldownMs)}';
      buttonEnabled = false;
      highlighted = false;
    } else {
      final hasPending = _pending.isNotEmpty || _input.text.trim().isNotEmpty;
      buttonEnabled = !_busy && hasPending;
      // 可点击（有输入）时只显示"解锁"并高亮；不可点击时显示剩余机会数。
      highlighted = buttonEnabled;
      buttonLabel = buttonEnabled
          ? '解锁'
          : '解锁（剩余 ${engine.remainingChances} 次）';
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
          onSubmitted: _addPending,
        ),
        const SizedBox(height: AppSizes.gateGap),
        VaultButton(
          label: buttonLabel,
          height: AppSizes.heroButtonHeight,
          highlighted: highlighted,
          onPressed: buttonEnabled ? () => _submitPending(engine) : null,
        ),
      ],
    );
  }

  void _addPending() {
    final v = _input.text;
    if (v.trim().isEmpty) return;
    _pending.add(v);
    _input.clear();
    setState(() {});
  }

  Future<void> _submitPending(UnlockEngine engine) async {
    final batch = List<String>.of(_pending);
    final cur = _input.text;
    if (cur.trim().isNotEmpty) {
      batch.add(cur);
      _input.clear();
    }
    if (batch.isEmpty || _busy) return;
    // 本次提交前先把待提交队列视作已收，避免重复提交。
    _pending.clear();
    setState(() => _busy = true);
    try {
      for (final raw in batch) {
        final result = await engine.submit(raw);
        if (!mounted || !context.mounted) return;
        if (result.success) {
          _showMessage('打开成功');
          final app = context.read<AppState>();
          await app.unlockWith(engine.takeMk());
          return;
        }
        if (result.failed) {
          _showMessage('打开失败');
          break;
        }
        if (result.rejected) {
          _showMessage('冷却中');
          break;
        }
      }
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) _showMessage('打开失败');
    } finally {
      if (mounted) setState(() => _busy = false);
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
