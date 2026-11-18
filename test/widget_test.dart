import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lab1_chat_ui/ai_client.dart';
import 'package:lab1_chat_ui/main.dart';

const _latency = Duration(milliseconds: 100);

Future<MockAiClient> _pumpApp(WidgetTester tester,
    {MockMode mode = MockMode.ok}) async {
  final client = MockAiClient(mode: mode, latency: _latency);
  await tester.pumpWidget(ChatLabApp(client: client));
  return client;
}

Future<void> _sendText(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump(); // 글자가 들어가야 전송 버튼이 켜진다
  await tester.tap(find.byIcon(Icons.send));
  await tester.pump();
}

void main() {
  testWidgets('앱이 뜨고 가짜 대화가 보인다', (tester) async {
    await _pumpApp(tester);

    expect(find.text('AI Chat — 실습 1'), findsOneWidget);
    expect(find.text('오늘 뭐 배워?'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('보내면 내 말풍선 → 점 3개 → AI 말풍선', (tester) async {
    await _pumpApp(tester);
    await _sendText(tester, '안녕');

    expect(find.text('안녕'), findsOneWidget);
    expect(find.byType(TypingDots), findsOneWidget); // typing

    await tester.pump(_latency);
    await tester.pumpAndSettle();

    expect(find.byType(TypingDots), findsNothing);
    expect(find.textContaining('“안녕”에 대한 답'), findsOneWidget);
  });

  testWidgets('대화를 지우면 빈 상태 문구가 보인다', (tester) async {
    await _pumpApp(tester);
    expect(find.text('무엇이든 물어보세요'), findsNothing);

    await tester.tap(find.byTooltip('대화 지우기'));
    await tester.pump();

    expect(find.text('무엇이든 물어보세요'), findsOneWidget);
  });
}
