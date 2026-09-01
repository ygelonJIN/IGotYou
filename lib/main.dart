import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app_state.dart';
import 'theme/theme.dart';
import 'ui/unlock_screen.dart';
import 'ui/vault_screen.dart';
import 'ui/widgets/vault_lock_button.dart';

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
  final _navKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState()..init(),
      child: MaterialApp(
        title: 'IGotYou',
        debugShowCheckedModeBanner: false,
        navigatorKey: _navKey,
        // 全局上锁按钮：盖在所有页面（含遮罩）之上，位置恒定。
        builder: (context, child) => Stack(
          textDirection: TextDirection.ltr,
          children: [
            Positioned.fill(child: child ?? const SizedBox.shrink()),
            VaultLockButtonOverlay(navigatorKey: _navKey),
          ],
        ),
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