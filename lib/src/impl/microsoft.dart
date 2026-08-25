/**
 * [INPUT]: 依赖 collection/dio/uuid/web_socket_channel，依赖 engine/voice_option/word_boundary/tts_result
 * [OUTPUT]: 对外提供 MicrosoftTtsEngine 抽象基类, MicrosoftVoiceOptions
 * [POS]: impl/ 的协议层，实现 Microsoft WebSocket TTS 协议 + SSML + WordBoundary 解析；
 *        并负责 WebSocket 生命周期：await ready 让惰性连接的失败在被 await 处抛出、
 *        addStream 的 Future 就地消化、turn.end 与发送竞态的串行化、cancelToken 透传，
 *        保证任何退出路径都不留下携带未处理错误的 Future（否则会逃到根 zone 变 fatal）
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/io.dart';

import '../engine.dart';
import '../tts_result.dart';
import '../voice_option.dart';
import '../word_boundary.dart';

// ============================================================
// MicrosoftTtsEngine — WebSocket TTS 协议抽象
// 子类只需实现 doConnect() 和 buildSSml()
// ============================================================

abstract class MicrosoftTtsEngine extends TtsEngine {
  IOWebSocketChannel doConnect();
  String buildSSml(String text, MicrosoftVoiceOptions options);

  // -------- 纯音频合成 --------

  @override
  Future<Uint8List> convert(
    String text,
    VoiceOption voice, {
    CancelToken? cancelToken,
  }) async {
    final result = await _synthesize(text, voice,
        wordBoundary: false, cancelToken: cancelToken);
    return result.audioBytes;
  }

  // -------- 音频 + 词级时间戳 --------

  @override
  Future<TtsResult> convertWithTimestamps(
    String text,
    VoiceOption voice, {
    CancelToken? cancelToken,
  }) {
    return _synthesize(text, voice,
        wordBoundary: true, cancelToken: cancelToken);
  }

  // ============================================================
  // 核心管道：WebSocket → 分流 (audio / audio.metadata) → TtsResult
  // ============================================================

  Future<TtsResult> _synthesize(
    String text,
    VoiceOption voice, {
    required bool wordBoundary,
    CancelToken? cancelToken,
  }) async {
    // 已经取消就别建连接。
    if (cancelToken != null && cancelToken.isCancelled)
      throw _cancelError(cancelToken);

    final connection = doConnect();
    final boundaries = <WordBoundary>[];

    // addStream 进行中 / turn.end 已经要求关闭 / 连接已经关过。
    var sending = false;
    var closeRequested = false;
    var closed = false;

    // 关闭连接，且吞掉 close 自身的同步/异步异常：
    // 连接压根没建起来时 close() 可能抛，也可能久久不完成，都不该外泄。
    void closeQuietly() {
      if (closed) return;
      closed = true;
      try {
        unawaited(
            connection.sink.close().then<void>((_) {}, onError: (Object _) {}));
      } catch (_) {
        // close 的同步异常同样就地消化
      }
    }

    // turn.end 想关 sink，但 addStream 还没送完时先记账，
    // 等发送结束再关 —— 否则 addStream 会抛 StateError: StreamSink is closed。
    void requestClose() {
      if (sending) {
        closeRequested = true;
        return;
      }
      closeQuietly();
    }

    final requestTransformer = StreamTransformer.fromHandlers(
      handleData: (_Message data, EventSink<String> sink) {
        sink.add(data.build());
      },
    );

    final responseTransformer = StreamTransformer.fromHandlers(
      handleData: (dynamic data, EventSink<List<int>> sink) {
        final message = _parseMessage(data);
        if (message == null) return;
        switch (message.path) {
          case "audio":
            sink.add(message.payload.codeUnits);
          case "audio.metadata":
            if (wordBoundary) _extractBoundaries(message.payload, boundaries);
          case "turn.end":
            requestClose();
          default:
            break;
        }
      },
      handleError: (error, stackTrace, sink) {
        sink.addError(error, stackTrace);
      },
      handleDone: (sink) {
        sink.close();
      },
    );

    final requestId = const Uuid().v4().toString();
    final options = _convert(voice);

    final inputStream = Stream.fromIterable([
      _buildConfigMessage(requestId, options.format,
          wordBoundary: wordBoundary),
      _buildSsmlMessage(requestId, text, options),
    ]).transform(requestTransformer);

    // 先订阅 output：连接失败时错误由这条流带出。
    // 立刻挂一个 catchError，保证无论谁先失败，这条 Future 都不是「无人处理」的。
    final outputFuture =
        connection.stream.transform(responseTransformer).toList();
    unawaited(outputFuture.catchError((Object _) => const <List<int>>[]));

    try {
      // IOWebSocketChannel.connect 是惰性的：连接在后台建立。
      // 在这里 await，让 403 / 连接超时 / DNS 失败从本函数抛出，
      // 而不是留下一条没人 await 的 ready Future 逃到根 zone。
      await _raceCancel<void>(connection.ready, cancelToken);

      sending = true;
      try {
        await connection.sink.addStream(inputStream);
      } catch (_) {
        // 发送途中连接断开，或 turn.end 抢先关掉了 sink。
        // 同一失败已经由 ready / outputStream 抛给调用方，这里吞掉不丢信息。
      } finally {
        sending = false;
        if (closeRequested) closeQuietly();
      }

      final chunks = await _raceCancel(outputFuture, cancelToken);

      // 可能是空音频：demo 端点对纯空白/纯标点这类无发音内容会握手成功、
      // 一帧不发、正常结束（实测 '   ' → 0 帧 / 1.2s）。那是服务端的合法回答，
      // 不是本层的错误。**消费方**若按「文件存在」判缓存，必须自己拒绝写 0 字节，
      // 否则会把该文本永久钉成无声。
      return TtsResult(
        audioBytes: Uint8List.fromList(chunks.flattened.toList()),
        boundaries: boundaries,
      );
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.cancel) rethrow;
      // 取消导致的连接中断统一归一成 DioException.cancel，
      // 让 FallbackTtsEngine._isCancel 判成取消而不是失败（取消不该触发 fallback）。
      if (cancelToken != null && cancelToken.isCancelled)
        throw _cancelError(cancelToken);
      rethrow;
    } finally {
      closeQuietly();
    }
  }

  /// [future] 与「被取消」赛跑：取消先到就抛 [DioException]（type=cancel）。
  /// 输的一方即使随后带错误完成，也已经被 [Future.any] 的监听消化，不会逃逸。
  Future<T> _raceCancel<T>(Future<T> future, CancelToken? cancelToken) {
    if (cancelToken == null) return future;
    return Future.any<T>([
      future,
      cancelToken.whenCancel.then<T>((e) => throw e),
    ]);
  }

  // ============================================================
  // WordBoundary 解析
  // audio.metadata payload: {"Metadata":[{"Type":"WordBoundary","Data":{...}}]}
  // ============================================================

  void _extractBoundaries(String payload, List<WordBoundary> out) {
    try {
      final json = jsonDecode(payload) as Map<String, dynamic>;
      final metadata = json['Metadata'] as List<dynamic>? ?? [];
      for (final entry in metadata) {
        final map = entry as Map<String, dynamic>;
        if (map['Type'] == 'WordBoundary') {
          out.add(
              WordBoundary.fromMetadata(map['Data'] as Map<String, dynamic>));
        }
      }
    } catch (_) {
      // 非 WordBoundary 消息或格式异常，静默跳过
    }
  }

  // ============================================================
  // 消息解析与构建
  // ============================================================

  _Message? _parseMessage(dynamic data) {
    try {
      if (data is String) {
        return _Message.parse(data);
      } else if (data is Uint8List) {
        return _Message.parse(String.fromCharCodes(data));
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  _Message _buildConfigMessage(
    String requestId,
    String format, {
    required bool wordBoundary,
  }) {
    final data = {
      "context": {
        "synthesis": {
          "audio": {
            "metadataOptions": {
              "sentenceBoundaryEnabled": false,
              "wordBoundaryEnabled": wordBoundary,
            },
            "outputFormat": format,
          }
        }
      }
    };
    return _Message(
      requestId: requestId,
      path: "speech.config",
      contentType: "application/json",
      payload: jsonEncode(data),
    );
  }

  _Message _buildSsmlMessage(
    String requestId,
    String text,
    MicrosoftVoiceOptions options,
  ) {
    return _Message(
      requestId: requestId,
      path: "ssml",
      contentType: "application/ssml+xml",
      payload: buildSSml(text, options),
    );
  }

  // ============================================================
  // VoiceOption → MicrosoftVoiceOptions 映射
  // ============================================================

  MicrosoftVoiceOptions _convert(VoiceOption voice) =>
      microsoftVoiceOptionsFor(voice);
}

// ============================================================
// 取消异常：必须能被 FallbackTtsEngine._isCancel 判定（DioException + type=cancel），
// 否则取消会被当成失败而误触 fallback。
// ============================================================

DioException _cancelError(CancelToken token) =>
    token.cancelError ??
    DioException.requestCancelled(
      requestOptions: RequestOptions(path: ''),
      reason: 'TTS request cancelled',
    );

// ============================================================
// VoiceOption → MicrosoftVoiceOptions 映射（顶层，供 Azure/Worker 等实现共用）
// ============================================================

MicrosoftVoiceOptions microsoftVoiceOptionsFor(VoiceOption voice) {
  switch (voice) {
    // -------- 女声 --------
    case VoiceOption.zhFemale:
      return const MicrosoftVoiceOptions(voice: "zh-CN-XiaoxiaoNeural");
    case VoiceOption.japaneseFemale:
      return const MicrosoftVoiceOptions(voice: "ja-JP-NanamiNeural");
    case VoiceOption.englishFemale:
      return const MicrosoftVoiceOptions(voice: "en-US-EmmaNeural");
    case VoiceOption.spanishFemale:
      return const MicrosoftVoiceOptions(voice: "es-ES-ElviraNeural");
    case VoiceOption.koreanFemale:
      return const MicrosoftVoiceOptions(voice: "ko-KR-SunHiNeural");
    case VoiceOption.frenchFemale:
      return const MicrosoftVoiceOptions(voice: "fr-FR-DeniseNeural");
    case VoiceOption.italianFemale:
      return const MicrosoftVoiceOptions(voice: "it-IT-ElsaNeural");
    // -------- 男声 --------
    case VoiceOption.zhMale:
      return const MicrosoftVoiceOptions(voice: "zh-CN-YunxiNeural");
    case VoiceOption.japaneseMale:
      return const MicrosoftVoiceOptions(voice: "ja-JP-KeitaNeural");
    case VoiceOption.englishMale:
      return const MicrosoftVoiceOptions(voice: "en-US-BrianNeural");
    case VoiceOption.spanishMale:
      return const MicrosoftVoiceOptions(voice: "es-ES-AlvaroNeural");
    case VoiceOption.koreanMale:
      return const MicrosoftVoiceOptions(voice: "ko-KR-InJoonNeural");
    case VoiceOption.frenchMale:
      return const MicrosoftVoiceOptions(voice: "fr-FR-HenriNeural");
    case VoiceOption.italianMale:
      return const MicrosoftVoiceOptions(voice: "it-IT-DiegoNeural");
  }
}

// ============================================================
// MicrosoftVoiceOptions — 声音配置
// ============================================================

class MicrosoftVoiceOptions {
  final String voice;
  final String style;
  final double styleDegree;
  final String role;
  final String format;

  const MicrosoftVoiceOptions({
    this.voice = "zh-CN-XiaoyiNeural",
    this.style = "general",
    this.styleDegree = 1.0,
    this.role = "default",
    this.format = "audio-24khz-48kbitrate-mono-mp3",
  });
}

// ============================================================
// _Message — WebSocket 消息帧 (header + payload)
// ============================================================

class _Message {
  final String path;
  final String requestId;
  final String contentType;
  final String payload;

  _Message({
    required this.path,
    required this.requestId,
    required this.contentType,
    required this.payload,
  });

  @override
  String toString() =>
      "Message(path:$path, requestId:$requestId, contentType:$contentType)";

  String build() {
    final ts = DateTime.now().toUtc().toIso8601String();
    return [
      "X-Timestamp:$ts",
      "X-RequestId:$requestId",
      "Content-Type:$contentType",
      "Path:$path",
      "",
      payload,
    ].join("\r\n");
  }

  factory _Message.parse(String data) {
    const separator = "\r\n";
    final lines = data.split(separator);

    final headers = <String, String>{};

    var i = 0;
    while (i < lines.length) {
      final line = lines[i];
      final kv = line.split(":");
      if (kv.length == 2) {
        headers[kv[0]] = kv[1];
      }
      if (line.startsWith("Path:")) break;
      i++;
    }

    final payload = lines.sublist(i + 1).join(separator);

    return _Message(
      path: headers["Path"] ?? "",
      requestId: headers["X-RequestId"] ?? "",
      contentType: headers["Content-Type"] ?? "",
      payload: payload,
    );
  }
}
