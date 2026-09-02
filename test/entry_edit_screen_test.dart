import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:igotyou/core/crypto/aes_gcm.dart';
import 'package:igotyou/core/crypto/argon2.dart';
import 'package:igotyou/core/crypto/keychain.dart';
import 'package:igotyou/core/file/vault_file.dart';
import 'package:igotyou/core/models/entry.dart';
import 'package:igotyou/core/models/vault_config.dart';
import 'package:igotyou/core/vault_session.dart';
import 'package:igotyou/ui/entry_edit_screen.dart';
import 'package:igotyou/ui/widgets/vault_button.dart';

final Random _rnd = Random.secure();

Uint8List secBytes(int n) {
  final b = Uint8List(n);
  for (var i = 0; i < n; i++) {
    b[i] = _rnd.nextInt(256);
  }
  return b;
}

Argon2Deriver fastDeriver({Uint8List? salt}) => Argon2Deriver(
      memory: 64,
      iterations: 1,
      parallelism: 1,
      hashLength: 32,
      salt: salt ?? secBytes(16),
    );

Entry entry(int seed, String secret, {bool isKey = true}) => Entry(
      id: 'entry-$seed',
      name: '条目 $seed',
      secret: secret,
      note: '',
      isKey: isKey,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

/// 写入真实格式库文件，用低成本 Argon2，返回打开的会话。
Future<VaultSession> openSession(
  Directory dir, {
  required List<Entry> entries,
  required VaultConfig config,
}) async {
  final mk = Keychain.generateMk();
  final deriver = fastDeriver();
  final keyEntries = entries.where((e) => e.isKey).toList();
  final shares = await Keychain.splitSecret(
    mk: mk,
    keyEntries: keyEntries,
    threshold: config.hitCount,
    deriver: deriver,
  );
  final header = VaultHeader(
    version: vaultFileVersion,
    argonParams: deriver.params,
    salt: Uint8List.fromList(deriver.salt),
    config: config,
  );
  final bodyJson = jsonEncode({
    'entries': entries.map((e) => e.toJson()).toList(),
    'config': config.toJson(),
  });
  final body = await AesGcmCipher().encrypt(bodyJson, SecretKeyData(mk));
  final path = '${dir.path}/vault.igotyou';
  await VaultFile.write(
    path,
    header: header,
    shares: shares,
    body: body,
  );
  final data = await VaultFile.read(path);
  return VaultSession.open(path: path, fileData: data, mk: mk);
}

/// 推入查看页：主页放一个入口按钮，点它 push EntryEditScreen，
/// 使路由可 pop（测试返回语义的前提）。
Future<NavigatorState> pumpPushedEdit(
  WidgetTester tester,
  VaultSession session,
  Entry entry,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => EntryEditScreen(entry: entry, session: session),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return tester.state<NavigatorState>(find.byType(Navigator));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 收尾：把自动消失横幅的 2600ms Timer 走完，避免「pending timer」报错。
  Future<void> flushBanner(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 3000));
    await tester.pumpAndSettle();
  }

  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('entry_edit_screen_test');
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });

  group('二次加密门禁：两段式流程（DEVELOPMENT 9.7b）', () {
    testWidgets('输对密钥 → 回车 → 按钮高亮但不进入；点查看才进入', (
      WidgetTester tester,
    ) async {
      final session = await openSession(
        dir,
        entries: [entry(1, 'secret-a', isKey: true)],
        config: const VaultConfig.defaults().copyWith(hitCount: 1),
      );
      final e = session.entries.first;
      await session.setDoubleLock(e, 'double-key-1');
      await session.save();

      await tester.pumpWidget(
        MaterialApp(
          home: EntryEditScreen(entry: e, session: session),
        ),
      );
      await tester.pumpAndSettle();

      // 门禁页：密钥输入框 + 查看按钮（初始不高亮、不可点）。
      final field = find.byType(TextField).first;
      final button = find.byType(VaultButton).first;

      expect(tester.widget<VaultButton>(button).highlighted, isFalse);
      expect(tester.widget<VaultButton>(button).onPressed, isNull);
      // 仍在门禁页（编辑表单的名称框尚未出现）。
      expect(find.text('名称'), findsNothing);

      // 输入正确密钥并回车。
      await tester.enterText(field, 'double-key-1');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // 按钮变为高亮、可点，但仍停留在门禁页（未进入编辑表单）。
      expect(tester.widget<VaultButton>(button).highlighted, isTrue);
      expect(tester.widget<VaultButton>(button).onPressed, isNotNull);
      expect(find.text('名称'), findsNothing);

      // 点击高亮的「查看」按钮 → 进入编辑表单。
      await tester.tap(button);
      await tester.pumpAndSettle();

      // 已进入编辑表单：出现名称框提示与底部操作区（修改密钥按钮）。
      expect(find.text('名称'), findsOneWidget);
      expect(find.text('修改密钥'), findsOneWidget);
    });

    testWidgets('输错密钥 → 回车 → 横幅提示，按钮不高亮', (
      WidgetTester tester,
    ) async {
      final session = await openSession(
        dir,
        entries: [entry(1, 'secret-a', isKey: true)],
        config: const VaultConfig.defaults().copyWith(hitCount: 1),
      );
      final e = session.entries.first;
      await session.setDoubleLock(e, 'double-key-1');
      await session.save();

      await tester.pumpWidget(
        MaterialApp(
          home: EntryEditScreen(entry: e, session: session),
        ),
      );
      await tester.pumpAndSettle();

      final field = find.byType(TextField).first;
      final button = find.byType(VaultButton).first;

      await tester.enterText(field, 'wrong-key');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // 按钮仍不高亮、不可点；横幅提示。
      expect(tester.widget<VaultButton>(button).highlighted, isFalse);
      expect(tester.widget<VaultButton>(button).onPressed, isNull);
      expect(find.text('加密密钥不正确'), findsOneWidget);
      await flushBanner(tester);
    });

    testWidgets('输对后再改输入 → 高亮消失；再输对再回车 → 重新高亮', (
      WidgetTester tester,
    ) async {
      final session = await openSession(
        dir,
        entries: [entry(1, 'secret-a', isKey: true)],
        config: const VaultConfig.defaults().copyWith(hitCount: 1),
      );
      final e = session.entries.first;
      await session.setDoubleLock(e, 'double-key-1');
      await session.save();

      await tester.pumpWidget(
        MaterialApp(
          home: EntryEditScreen(entry: e, session: session),
        ),
      );
      await tester.pumpAndSettle();

      final field = find.byType(TextField).first;
      final button = find.byType(VaultButton).first;

      // 输对并回车 → 高亮。
      await tester.enterText(field, 'double-key-1');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(tester.widget<VaultButton>(button).highlighted, isTrue);

      // 再改输入 → 高亮消失。
      await tester.enterText(field, 'x');
      await tester.pumpAndSettle();
      expect(tester.widget<VaultButton>(button).highlighted, isFalse);

      // 再输对并回车 → 重新高亮。
      await tester.enterText(field, 'double-key-1');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(tester.widget<VaultButton>(button).highlighted, isTrue);
    });

    testWidgets('门禁页无改动 → canPop 为 true → 直接返回', (
      WidgetTester tester,
    ) async {
      final session = await openSession(
        dir,
        entries: [entry(1, 'secret-a', isKey: true)],
        config: const VaultConfig.defaults().copyWith(hitCount: 1),
      );
      final e = session.entries.first;
      await session.setDoubleLock(e, 'double-key-1');
      await session.save();

      final nav = await pumpPushedEdit(tester, session, e);
      expect(find.byType(EntryEditScreen), findsOneWidget);

      final popped = await nav.maybePop();
      await tester.pumpAndSettle();
      expect(popped, isTrue);
      expect(find.byType(EntryEditScreen), findsNothing);
    });
  });

  group('查看页：返回语义（DEVELOPMENT 9.7b）', () {
    testWidgets('无改动 → canPop 为 true → 直接返回', (
      WidgetTester tester,
    ) async {
      final session = await openSession(
        dir,
        entries: [entry(1, 'secret-a', isKey: true)],
        config: const VaultConfig.defaults().copyWith(hitCount: 1),
      );
      final e = session.entries.first;

      final nav = await pumpPushedEdit(tester, session, e);
      // 已进入编辑表单（非门禁）。
      expect(find.text('名称'), findsOneWidget);

      final popped = await nav.maybePop();
      await tester.pumpAndSettle();
      expect(popped, isTrue);
      expect(find.byType(EntryEditScreen), findsNothing);
    });

    testWidgets('有改动 → 返回先保存再退出（数据不丢）', (
      WidgetTester tester,
    ) async {
      final session = await openSession(
        dir,
        entries: [entry(1, 'secret-a', isKey: true)],
        config: const VaultConfig.defaults().copyWith(hitCount: 1),
      );
      final e = session.entries.first;

      final nav = await pumpPushedEdit(tester, session, e);

      // 修改名称字段（触发脏数据）。
      await tester.enterText(find.byType(TextField).first, '新名称');
      await tester.pumpAndSettle();

      // 脏数据下返回：应保存后退出。
      final popped = await nav.maybePop();
      await tester.pumpAndSettle();
      expect(popped, isFalse); // 本次 pop 被拦截（回显保存），随后程序化退出
      expect(find.byType(EntryEditScreen), findsNothing);
      // 改动已落盘到会话。
      expect(session.entryById(e.id)!.name, '新名称');
      await flushBanner(tester);
    });

    testWidgets('有改动 → 点返回箭头 → 保存并退出', (
      WidgetTester tester,
    ) async {
      final session = await openSession(
        dir,
        entries: [entry(1, 'secret-a', isKey: true)],
        config: const VaultConfig.defaults().copyWith(hitCount: 1),
      );
      final e = session.entries.first;

      await pumpPushedEdit(tester, session, e);

      await tester.enterText(find.byType(TextField).first, '新名称');
      await tester.pumpAndSettle();

      final backButton = find.byIcon(Icons.arrow_back_rounded);
      expect(backButton, findsOneWidget);
      await tester.tap(backButton);
      await tester.pumpAndSettle();

      expect(find.byType(EntryEditScreen), findsNothing);
      expect(session.entryById(e.id)!.name, '新名称');
      await flushBanner(tester);
    });
  });
}