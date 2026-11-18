import 'package:flutter/material.dart';

import 'ai_client.dart';

/// flutter run --dart-define=USE_PROXY=true 로 실제 프록시(8787)에 붙는다.
const _useProxy = bool.fromEnvironment('USE_PROXY');

void main() => runApp(const ChatLabApp());

class ChatLabApp extends StatelessWidget {
  const ChatLabApp({super.key, this.client});

  /// 테스트에서 가짜 클라이언트를 넣을 수 있게 열어 둔다.
  final AiClient? client;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Chat — 실습 1',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2F6FE4)),
        useMaterial3: true,
      ),
      home: ChatPage(client: client),
    );
  }
}

/// 대화 한 줄. 서버 없이 화면만 만들기 위한 최소 모델.
class ChatMessage {
  const ChatMessage({required this.text, required this.isUser});

  final String text;
  final bool isUser;
}

/// 오류 → 화면 문구 (테스트에서도 쓴다).
String errorMessageFor(Object e) => _ChatPageState.errorMessage(e);

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, this.client});

  final AiClient? client;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  /// 실습용 가짜 대화 — API를 붙이기 전까지 이 목록으로 화면을 만든다.
  final List<ChatMessage> _messages = [
    const ChatMessage(text: '오늘 뭐 배워?', isUser: true),
    const ChatMessage(text: 'AI 챗봇에 움직이는 응답을 붙입니다.', isUser: false),
    const ChatMessage(text: '타이핑 점은 왜 필요해요?', isUser: true),
    const ChatMessage(text: '응답이 1초를 넘으면 앱이 멈춘 것처럼 보이기 때문입니다.', isUser: false),
  ];

  final _controller = TextEditingController();
  final _scroll = ScrollController();

  late final AiClient _ai =
      widget.client ?? (_useProxy ? ProxyAiClient() : MockAiClient());

  /// sending: 전송 중(입력 잠금) · typing: 응답 대기(점 3개)
  bool _sending = false;
  bool _typing = false;

  /// error: 마지막 요청이 실패했을 때의 문구. null이면 오류 없음.
  String? _error;

  /// 재시도는 마지막 사용자 메시지를 다시 보낸다.
  String? _lastPrompt;

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// 401 · 429 · 500 · timeout을 하나의 error 상태(문구)로 모은다.
  static String errorMessage(Object e) {
    if (e is! AiException) return '⚠️ 응답을 받지 못했습니다';
    if (e.isTimeout) return '⏱️ 응답이 30초 넘게 없습니다. 네트워크를 확인해 주세요';
    return switch (e.status) {
      401 => '🔑 키/권한을 확인해 주세요',
      429 => '⏳ 요청이 많습니다. 잠시 후 다시 시도해 주세요',
      500 => '⚠️ 응답을 받지 못했습니다',
      _ => '📡 네트워크를 확인해 주세요',
    };
  }

  /// 새 메시지는 보이는 곳에 — reverse:true라 맨 아래는 offset 0이다.
  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      if (MediaQuery.of(context).disableAnimations) {
        _scroll.jumpTo(0);
      } else {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return; // 연타해도 한 번만
    _controller.clear();
    setState(() => _messages.add(ChatMessage(text: text, isUser: true)));
    _toBottom();
    await _request(text);
  }

  /// 오류 말풍선의 '다시 시도' — 내 말풍선은 그대로 두고 요청만 다시.
  Future<void> _retry() async {
    final text = _lastPrompt;
    if (text == null || _sending) return;
    await _request(text);
  }

  Future<void> _request(String text) async {
    setState(() {
      _lastPrompt = text;
      _error = null;
      _sending = true;
      _typing = true;
    });
    try {
      final answer = await _ai.chat(text);
      if (!mounted) return;
      setState(() => _messages.add(ChatMessage(text: answer, isUser: false)));
      _toBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = errorMessage(e));
    } finally {
      // 오류 뒤에도 입력이 되도록 잠금은 항상 푼다.
      if (mounted) {
        setState(() {
          _sending = false;
          _typing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 접근성: OS의 '애니메이션 줄이기'가 켜지면 움직임만 끄고 정보는 그대로.
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return Scaffold(
      // ✅ 할 일 5 — 키보드가 올라오면 body가 줄어들어 입력창이 키보드 위에 남는다.
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('AI Chat — 실습 1'),
        actions: [
          if (_ai case final MockAiClient mock)
            PopupMenuButton<MockMode>(
              tooltip: '응답 모드 (MOCK)',
              icon: const Icon(Icons.science_outlined),
              initialValue: mock.mode,
              onSelected: (m) => setState(() => mock.mode = m),
              itemBuilder: (_) => [
                for (final m in MockMode.values)
                  CheckedPopupMenuItem(
                    value: m,
                    checked: m == mock.mode,
                    child: Text(m.label),
                  ),
              ],
            ),
          IconButton(
            tooltip: '대화 지우기',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _messages.isEmpty || _sending
                ? null
                : () => setState(() {
                    _messages.clear();
                    _error = null;
                  }),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ✅ 할 일 1 — ListView.builder + reverse: true (index 0 = 맨 아래)
            // ✅ 할 일 4 — 빈 상태: Stack으로 목록 위에 안내문을 겹친다.
            Expanded(
              child: Stack(
                children: [
                  ListView.builder(
                    controller: _scroll,
                    reverse: true,
                    // 목록을 끌어내리면 키보드가 닫힌다.
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[_messages.length - 1 - index];
                      return _Bubble(message: message);
                    },
                  ),
                  if (_messages.isEmpty) const _EmptyState(),
                ],
              ),
            ),

            // ✅ 할 일 3 — 입력창. SafeArea 안 Column 맨 아래라 홈 인디케이터를 피한다.
            // typing ↔ error ↔ 없음 전환을 AnimatedSwitcher로 (200ms, 한 번에 하나).
            AnimatedSwitcher(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SizeTransition(
                  sizeFactor: animation,
                  child: child,
                ),
              ),
              child: switch ((_typing, _error)) {
                (true, _) => const _TypingBubble(key: ValueKey('typing')),
                (false, final String error) => _ErrorBubble(
                  key: ValueKey('error:$error'),
                  message: error,
                  onRetry: _retry,
                ),
                _ => const SizedBox.shrink(key: ValueKey('idle')),
              },
            ),
            _InputBar(
              controller: _controller,
              onSend: _send,
              enabled: !_sending,
            ),
          ],
        ),
      ),
    );
  }
}

/// ✅ 할 일 2 — 말풍선 2종. 사용자는 오른쪽(primaryContainer), AI는 왼쪽.
/// 색은 colorScheme에서 꺼내 다크 모드에서도 대비가 유지된다.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: isUser
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isUser ? 14 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 14),
          ),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: isUser
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// error 상태 — 화면에 남는 오류 말풍선 + 다시 시도.
class _ErrorBubble extends StatelessWidget {
  const _ErrorBubble({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  message,
                  style: TextStyle(color: colorScheme.onErrorContainer),
                ),
              ),
            ),
            const SizedBox(width: 4),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('다시 시도'),
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.onErrorContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// typing 상태 — AI 쪽(왼쪽)에 점 3개가 든 말풍선.
class _TypingBubble extends StatelessWidget {
  const _TypingBubble({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Semantics(label: 'AI가 답을 쓰는 중', child: const TypingDots()),
      ),
    );
  }
}

/// 점 3개가 순서대로 켜진다 (점 하나당 200ms, 한 바퀴 600ms).
class TypingDots extends StatefulWidget {
  const TypingDots({super.key});

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduce Motion이면 점을 멈추고 셋 다 켠 채로 보여 준다.
    if (MediaQuery.of(context).disableAnimations) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) {
        final t = _c.isAnimating ? (_c.value * 3).floor() % 3 : 2;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Opacity(
                  opacity: i <= t ? 1 : 0.25,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 할 일 4 — 빈 상태. 무엇을 할 수 있는지 미리 알려 주는 피드포워드.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline, size: 48, color: colorScheme.outline),
          const SizedBox(height: 12),
          Text(
            '무엇이든 물어보세요',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 할 일 3 — 입력창 (TextField + 전송 버튼)
class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.onSend,
    this.enabled = true,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: enabled ? '메시지를 입력하세요' : '응답을 기다리는 중…',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 피드포워드: 글자가 없거나 전송 중이면 버튼이 비활성으로 보인다.
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final canSend = enabled && value.text.trim().isNotEmpty;
              return IconButton.filled(
                tooltip: '보내기',
                icon: const Icon(Icons.send),
                onPressed: canSend ? onSend : null,
              );
            },
          ),
        ],
      ),
    );
  }
}
