import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/models/entry.dart';
import '../core/vault_session.dart';
import '../theme/tokens.dart';
import 'widgets/missing_key_prompt.dart';
import 'widgets/vault_banner.dart';
import 'widgets/vault_bottom_scrim.dart';
import 'widgets/vault_button.dart';
import 'widgets/vault_field.dart';
import 'widgets/vault_top_bar.dart';

/// 条目编辑页：全屏表单，仅顶部关闭按钮。
/// 名称/加密密钥/内容 三组字段铺满；内容支持多行（一行一框，末尾空框
/// 继续添加），各组之间以细分隔线区分。仅显式操作触发保存，保存期间
/// 弹出阻塞式「正在保存…」遮罩，避免慢速落盘（Argon2id 份额重切）时的误操作。
/// - 编辑：字段失去焦点自动保存；返回箭头保存并返回。
/// - 新建：回车顺序流转 名称→密钥→内容；内容回车仅收起键盘，
///   由保存按钮/返回箭头保存。
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
  late final FocusNode _nameFocus = FocusNode();
  late final FocusNode _secretFocus = FocusNode();

  /// 内容多行框：一行一个输入框，末尾始终保留一个空框用于继续添加。
  late final List<TextEditingController> _noteCtrls = [];
  late final List<FocusNode> _noteFoci = [];
  bool _dirty = false;
  bool _saving = false;
  bool _allowPop = false;
  String? _duplicateOf;

  /// 新建时已加入会话、尚未落盘的条目 id：重复检测需排除自身。
  String? _pendingCreateId;

  /// 新建落盘时因其他二次加密钥匙明文缺失而降级为普通条目。
  bool _createdAsNonKey = false;
  bool _unlocked = false;

  /// 正在进行的保存（供锁定/返回等待）。
  Future<void>? _inFlightSave;

  bool get _isEdit => widget.entry != null;

  @override
  void initState() {
    super.initState();
    _nameFocus.addListener(() => _onLostFocus(_nameFocus));
    _secretFocus.addListener(() => _onLostFocus(_secretFocus));
    _resetNoteBoxes(widget.entry?.note ?? '');
    // 全局上锁按钮锁定前：先落盘未保存的改动。
    context.read<AppState>().setBeforeLock(_flushSaves);
  }

  @override
  void dispose() {
    context.read<AppState>().setBeforeLock(null);
    _nameCtrl.dispose();
    _secretCtrl.dispose();
    _disposeNoteBoxes();
    _nameFocus.dispose();
    _secretFocus.dispose();
    super.dispose();
  }

  /// 把内容按行拆成多个输入框，末尾始终保留一个空框用于继续添加。
  void _resetNoteBoxes(String note) {
    _disposeNoteBoxes();
    for (final line in note.split('\n')) {
      if (line.trim().isEmpty) continue;
      _addNoteBox(line);
    }
    // 末尾空框：始终存在，用于输入新的一行内容。
    _addNoteBox('');
  }

  void _addNoteBox(String text) {
    final focus = FocusNode();
    focus.addListener(() => _onLostFocus(focus));
    _noteCtrls.add(TextEditingController(text: text));
    _noteFoci.add(focus);
  }

  void _disposeNoteBoxes() {
    for (final c in _noteCtrls) {
      c.dispose();
    }
    for (final f in _noteFoci) {
      f.dispose();
    }
    _noteCtrls.clear();
    _noteFoci.clear();
  }

  /// 内容框拼装回单行字符串（空行丢弃，行间以换行连接）。
  String get _noteText =>
      _noteCtrls.map((c) => c.text.trim()).where((s) => s.isNotEmpty).join('\n');

  /// 字段失去焦点即自动保存（仅编辑模式；新建由回车/关闭触发）。
  void _onLostFocus(FocusNode node) {
    if (!node.hasFocus && _dirty && _isEdit && !_saving) {
      _inFlightSave = _save();
    }
  }

  void _markDirty() => setState(() => _dirty = true);

  // ── 保存 / 创建 ──

  /// 从会话取当前条目（二次加密开/关会替换条目对象，widget.entry 会过期）。
  Entry _liveEntry(VaultSession session) =>
      session.entryById(widget.entry!.id) ?? widget.entry!;

  Future<bool> _save() async {
    if (_saving) return false;
    _saving = true;
    try {
      final session = widget.session;
      final entry = _liveEntry(session);
      if (entry.doubleLocked) {
        // 二次加密条目：正文用会话缓存密钥重新加密（门禁已缓存）。
        await session.updateDoubleEntry(
          entry,
          name: _nameCtrl.text.trim(),
          secret: _secretCtrl.text.trim(),
          note: _noteText,
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
            return false;
          }
        }
        session.updateEntry(
          entry,
          name: _nameCtrl.text.trim(),
          secret: newSecret,
          note: _noteText,
        );
      }
      if (!await _saveWithMissingKeys()) {
        // 用户放弃补齐缺失的钥匙密钥：改动未落盘，提示并保持页面。
        if (mounted) showVaultBanner(context, '保存失败');
        return false;
      }
      if (mounted) setState(() => _dirty = false);
      return true;
    } catch (_) {
      if (mounted) showVaultBanner(context, '保存失败');
      return false;
    } finally {
      _saving = false;
    }
  }

  /// 二次加密门禁：输入条目的加密密钥后才能查看内容。
  Widget _buildGate(BuildContext context, double topInset) {
    final ctrl = TextEditingController();
    // 底部留白：与主页一致（contentBottomInset）。
    final bottomInset = AppSizes.contentBottomInset;
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
    final entry = _liveEntry(widget.session);
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
      _resetNoteBoxes(note);
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
    final entry = _liveEntry(session);
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
    final entry = _liveEntry(session);
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
      await session.changeDoubleKey(_liveEntry(session), old, next);
      await session.save();
      if (!mounted) return;
      showVaultBanner(context, '密钥已修改');
      setState(() {});
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
      await session.clearDoubleLock(_liveEntry(session), key);
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
      // 名称为空 = 取消创建：直接返回，不建空条目。
      if (!mounted) return;
      setState(() => _allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return;
    }
    if (_saving) return;
    _saving = true;
    // 收起键盘，避免保存遮罩下残留输入法。
    FocusManager.instance.primaryFocus?.unfocus();
    Entry? created;
    try {
      final sharesDirtyBefore = widget.session.sharesDirty;
      created = widget.session.addEntry(
        name: _nameCtrl.text.trim(),
        secret: _secretCtrl.text.trim(),
        note: _noteText,
        isKey: true,
      );
      _pendingCreateId = created.id;
      var saved = false;
      var degraded = false;
      await _withSavingIndicator(() async {
        saved = await _persistCreate(sharesDirtyBefore);
        degraded = _createdAsNonKey;
      });
      if (!saved) {
        // 意外落盘失败：回滚幽灵条目并返回列表页。
        _abortCreate(created);
        return;
      }
      if (mounted) {
        setState(() => _allowPop = true);
        showVaultBanner(
          context,
          degraded ? '已保存为普通条目（需要时可在列表开启钥匙）' : '已保存',
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop();
        });
      }
    } on VaultKeyMissingException catch (e) {
      // 保险柜处于待重切状态（如先前改密未落盘）且缺该钥匙明文：
      // 本次创建无法落盘，回滚并说明原因。
      if (mounted) showVaultBanner(context, '创建失败：$e');
      _abortCreate(created);
    } catch (_) {
      // 落盘失败：回滚已加入内存的条目。否则幽灵条目会残留——重复检测
      // 会把新建条目误判成"与自身相同"，且每次返回都是重试创建，再也出不去。
      if (mounted) showVaultBanner(context, '创建失败');
      _abortCreate(created);
    } finally {
      _saving = false;
      _pendingCreateId = null;
    }
  }

  /// 保存期间弹出阻塞式「正在保存…」遮罩，防止用户在慢速落盘
  /// （Argon2id 份额重切）中重复操作或误以为卡死。
  Future<void> _withSavingIndicator(Future<void> Function() action) async {
    if (!mounted) return;
    final nav = Navigator.of(context, rootNavigator: true);
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const PopScope(canPop: false, child: _SavingDialog()),
      ),
    );
    try {
      await action();
    } finally {
      // 关闭保存遮罩。若上层还有弹窗（如缺失钥匙输入框），
      // 其关闭后此处 pop 的必是保存遮罩本身。
      if (nav.canPop()) nav.pop();
    }
  }

  /// 新建落盘：优先按钥匙保存；若因其他二次加密钥匙明文缺失而无法重切份额，
  /// 自动降级为普通条目保存（新建不应索要其他条目的密码）。
  /// 返回 true 表示已成功落盘（降级与否见 [_createdAsNonKey]）。
  Future<bool> _persistCreate(bool sharesDirtyBefore) async {
    _createdAsNonKey = false;
    try {
      await widget.session.save();
      return true;
    } on VaultKeyMissingException {
      // 降级：条目保留但不再是钥匙，份额状态恢复到加入前，保存不再重切。
      final id = _pendingCreateId;
      if (id == null) return false;
      widget.session.downgradeToNonKey(id, sharesDirty: sharesDirtyBefore);
      _createdAsNonKey = true;
      await widget.session.save();
      return true;
    }
  }

  /// 落盘：二次加密钥匙明文密钥缺失时弹窗输入后重试（最多 8 轮）。
  /// 返回 true 表示已成功落盘；false 表示用户放弃（未落盘）。
  Future<bool> _saveWithMissingKeys() async {
    for (var attempt = 0; attempt < 8; attempt++) {
      try {
        await widget.session.save();
        return true;
      } on VaultKeyMissingException catch (e) {
        if (!mounted) return false;
        final ok =
            await promptMissingDoubleKey(context, widget.session, e.entryName);
        if (!ok || !mounted) return false;
      }
    }
    return false;
  }

  /// 创建失败收尾：回滚已加入内存的条目（幽灵），并允许返回列表页。
  void _abortCreate(Entry? created) {
    if (created != null) {
      widget.session.entries.removeWhere((e) => e.id == created.id);
    }
    if (!mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  /// 等待未完成的保存；还有改动则再保存一次（锁定前调用，带保存遮罩）。
  Future<void> _flushSaves() async {
    if (_inFlightSave != null) {
      await _inFlightSave;
      _inFlightSave = null;
    }
    if (_dirty && !_saving && _isEdit) {
      await _withSavingIndicator(_save);
    }
  }

  Future<void> _handleClose() async {
    if (_isEdit) {
      // 若字段失焦自动保存还在进行，先等它结束再决定是否再存。
      if (_inFlightSave != null) {
        await _inFlightSave;
        _inFlightSave = null;
      }
      if (_dirty) {
        await _withSavingIndicator(_save);
        if (!mounted) return;
        if (_dirty) {
          // 保存未成功（_save 已横幅提示）：留在页面，让用户处理后重试。
          return;
        }
        showVaultBanner(context, '已保存');
      }
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    } else {
      await _createAndClose();
    }
  }

  // ── 回车流转 ──
  // 回车只负责移动光标：名称→密钥→内容。内容框回车统一收起键盘
  // （不跳下一框、不自动保存），保存由按钮/返回箭头完成。

  void _onNameSubmitted() {
    FocusScope.of(context).requestFocus(_secretFocus);
  }

  void _onSecretSubmitted() {
    if (_noteFoci.isNotEmpty) {
      FocusScope.of(context).requestFocus(_noteFoci.first);
    }
  }

  void _onNoteSubmitted(int index) {
    // 内容框回车：统一收起键盘，不跳转下一框、不自动保存。
    FocusScope.of(context).unfocus();
  }

  /// 内容框内容变化：末尾框出现内容时追加一个空框；
  /// 其余框清空后删除（保持末尾始终只有一个空框）。
  void _onNoteChanged(int index) {
    final text = _noteCtrls[index].text;
    if (index == _noteCtrls.length - 1) {
      // 末尾框从空变非空：追加新空框继续输入。
      if (text.trim().isNotEmpty) {
        setState(() => _addNoteBox(''));
        _markDirty();
      }
    } else if (text.trim().isEmpty) {
      // 中间框被清空：删除该框，焦点落到原下一框（顶替上来）。
      final next = _noteFoci[index + 1];
      setState(() {
        _noteCtrls.removeAt(index).dispose();
        _noteFoci.removeAt(index).dispose();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        next.requestFocus();
      });
      _markDirty();
    } else {
      _markDirty();
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
      exceptId: _isEdit ? widget.entry?.id : _pendingCreateId,
    );
    _duplicateOf = dup?.name;
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    _refreshDuplicate(session);
    final mq = MediaQuery.of(context);
    final topInset = VaultTopBar.totalHeight(mq);
    // 底部留白：与主页一致（contentBottomInset）。
    final bottomInset = AppSizes.contentBottomInset;

    // 二次加密门禁：仅二次加密条目需输入密钥；普通条目直接查看。
    final needsGate =
        _isEdit && _liveEntry(session).doubleLocked && !_unlocked;
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
                                const VaultFieldDivider(),
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
                                const VaultFieldDivider(),
                                // 内容多行框：一行一框，末尾空框用于继续添加。
                                for (var i = 0;
                                    i < _noteCtrls.length;
                                    i++) ...[
                                  if (i > 0)
                                    const SizedBox(height: AppSpacing.unit2),
                                  VaultField(
                                    controller: _noteCtrls[i],
                                    hint: i == _noteCtrls.length - 1
                                        ? '新增内容条目'
                                        : '内容',
                                    focusNode: _noteFoci[i],
                                    textInputAction: TextInputAction.done,
                                    onSubmitted: () => _onNoteSubmitted(i),
                                    onChanged: (_) => _onNoteChanged(i),
                                  ),
                                ],
                                if (!_isEdit) ...[
                                  const SizedBox(height: AppSpacing.unit6),
                                  // 显式保存按钮（内容回车仅收起键盘，不保存）。
                                  VaultButton(
                                    label: '保存',
                                    onPressed: _createAndClose,
                                  ),
                                ],
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
    if (confirm != true || !mounted) return;
    await _flushSaves();
    if (!mounted) return;
    final entry = widget.entry!;
    final sharesDirtyBefore = session.sharesDirty;
    var deleted = false;
    try {
      await _withSavingIndicator(() async {
        final adjustedK = session.deleteEntry(entry.id);
        var saved = false;
        // 落盘；二次加密钥匙明文缺失时引导输入后重试（最多 8 轮）。
        for (var attempt = 0; attempt < 8; attempt++) {
          try {
            await session.save();
            saved = true;
            break;
          } on VaultKeyMissingException catch (e) {
            if (!mounted) break;
            final ok =
                await promptMissingDoubleKey(context, session, e.entryName);
            if (!ok || !mounted) break;
          }
        }
        if (!saved) {
          // 落盘失败：回滚内存删除，界面保持原状。
          session.restoreEntry(entry, sharesDirty: sharesDirtyBefore);
          return;
        }
        deleted = true;
        if (adjustedK != null && mounted) {
          showVaultBanner(context, '钥匙数减少，命中数已调整为 $adjustedK');
        }
      });
    } on StateError catch (e) {
      // 最后一把钥匙等守卫：条目未被删除，仅提示。
      if (mounted) showVaultBanner(context, e.message);
      return;
    }
    if (!deleted) {
      if (mounted) showVaultBanner(context, '删除失败');
      return;
    }
    if (!mounted) return;
    showVaultBanner(context, '已删除');
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }
}

/// 保存中阻塞遮罩：盖住整个页面，防止保存期间重复操作。
class _SavingDialog extends StatelessWidget {
  const _SavingDialog();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.unit6),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.unit4,
            vertical: AppSpacing.unit4,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.all(Radius.circular(AppRadius.gate)),
            border: Border.all(color: AppColors.goldDim, width: AppBorder.width),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: AppColors.gold,
                ),
              ),
              const SizedBox(width: AppSpacing.unit4),
              Flexible(
                child: Text('正在保存…', style: AppTextStyles.body),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
