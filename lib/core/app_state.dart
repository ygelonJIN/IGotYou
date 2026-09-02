import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'file/vault_file.dart';
import 'unlock/unlock_engine.dart';
import 'vault_session.dart';

/// 应用顶层状态（provider 注入）。
///
/// 职责：库文件/尝试状态文件的路径管理、解锁引擎与会话生命周期、
/// 创建保险柜、打开成功进入会话、锁定清空。
///
/// [beforeLock] 由当前页面注册：锁定前等待未落盘的自动保存
/// （全局上锁按钮触发锁定前调用，避免焦点内改动丢失）。
class AppState extends ChangeNotifier {
  String? _vaultPath;
  String? _statePath;
  bool _initialized = false;

  UnlockEngine? _engine;
  VaultSession? _session;

  /// 设置侧栏是否展开：展开期间全局上锁按钮隐藏，
  /// 改由设置栏内右上角渲染同款按钮（见 settings_panel）。
  bool _settingsOpen = false;

  bool get settingsOpen => _settingsOpen;

  void setSettingsOpen(bool open) {
    if (_settingsOpen == open) return;
    _settingsOpen = open;
    notifyListeners();
  }

  /// 锁定前回调：当前页面注册（编辑页/设置页），返回前会等待保存完成。
  Future<void> Function()? beforeLock;

  /// 注册/清除锁定前回调（页面挂载时注册、销毁时清除）。
  void setBeforeLock(Future<void> Function()? fn) {
    beforeLock = fn;
  }

  /// 应用文档目录（path_provider），初始化时解析一次。
  Future<Directory> _appDir() => getApplicationDocumentsDirectory();

  bool get isInitialized => _initialized;

  /// 是否存在库文件（决定首启展示创建页还是解锁页）。
  bool get hasVault => _vaultPath != null && File(_vaultPath!).existsSync();

  /// 是否已解锁进入保险柜。
  bool get isUnlocked => _session != null;

  VaultSession? get session => _session;

  /// 解锁引擎（未解锁时有值）。
  UnlockEngine? get engine => _engine;

  String get vaultPath => _vaultPath!;
  String get statePath => _statePath!;

  /// 启动初始化：解析路径、读库文件与尝试状态，未解锁时构建引擎。
  Future<void> init() async {
    if (_initialized) return;
    final dir = await _appDir();
    _vaultPath = '${dir.path}/vault.igotyou';
    _statePath = '${dir.path}/attempt_state.json';
    _initialized = true;
    if (hasVault) {
      await _prepareEngine();
    }
    notifyListeners();
  }

  Future<void> _prepareEngine() async {
    final data = await VaultFile.read(_vaultPath!);
    final engine = UnlockEngine(data: data, statePath: _statePath!);
    await engine.loadState();
    _engine = engine;
  }

  /// 首次创建保险柜（DEVELOPMENT 8.1）：直接建库并进入会话。
  Future<void> createVault({
    required String name,
    required String secret,
    String note = '',
  }) async {
    final session = await VaultSession.create(
      path: _vaultPath!,
      name: name,
      secret: secret,
      note: note,
    );
    _session = session;
    _engine = null;
    notifyListeners();
  }

  /// 盲输提交（转发给解锁引擎）。
  Future<UnlockSubmitResult> submit(String value) => _engine!.submit(value);

  /// 打开成功：用重构出的 MK 打开会话，清空引擎内存。
  /// [repairShares] 为 true 表示本次经存量库修复路径打开（命中数 > K）：
  /// 会话自动缓存本轮命中口令、标记重切，并立即尽力重切落盘——份额与
  /// 当前 K 从此一致，下次解锁按设置即可（17.18/17.20）。
  Future<VaultSession> unlockWith(
    Uint8List mk, {
    bool repairShares = false,
    Map<String, String> hitPasswords = const {},
  }) async {
    final data = await VaultFile.read(_vaultPath!);
    final session = await VaultSession.open(
      path: _vaultPath!,
      fileData: data,
      mk: mk,
    );
    if (repairShares) {
      await session.seedDoubleKeys(hitPasswords);
      session.markSharesForResplit();
      try {
        await session.save(); // 全量重切（K 份份额）+ 落盘，一次性修复
      } on VaultKeyMissingException {
        // 仍有二次加密钥匙明文缺失：保持标记，进库后任意一次保存会补齐
        //（settings/entry 保存的缺口令弹窗流程，17.19）。
      }
    }
    _session = session;
    _engine = null;
    notifyListeners();
    return session;
  }

  /// 锁定：清空会话解密数据，重建解锁引擎（机会与冷却保留）。
  Future<void> lock() async {
    _settingsOpen = false;
    _session?.lock();
    _session = null;
    if (hasVault) {
      await _prepareEngine();
    }
    notifyListeners();
  }

  /// 导入备份：用外部 .igotyou 替换当前库文件（DEVELOPMENT 8.7）。
  /// 成功后重建引擎，等待盲输解锁。
  Future<void> importVault(File source) async {
    // 校验 magic/版本（抛异常即文件损坏）。
    await VaultFile.read(source.path);
    if (source.path != _vaultPath) {
      await source.copy(_vaultPath!);
    }
    _session = null;
    await _prepareEngine();
    notifyListeners();
  }

  /// 清空保险柜（DEVELOPMENT 8.6）：删除库文件与尝试状态文件，
  /// 清空内存，回到首次创建状态。需 UI 侧确认后调用。
  Future<void> clearVault() async {
    _session?.lock();
    _session = null;
    _engine = null;
    for (final p in [_vaultPath, _statePath]) {
      if (p != null) {
        final f = File(p);
        if (await f.exists()) await f.delete();
      }
    }
    notifyListeners();
  }
}
