import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app_state.dart';
import 'theme/theme.dart';
import 'ui/unlock_screen.dart';
import 'ui/vault_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VaultApp());
}

class VaultApp extends StatefulWidget {
  const VaultApp({super.key});

  @override
  State<VaultApp> createState() => _VaultAppState();
}

class _VaultAppState extends State<VaultApp> {
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState()..init(),
      child: MaterialApp(
        title: 'IGotYou',
        debugShowCheckedModeBanner: false,
        theme: buildVaultTheme(),
        home: const RootGate(),
      ),
    );
  }
}

/// 根路由：根据 AppState 状态在 创建/解锁页 ⇄ 保险柜页 间切换。
class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (!app.isInitialized) {
      return const _Booting();
    }
    if (app.isUnlocked) {
      return const VaultScreen();
    }
    return UnlockScreen(
      showCreate: !app.hasVault,
      key: ValueKey(app.vaultPath),
    );
  }
}

class _Booting extends StatelessWidget {
  const _Booting();

  @override
  Widget build(BuildContext context) {
    // 启动初始化在 main 触发。
    return const Scaffold(
      body: SizedBox.shrink(),
    );
  }
}