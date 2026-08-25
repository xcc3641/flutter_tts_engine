/**
 * [INPUT]: 依赖 flutter_test/dio/web_socket_channel + dart:io HttpServer（真实本地服务端，不用 mock 框架）
 * [OUTPUT]: MicrosoftTtsEngine 的失败路径回归测试 —— 核心断言是「零未捕获异步异常」
 * [POS]: test/ 唯一测试文件，锁死 TICKET-TTS-FIX 修的四类场景
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_engine/src/impl/microsoft.dart';
import 'package:tts_engine/src/voice_option.dart';
import 'package:web_socket_channel/io.dart';

// ============================================================
// 测试用引擎：只替换连接目标，不动生产类的公开 API
// ============================================================

class _LocalWsEngine extends MicrosoftTtsEngine {
  _LocalWsEngine(this.uri, {this.connectTimeout = const Duration(seconds: 3)});

  final Uri uri;

  /// 默认与 AzureTtsEngine 同款 3s 快速失败；超时用例调短以免拖慢测试。
  final Duration connectTimeout;

  @override
  IOWebSocketChannel doConnect() => IOWebSocketChannel.connect(
        uri,
        pingInterval: const Duration(seconds: 10),
        connectTimeout: connectTimeout,
      );

  @override
  String buildSSml(String text, MicrosoftVoiceOptions options) =>
      '<speak><voice name="${options.voice}">$text</voice></speak>';

  @override
  Future<List<String>> getVoiceList() async => const <String>[];
}

// ============================================================
// 工具：在 runZonedGuarded 里跑一段，同时收集
//   - body 自己抛出的异常（这是「调用方能接住的」）
//   - 逃到 zone 的未捕获异步错误（这就是线上 fatal 的来源）
// ============================================================

typedef _Run = ({Object? error, List<Object> uncaught});

Future<_Run> _capture(Future<void> Function() body) async {
  final uncaught = <Object>[];
  final done = Completer<Object?>();

  runZonedGuarded(() async {
    Object? error;
    try {
      await body();
    } catch (e) {
      error = e;
    }
    if (!done.isCompleted) done.complete(error);
  }, (e, _) {
    uncaught.add(e);
  });

  final error = await done.future;
  // 未捕获错误由 SDK 的 _asyncCompleteErrorObject 经 scheduleMicrotask 上报
  // （future_impl.dart），所以泵干 microtask 队列就够，不靠固定 sleep 赌时间。
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  return (error: error, uncaught: uncaught);
}

/// 构造一帧文本消息。
/// 注意 [_Message.parse] 把 `Path:` 之后的所有行都算 payload（含分隔空行），
/// 这里按解析器的实际口径构造，避免 payload 多带一个前导 CRLF。
String _frame(String path, String payload) => [
      'X-Timestamp:${DateTime.now().toUtc().toIso8601String()}',
      'X-RequestId:00000000000000000000000000000000',
      'Content-Type:application/json',
      'Path:$path',
      payload,
    ].join('\r\n');

Future<HttpServer> _bind(void Function(HttpRequest) onRequest) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) {
    try {
      onRequest(req);
    } catch (_) {
      // 服务端自身异常与被测对象无关，别污染测试
    }
  });
  return server;
}

Uri _wsUri(HttpServer server) =>
    Uri.parse('ws://127.0.0.1:${server.port}/cognitiveservices/websocket/v1');

void main() {
  // ============================================================
  // 1. 连接被拒 / 不升级为 WebSocket（线上 56 条 fatal 的复现）
  // ============================================================
  test('HTTP 403 不升级为 WebSocket：convert 抛异常，且零未捕获异步错误', () async {
    final server = await _bind((req) {
      req.response.statusCode = HttpStatus.forbidden;
      req.response.close();
    });
    addTearDown(() => server.close(force: true));

    final engine = _LocalWsEngine(_wsUri(server));
    final run =
        await _capture(() => engine.convert('你好世界', VoiceOption.zhFemale));

    // 失败必须从被 await 的 Future 抛出（调用方 FallbackTtsEngine 才接得住）
    expect(run.error, isNotNull);
    // 且不能被误判成「取消」，否则 fallback 不会触发
    expect(run.error, isNot(isA<DioException>()));
    // 本票核心断言
    expect(run.uncaught, isEmpty,
        reason: '未捕获异步错误会逃到根 zone，被 Flutter 记成 fatal');
  });

  // ============================================================
  // 1b. connectTimeout 超时（线上 56 条 fatal / KACHIKA-P 的那条分支）
  //     adapter 对 TimeoutException 不包 WebSocketChannelException，
  //     直接原样 completeError(ready) —— 与 403 是**不同**分支，得单独覆盖。
  // ============================================================
  test('连接超时：抛裸 TimeoutException，且零未捕获异步错误', () async {
    // 只监听不 accept 的 TCP 端口：握手永远完不成，只能等 connectTimeout
    final silent = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(silent.close);

    final engine = _LocalWsEngine(
      Uri.parse('ws://127.0.0.1:${silent.port}/cognitiveservices/websocket/v1'),
      connectTimeout: const Duration(milliseconds: 300),
    );
    final run =
        await _capture(() => engine.convert('你好世界', VoiceOption.zhFemale));

    expect(run.error, isA<TimeoutException>());
    expect(run.uncaught, isEmpty,
        reason: 'ready 未被 await 时，这条超时就是线上 KACHIKA-P 的 fatal');
  });

  // ============================================================
  // 2. 握手中被服务端掐断（连接中断）
  // ============================================================
  test('握手中 socket 被销毁：convert 抛异常，且零未捕获异步错误', () async {
    final server = await _bind((req) async {
      final socket = await req.response.detachSocket(writeHeaders: false);
      socket.destroy();
    });
    addTearDown(() => server.close(force: true));

    final engine = _LocalWsEngine(_wsUri(server));
    final run =
        await _capture(() => engine.convert('你好世界', VoiceOption.zhFemale));

    expect(run.error, isNotNull);
    expect(run.uncaught, isEmpty);
  });

  // ============================================================
  // 3. 连接后立刻被服务端关闭
  // ============================================================
  test('升级后服务端立刻关闭：零未捕获异步错误', () async {
    final server = await _bind((req) async {
      final ws = await WebSocketTransformer.upgrade(req);
      await ws.close();
    });
    addTearDown(() => server.close(force: true));

    final engine = _LocalWsEngine(_wsUri(server));
    final run =
        await _capture(() => engine.convert('你好世界', VoiceOption.zhFemale));

    // 空音频本身不算错（服务端对无发音内容的合法回答），但绝不能留下未捕获错误
    expect(run.uncaught, isEmpty);
  });

  // ============================================================
  // 4. turn.end 与 addStream 的竞态
  // ============================================================
  test('服务端秒回 turn.end：不抛 StateError，音频照常返回，零未捕获异步错误', () async {
    final server = await _bind((req) async {
      final ws = await WebSocketTransformer.upgrade(req);
      ws.listen((_) {}, onError: (Object _) {});
      // 不等客户端把两帧发完，收到连接就立刻 audio + turn.end
      ws.add(_frame('audio', 'AUDIO-CHUNK'));
      ws.add(_frame('turn.end', ''));
    });
    addTearDown(() => server.close(force: true));

    final engine = _LocalWsEngine(_wsUri(server));
    List<int>? audio;
    final run = await _capture(() async {
      audio = await engine.convert('你好世界', VoiceOption.zhFemale);
    });

    expect(run.error, isNull, reason: 'turn.end 提前关 sink 不应把 StateError 抛给调用方');
    expect(String.fromCharCodes(audio ?? const <int>[]), 'AUDIO-CHUNK');
    expect(run.uncaught, isEmpty);
  });

  // ============================================================
  // 5. 取消
  // ============================================================
  test('CancelToken 已取消：不建连接，抛 DioException(cancel)', () async {
    var requests = 0;
    final server = await _bind((req) {
      requests++;
      req.response.close();
    });
    addTearDown(() => server.close(force: true));

    final engine = _LocalWsEngine(_wsUri(server));
    final token = CancelToken()..cancel();

    final run = await _capture(
        () => engine.convert('你好世界', VoiceOption.zhFemale, cancelToken: token));

    expect(
        run.error,
        isA<DioException>()
            .having((e) => e.type, 'type', DioExceptionType.cancel));
    expect(requests, 0, reason: '已取消就不该再发起连接');
    expect(run.uncaught, isEmpty);
  });

  test('中途 cancel：抛 DioException(cancel)，零未捕获异步错误', () async {
    // 升级后保持沉默，逼客户端一直等 —— 只能靠 cancel 结束
    final server = await _bind((req) async {
      final ws = await WebSocketTransformer.upgrade(req);
      ws.listen((_) {}, onError: (Object _) {});
    });
    addTearDown(() => server.close(force: true));

    final engine = _LocalWsEngine(_wsUri(server));
    final token = CancelToken();

    final run = await _capture(() async {
      final pending =
          engine.convert('你好世界', VoiceOption.zhFemale, cancelToken: token);
      Timer(const Duration(milliseconds: 200), token.cancel);
      await pending;
    });

    expect(
        run.error,
        isA<DioException>()
            .having((e) => e.type, 'type', DioExceptionType.cancel));
    expect(run.uncaught, isEmpty);
  });

  // ============================================================
  // 6. 正常路径没被改坏：音频 + 词级时间戳
  // ============================================================
  test('正常合成：音频与 WordBoundary 都能拿到', () async {
    const metadata = '{"Metadata":[{"Type":"WordBoundary","Data":'
        '{"Offset":1000000,"Duration":5000000,"text":{"Text":"你好","Length":2,"BoundaryType":"WordBoundary"}}}]}';

    final server = await _bind((req) async {
      final ws = await WebSocketTransformer.upgrade(req);
      var received = 0;
      ws.listen((_) {
        received++;
        // 等 config + ssml 两帧都到齐再回，模拟真实服务端
        if (received < 2) return;
        ws.add(_frame('audio.metadata', metadata));
        ws.add(_frame('audio', 'HELLO'));
        ws.add(_frame('turn.end', ''));
      }, onError: (Object _) {});
    });
    addTearDown(() => server.close(force: true));

    final engine = _LocalWsEngine(_wsUri(server));
    final result =
        await engine.convertWithTimestamps('你好世界', VoiceOption.zhFemale);

    expect(String.fromCharCodes(result.audioBytes), 'HELLO');
    expect(result.boundaries, hasLength(1));
    expect(result.boundaries.first.text, '你好');
  });
}
