import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:github_releases_keep_update/app.dart';

void main() {
  testWidgets('App 可正常构建', (WidgetTester tester) async {
    // 页面在 build 中通过 Riverpod 读取配置，需要 ProviderScope
    await tester.pumpWidget(const ProviderScope(child: App()));
    expect(find.byType(MaterialApp), findsOneWidget);
    // 卸载组件树：释放后台自动检测的定时器（ProviderScope 销毁时 stop）
    await tester.pumpWidget(const SizedBox());
  });
}
