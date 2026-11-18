import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lab1_chat_ui/ai_client.dart';
import 'package:lab1_chat_ui/main.dart';

const _latency = Duration(milliseconds: 100);

Future<MockAiClient> _pumpApp(
  WidgetTester tester, {
  MockMode mode = MockMode.ok,
}) async {
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

  testWidgets('오류 문구가 남고, 다시 시도하면 답이 온다', (tester) async {
    final client = await _pumpApp(tester, mode: MockMode.serverError);
    await _sendText(tester, '질문');
    await tester.pump(_latency);
    await tester.pumpAndSettle();

    expect(find.text('⚠️ 응답을 받지 못했습니다'), findsOneWidget);
    // 오류 뒤에도 입력이 된다
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enabled, isTrue);

    client.mode = MockMode.ok;
    await tester.tap(find.text('다시 시도'));
    await tester.pump();
    await tester.pump(_latency);
    await tester.pumpAndSettle();

    expect(find.text('⚠️ 응답을 받지 못했습니다'), findsNothing);
    expect(find.textContaining('“질문”에 대한 답'), findsOneWidget);
    expect(find.text('질문'), findsOneWidget); // 내 말풍선은 한 번만
  });

  test('상태 코드별 오류 문구', () {
    expect(errorMessageFor(const AiException(401)), contains('키/권한'));
    expect(errorMessageFor(const AiException(429)), contains('잠시 후'));
    expect(errorMessageFor(const AiException(500)), contains('응답을 받지 못했습니다'));
    expect(
      errorMessageFor(const AiException(null, 'timeout')),
      contains('네트워크'),
    );
  });

  testWidgets('Reduce Motion이면 점이 멈춘 채 보인다', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await _pumpApp(tester);
    await _sendText(tester, '안녕');

    expect(find.byType(TypingDots), findsOneWidget);
    final dots = tester.widgetList<Opacity>(
      find.descendant(
        of: find.byType(TypingDots),
        matching: find.byType(Opacity),
      ),
    );
    // 멈춘 상태에서도 점 3개가 모두 보인다 (정보는 유지)
    expect(dots.map((o) => o.opacity), everyElement(1.0));

    await tester.pump(_latency);
    await tester.pump();
    expect(find.textContaining('“안녕”에 대한 답'), findsOneWidget);
  });

  testWidgets('429면 1s → 2s 백오프 후 다시 시도해 성공한다', (tester) async {
    final client = await _pumpApp(tester, mode: MockMode.flaky429);
    await _sendText(tester, '혼잡');

    await tester.pump(_latency); // 1차 429
    expect(client.calls, 1);
    await tester.pump(const Duration(seconds: 1)); // 1s 대기 → 2차
    expect(client.calls, 2);
    await tester.pump(_latency); // 2차 429
    await tester.pump(const Duration(seconds: 2)); // 2s 대기 → 3차
    expect(client.calls, 3);
    await tester.pump(_latency); // 3차 성공
    await tester.pumpAndSettle();

    expect(find.textContaining('“혼잡”에 대한 답'), findsOneWidget);
    expect(find.textContaining('잠시 후'), findsNothing);
  });

  testWidgets('429가 계속되면 백오프 뒤 "잠시 후" 오류', (tester) async {
    final client = await _pumpApp(tester, mode: MockMode.rateLimited);
    await _sendText(tester, '혼잡');

    await tester.pump(_latency);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(_latency);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(_latency);
    await tester.pumpAndSettle();

    expect(client.calls, 3);
    expect(find.textContaining('잠시 후'), findsOneWidget);
  });
}
