import 'package:flutter/material.dart';

import '../core/models/entry.dart';
import '../core/vault_session.dart';
import '../theme/tokens.dart';
import 'widgets/vault_banner.dart';
import 'widgets/vault_bottom_scrim.dart';
import 'widgets/vault_button.dart';
import 'widgets/vault_field.dart';
import 'widgets/vault_top_bar.dart';

/// 条目编辑页：全屏表单，仅顶部关闭按钮。
/// 名称/加密内容/内容 三字段铺满；失去焦点自动保存（无保存按钮）。
/// - 编辑：字段失去焦点即自动保存。
/// - 新建：名称回车即创建并关闭，其余字段可留空后补。
/// [entry] 为 null 时表示新建。[session] 必传以避免 provider 依赖。
class EntryEditScreen extends StatefulWidget {
  final Entry? entry;
  final VaultSession session;

  const EntryEditScreen({super.key, this.entry, required this.session});

  @override
  State<EntryEditScreen> createState() => _EntryEditScreenState();
}

class _EntryEditScreenState extends State<EntryEditScreen> {
  late final TextEditingController _nameCtrl = TextEditingController(
    text: widget.entry?.name,
  );
  late final TextEditingController _secretCtrl = TextEditingController(
    text: widget.entry?.secret,
  );
  late final TextEditingController _noteCtrl = TextEditingController(
    text: widget.entry?.note,
  );
  late final FocusNode _nameFocus = FocusNode();
  late final FocusNode _secretFocus = FocusNode();
  late final FocusNode _noteFocus = FocusNode();
  bool _dirty = false;
  bool _saving = false;
  bool _allowPop = false;
  String? _duplicateOf;
  bool _unlocked = false;

  /// 正在进行的保存（供锁定/返回等待）。
  Future<void>? _inFlightSave;

  bool get _isEdit => widget.entry != null;

  @override
  void initState() {
    super.initState();
    _nameFocus.addListener(() => _onLostFocus(_nameFocus));
    _secretFocus.addListener(() => _onLostFocus(_secretFocus));
    _noteFocus.addListener(() => _onLostFocus(_noteFocus));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _secretCtrl.dispose();
    _noteCtrl.dispose();
    _nameFocus.dispose();
    _secretFocus.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  /// 字段失去焦点即自动保存（仅编辑模式；新建由回车/关闭触发）。
  void _onLostFocus(FocusNode node) {
    if (!node.hasFocus && _dirty && _isEdit && !_saving) {
      _inFlightSave = _save();
    }
  }

  void _markDirty() => setState(() => _dirty = true);

  // ── 保存 / 创建 ──

  Future<void> _save() async {
    if (_saving) return;
    _saving = true;
    try {
      final session = widget.session;
      final entry = widget.entry!;
      if (entry.doubleLocked) {
        // 二次加密条目：正文用会话缓存密钥重新加密（门禁已缓存）。
        await session.updateDoubleEntry(
          entry,
          name: _nameCtrl.text.trim(),
          secret: _secretCtrl.text.trim(),
          note: _noteCtrl.text.trim(),
        );
      } else {
        // 修改钥匙条目的加密密钥 = 更换解锁口令，旧口令立即失效。
        // 必须先用旧口令验证，防止误改后把自己锁死。
        final newSecret = _secretCtrl.text.trim();
        if (entry.isKey && newSecret.isNotEmpty && newSecret != entry.secret) {
          final ok = await _confirmKeyChange(entry);
          if (!ok) {
            if (mounted) {
              // 用户取消：回填旧值，避免继续保存。
              _secretCtrl.text = entry.secret;
              setState(() => _dirty = false);
            }
            return;
          }
        }
        session.updateEntry(
          entry,
          name: _nameCtrl.text.trim(),
          secret: newSecret,
          note: _noteCtrl.text.trim(),
        );
      }
      await session.save();
      if (mounted) setState(() => _dirty = false);
    } catch (_) {
      if (mounted) showVaultBanner(context, '保存失败');
    } finally {
      _saving = false;
    }
  }

  /// 二次加密门禁：输入条目的加密密钥后才能查看内容。
  Widget _buildGate(BuildContext context, double topInset) {
    final ctrl = TextEditingController();
    // 底部遮罩区高度：与顶部渐变区对称（VaultBottomScrim.height = bottom + bottomMaskHeight）。
    final bottomInset = VaultBottomScrim.height(MediaQuery.of(context));
    return Scaffold(
      body: PopScope(
        canPop: true,
        child: Stack(
          children: [
            // 门禁表单（居中窄列，垂直居中）
            Positioned.fill(
              child: SafeArea(
                top: false,
                child: LayoutBuilder(
                  builder: (context, viewport) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: viewport.maxHeight,
                      ),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          AppSpacing.unit6,
                          topInset,
                          AppSpacing.unit6,
                          bottomInset,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: AppSizes.gateMaxWidth,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                VaultField(
                                  controller: ctrl,
                                  hint: '加密密钥',
                                  mono: true,
                                  obscure: true,
                                  icon: Icons.lock_outline,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: () => _tryUnlock(ctrl),
                                ),
                                const SizedBox(height: AppSizes.gateGap),
                                VaultButton(
                                  label: '查看',
                                  height: AppSizes.heroButtonHeight,
                                  onPressed: () => _tryUnlock(ctrl),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // 顶部覆盖栏（门禁：返回箭头即可退出，无表单内容需保存）
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: VaultTopBar(
                title: '查看',
                onBack: _handleClose,
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

  Future<void> _tryUnlock(TextEditingController ctrl) async {
    final entry = widget.entry!;
    if (ctrl.text.trim().isEmpty) return;
    try {
      final (secret, note) = await widget.session.unlockDoubleLock(
        entry,
        ctrl.text.trim(),
      );
      if (!mounted) return;
      ctrl.dispose();
      // 门禁通过：用明文填充表单（secret 需去掉 trim 副作用，保留原文）。
      _secretCtrl.text = secret;
      _noteCtrl.text = note;
      setState(() => _unlocked = true);
    } on StateError {
      if (mounted) showVaultBanner(context, '加密密钥不正确');
    }
  }

  /// 钥匙口令修改确认：输入旧口令验证 + 警告旧口令将失效。
  /// 返回 true 表示允许保存新口令。
  Future<bool> _confirmKeyChange(Entry entry) async {
    final ctrl = TextEditingController();
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '正在修改这把钥匙的加密密钥。修改后旧密钥立即失效，必须用新密钥解锁。请先输入当前密钥确认。',
              style: AppTextStyles.body,
            ),
            const SizedBox(height: AppSpacing.unit4),
            VaultField(
              controller: ctrl,
              hint: '当前密钥',
              mono: true,
              obscure: true,
              onSubmitted: () => Navigator.of(ctx).pop(true),
            ),
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
    final input = ctrl.text.trim();
    ctrl.dispose();
    if (proceed != true) return false;
    if (!mounted) return false;
    if (input.isEmpty || input != entry.secret) {
      showVaultBanner(context, '当前密钥不正确');
      return false;
    }
    return true;
  }

  /// 二次加密管理区：未开启 → "开启二次加密"；已开启 → 状态 + 修改/关闭。
  Widget _buildDoubleLockSection(VaultSession session) {
    final entry = widget.entry!;
    if (!entry.doubleLocked) {
      return VaultButton(
        label: '开启二次加密',
        onPressed: () => _promptEnableDoubleLock(session),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('已开启二次加密：查看需输入密钥', style: AppTextStyles.metaDim),
        const SizedBox(height: AppSpacing.unit3),
        VaultButton(
          label: '修改密钥',
          onPressed: () => _promptChangeDoubleKey(session),
        ),
        const SizedBox(height: AppSpacing.unit2),
        VaultDangerButton(
          label: '关闭二次加密',
          onPressed: () => _promptDisableDoubleLock(session),
        ),
      ],
    );
  }

  Future<void> _promptEnableDoubleLock(VaultSession session) async {
    final entry = widget.entry!;
    // 直接用条目原本的加密密钥，无需重新输入（DEVELOPMENT 8.4）。
    final key = entry.secret;
    if (key.trim().isEmpty) {
      if (mounted) showVaultBanner(context, '请先设置加密密钥');
      return;
    }
    if (!mounted) return;
    try {
      await session.setDoubleLock(entry, key);
      await session.save();
      if (!mounted) return;
      showVaultBanner(context, '二次加密已开启');
      setState(() {});
    } on VaultKeyMissingException catch (e) {
      if (mounted) showVaultBanner(context, '$e');
    } catch (_) {
      if (mounted) showVaultBanner(context, '开启失败');
    }
  }

  Future<void> _promptChangeDoubleKey(VaultSession session) async {
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '修改二次加密密钥：需先输入当前密钥。',
              style: AppTextStyles.body,
            ),
            const SizedBox(height: AppSpacing.unit4),
            VaultField(
              controller: oldCtrl,
              hint: '当前密钥',
              mono: true,
              obscure: true,
              onSubmitted: () => FocusScope.of(ctx).nextFocus(),
            ),
            const SizedBox(height: AppSpacing.unit2),
            VaultField(
              controller: newCtrl,
              hint: '新密钥',
              mono: true,
              obscure: true,
              onSubmitted: () => FocusScope.of(ctx).nextFocus(),
            ),
            const SizedBox(height: AppSpacing.unit2),
            VaultField(
              controller: confirmCtrl,
              hint: '再次输入',
              mono: true,
              obscure: true,
              onSubmitted: () => Navigator.of(ctx).pop(true),
            ),
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
    final old = oldCtrl.text.trim();
    final next = newCtrl.text.trim();
    final confirm = confirmCtrl.text.trim();
    oldCtrl.dispose();
    newCtrl.dispose();
    confirmCtrl.dispose();
    if (ok != true || old.isEmpty || next.isEmpty) return;
    if (next != confirm) {
      if (mounted) showVaultBanner(context, '两次输入不一致');
      return;
    }
    if (!mounted) return;
    try {
      await session.changeDoubleKey(widget.entry!, old, next);
      await session.save();
      if (!mounted) return;
      showVaultBanner(context, '密钥已修改');
    } on StateError catch (e) {
      if (mounted) showVaultBanner(context, e.message);
    } on VaultKeyMissingException catch (e) {
      if (mounted) showVaultBanner(context, '$e');
    } catch (_) {
      if (mounted) showVaultBanner(context, '修改失败');
    }
  }

  Future<void> _promptDisableDoubleLock(VaultSession session) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '关闭二次加密：内容将恢复为明文保存。请输入当前密钥确认。',
              style: AppTextStyles.body,
            ),
            const SizedBox(height: AppSpacing.unit4),
            VaultField(
              controller: ctrl,
              hint: '当前密钥',
              mono: true,
              obscure: true,
              onSubmitted: () => Navigator.of(ctx).pop(true),
            ),
          ],
        ),
        actions: [
          VaultTextButton(
            label: '取消',
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          VaultTextButton(
            label: '关闭',
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    final key = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true || key.isEmpty) return;
    if (!mounted) return;
    try {
      await session.clearDoubleLock(widget.entry!, key);
      await session.save();
      if (!mounted) return;
      showVaultBanner(context, '二次加密已关闭');
      setState(() {});
    } on StateError catch (e) {
      if (mounted) showVaultBanner(context, e.message);
    } on VaultKeyMissingException catch (e) {
      if (mounted) showVaultBanner(context, '$e');
    } catch (_) {
      if (mounted) showVaultBanner(context, '关闭失败');
    }
  }

  Future<void> _createAndClose() async {
    if (_nameCtrl.text.trim().isEmpty) {
      if (!mounted) return;
      setState(() => _allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return;
    }
    if (_saving) return;
    _saving = true;
    try {
      widget.session.addEntry(
        name: _nameCtrl.text.trim(),
        secret: _secretCtrl.text.trim(),
        note: _noteCtrl.text.trim(),
        isKey: true,
      );
      await widget.session.save();
      if (mounted) {
        setState(() => _allowPop = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop();
        });
      }
    } catch (_) {
      if (mounted) showVaultBanner(context, '创建失败');
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
    if (_dirty && !_saving && _isEdit) {
      _inFlightSave = _save();
      await _inFlightSave;
      _inFlightSave = null;
    }
  }

  Future<void> _handleClose() async {
    if (_isEdit) {
      if (_dirty) await _save();
      if (!mounted) return;
      setState(() => _allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    } else {
      await _createAndClose();
    }
  }

  // ── 回车流转 ──
  // 新建：名称回车即创建（其余可留空后补）；编辑：焦点流转 + 失去焦点保存。

  void _onNameSubmitted() {
    if (!_isEdit) {
      _createAndClose();
    } else {
      FocusScope.of(context).requestFocus(_secretFocus);
    }
  }

  void _onSecretSubmitted() {
    FocusScope.of(context).requestFocus(_noteFocus);
  }

  void _onNoteSubmitted() {
    if (!_isEdit) {
      _createAndClose();
    } else {
      FocusScope.of(context).unfocus();
    }
  }

  // ── 重复检测 ──

  void _refreshDuplicate(VaultSession session) {
    if (_secretCtrl.text.trim().isEmpty) {
      _duplicateOf = null;
      return;
    }
    final dup = session.findDuplicateSecret(
      _secretCtrl.text.trim(),
      exceptId: widget.entry?.id,
    );
    _duplicateOf = dup?.name;
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    _refreshDuplicate(session);
    final mq = MediaQuery.of(context);
    final topInset = VaultTopBar.totalHeight(mq);
    // 底部遮罩区高度：与顶部渐变区对称（VaultBottomScrim.height = bottom + bottomMaskHeight）。
    final bottomInset = VaultBottomScrim.height(mq);

    // 二次加密门禁：仅二次加密条目需输入密钥；普通条目直接查看。
    final needsGate = _isEdit && widget.entry!.doubleLocked && !_unlocked;
    if (needsGate) {
      return _buildGate(context, topInset);
    }

    return Scaffold(
      body: PopScope(
        canPop: _allowPop,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          _handleClose();
        },
        child: Stack(
          children: [
            // 全屏编辑表单（居中窄列，与首次创建页三列一致）
            Positioned.fill(
              child: SafeArea(
                top: false,
                child: LayoutBuilder(
                  builder: (context, viewport) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: viewport.maxHeight,
                      ),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          AppSpacing.unit6,
                          topInset,
                          AppSpacing.unit6,
                          bottomInset,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: AppSizes.gateMaxWidth,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                VaultField(
                                  controller: _nameCtrl,
                                  hint: '名称',
                                  focusNode: _nameFocus,
                                  textInputAction: TextInputAction.next,
                                  onSubmitted: _onNameSubmitted,
                                  onChanged: (_) => _markDirty(),
                                ),
                                const SizedBox(height: AppSpacing.unit2),
                                VaultField(
                                  controller: _secretCtrl,
                                  hint: '加密密钥',
                                  mono: true,
                                  focusNode: _secretFocus,
                                  textInputAction: TextInputAction.next,
                                  onSubmitted: _onSecretSubmitted,
                                  onChanged: (_) {
                                    _markDirty();
                                    setState(() {});
                                  },
                                ),
                                if (_duplicateOf != null) ...[
                                  const SizedBox(height: AppSpacing.unit2),
                                  Text(
                                    '与条目【$_duplicateOf】相同',
                                    style: AppTextStyles.metaDim,
                                  ),
                                ],
                                const SizedBox(height: AppSpacing.unit2),
                                VaultField(
                                  controller: _noteCtrl,
                                  hint: '内容',
                                  maxLines: null,
                                  focusNode: _noteFocus,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: _onNoteSubmitted,
                                  onChanged: (_) => _markDirty(),
                                ),
                                if (_isEdit) ...[
                                  const SizedBox(height: AppSpacing.unit6),
                                  _buildDoubleLockSection(session),
                                  const SizedBox(height: AppSpacing.unit6),
                                  VaultDangerButton(
                                    label: '删除',
                                    onPressed: () => _confirmDelete(session),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // 顶部覆盖栏（查看/添加：返回箭头退出）
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: VaultTopBar(
                title: _isEdit ? '查看' : '添加',
                onBack: _handleClose,
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

  Future<void> _confirmDelete(VaultSession session) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: const Text('删除后不可恢复，确认？', style: AppTextStyles.body),
        actions: [
          VaultTextButton(
            label: '取消',
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          VaultTextButton(
            label: '删除',
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _flushSaves();
      if (!mounted) return;
      try {
        final adjustedK = session.deleteEntry(widget.entry!.id);
        await session.save();
        if (mounted) {
          if (adjustedK != null) {
            showVaultBanner(context, '钥匙数减少，命中数已调整为 $adjustedK');
          }
          setState(() => _allowPop = true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.of(context).pop();
          });
        }
      } on StateError catch (e) {
        if (mounted) showVaultBanner(context, e.message);
      }
    }
  }
}
