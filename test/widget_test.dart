import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lab1_chat_ui/main.dart';

void main() {
  testWidgets('앱이 뜨고 가짜 대화가 보인다', (WidgetTester tester) async {
    await tester.pumpWidget(const ChatLabApp());

    expect(find.text('AI Chat — 실습 1'), findsOneWidget);
    expect(find.text('오늘 뭐 배워?'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('입력하고 보내면 내 말풍선이 추가된다', (WidgetTester tester) async {
    await tester.pumpWidget(const ChatLabApp());

    await tester.enterText(find.byType(TextField), '안녕');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(find.text('안녕'), findsOneWidget);
  });
}
