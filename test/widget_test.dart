import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:github_releases_keep_update/app.dart';

void main() {
  testWidgets('App 可正常构建', (WidgetTester tester) async {
    // 页面在 build 中通过 Riverpod 读取配置，需要 ProviderScope
    await tester.pumpWidget(const ProviderScope(child: App()));
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
