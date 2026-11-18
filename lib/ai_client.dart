import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// AI 호출 실패를 한 가지 모양으로 모은다.
/// status: 401 · 429 · 500 · null(타임아웃/네트워크)
class AiException implements Exception {
  const AiException(this.status, [this.detail]);

  final int? status;
  final String? detail;

  bool get isTimeout => status == null && detail == 'timeout';

  @override
  String toString() => 'AiException($status, $detail)';
}

/// 앱이 아는 것은 chat() 하나뿐이다. 키는 프록시(서버)에만 있다.
abstract class AiClient {
  /// 응답 대기 한계 — Nielsen의 10초 주의 한계를 넘기면 오류로 돌려준다.
  static const timeout = Duration(seconds: 30);

  Future<String> chat(String message);
}

/// 프록시(w12/ai)에 붙는 실제 클라이언트.
/// 웹/데스크톱은 localhost:8787, Android 에뮬레이터는 10.0.2.2:8787.
class ProxyAiClient implements AiClient {
  ProxyAiClient({this.baseUrl = 'http://localhost:8787', http.Client? client})
    : _http = client ?? http.Client();

  final String baseUrl;
  final http.Client _http;

  @override
  Future<String> chat(String message) async {
    final http.Response res;
    try {
      res = await _http
          .post(
            Uri.parse('$baseUrl/api/chat'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'message': message}),
          )
          .timeout(AiClient.timeout);
    } on TimeoutException {
      throw const AiException(null, 'timeout');
    } catch (e) {
      throw AiException(null, 'network: $e');
    }

    if (res.statusCode != 200) throw AiException(res.statusCode, res.body);

    final body = jsonDecode(utf8.decode(res.bodyBytes));
    if (body is Map) {
      for (final key in const ['reply', 'answer', 'text', 'content']) {
        final v = body[key];
        if (v is String && v.isNotEmpty) return v;
      }
    }
    throw const AiException(500, 'empty response');
  }
}

/// 실패 상황을 마음대로 만들어 보는 모드 (프록시의 FORCE_STATUS와 같은 역할).
enum MockMode {
  ok('정상 응답'),
  unauthorized('401 키/권한'),
  rateLimited('429 한도 초과'),
  serverError('500 서버 오류'),
  timeout('타임아웃'),
  flaky429('429 두 번 후 성공');

  const MockMode(this.label);
  final String label;
}

/// 서버 없이 상태와 화면을 시험하는 가짜 클라이언트.
class MockAiClient implements AiClient {
  MockAiClient({
    this.mode = MockMode.ok,
    this.latency = const Duration(milliseconds: 1200),
  });

  MockMode mode;
  final Duration latency;

  /// 지금까지 들어온 호출 수 (백오프 재시도 확인용).
  int calls = 0;
  int _flakyFails = 0;

  @override
  Future<String> chat(String message) async {
    calls++;
    await Future<void>.delayed(latency);
    switch (mode) {
      case MockMode.ok:
        return _reply(message);
      case MockMode.unauthorized:
        throw const AiException(401);
      case MockMode.rateLimited:
        throw const AiException(429);
      case MockMode.serverError:
        throw const AiException(500);
      case MockMode.timeout:
        // 실제로 30초를 기다리지 않고, 기다린 끝의 결과만 흉내 낸다.
        throw const AiException(null, 'timeout');
      case MockMode.flaky429:
        // 처음 두 번은 429, 그다음은 성공 → 지수 백오프 1s → 2s 확인
        if (_flakyFails < 2) {
          _flakyFails++;
          throw const AiException(429);
        }
        _flakyFails = 0;
        return _reply(message);
    }
  }

  String _reply(String message) =>
      '“$message”에 대한 답입니다. '
      '(MOCK 응답 — 프록시를 켜면 실제 AI가 답합니다)';
}
