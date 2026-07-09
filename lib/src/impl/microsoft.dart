/**
 * [INPUT]: 依赖 collection/dio/uuid/web_socket_channel，依赖 engine/voice_option/word_boundary/tts_result
 * [OUTPUT]: 对外提供 MicrosoftTtsEngine 抽象基类, MicrosoftVoiceOptions
 * [POS]: impl/ 的协议层，实现 Microsoft WebSocket TTS 协议 + SSML + WordBoundary 解析
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
    final result = await _synthesize(text, voice, wordBoundary: false);
    return result.audioBytes;
  }

  // -------- 音频 + 词级时间戳 --------

  @override
  Future<TtsResult> convertWithTimestamps(
    String text,
    VoiceOption voice, {
    CancelToken? cancelToken,
  }) {
    return _synthesize(text, voice, wordBoundary: true);
  }

  // ============================================================
  // 核心管道：WebSocket → 分流 (audio / audio.metadata) → TtsResult
  // ============================================================

  Future<TtsResult> _synthesize(
    String text,
    VoiceOption voice, {
    required bool wordBoundary,
  }) async {
    final connection = doConnect();
    final boundaries = <WordBoundary>[];

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
            connection.sink.close();
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
      _buildConfigMessage(requestId, options.format, wordBoundary: wordBoundary),
      _buildSsmlMessage(requestId, text, options),
    ]).transform(requestTransformer);

    final outputStream = connection.stream.transform(responseTransformer);

    connection.sink.addStream(inputStream);
    final audioBytes = await outputStream.toList().then((chunks) => Uint8List.fromList(chunks.flattened.toList()));

    return TtsResult(audioBytes: audioBytes, boundaries: boundaries);
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
          out.add(WordBoundary.fromMetadata(map['Data'] as Map<String, dynamic>));
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

  MicrosoftVoiceOptions _convert(VoiceOption voice) => microsoftVoiceOptionsFor(voice);
}

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
  String toString() => "Message(path:$path, requestId:$requestId, contentType:$contentType)";

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
