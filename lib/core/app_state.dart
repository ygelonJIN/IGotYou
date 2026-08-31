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
class AppState extends ChangeNotifier {
  String? _vaultPath;
  String? _statePath;
  bool _initialized = false;

  UnlockEngine? _engine;
  VaultSession? _session;

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
  Future<VaultSession> unlockWith(Uint8List mk) async {
    final data = await VaultFile.read(_vaultPath!);
    final session = await VaultSession.open(
      path: _vaultPath!,
      fileData: data,
      mk: mk,
    );
    _session = session;
    _engine = null;
    notifyListeners();
    return session;
  }

  /// 锁定：清空会话解密数据，重建解锁引擎（机会与冷却保留）。
  Future<void> lock() async {
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
