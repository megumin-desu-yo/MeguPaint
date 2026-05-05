// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Basic widget test', (WidgetTester tester) async {
    // 简单的冒烟测试，验证 Flutter 测试框架工作正常
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('MeguPaint'))),
      ),
    );

    // 验证文本存在
    expect(find.text('MeguPaint'), findsOneWidget);
  });
}
