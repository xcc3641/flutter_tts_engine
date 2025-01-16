import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import '../engine.dart';
import '../voice_option.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/io.dart';

abstract class MicrosoftTtsEngine extends TtsEngine {
  IOWebSocketChannel doConnect();
  String buildSSml(String text, MicrosoftVoiceOptions options);

  @override
  Future<Uint8List> convert(
    String text,
    VoiceOption voice, {
    CancelToken? cancelToken,
  }) async {
    final connection = doConnect();

    final requestTransformer = StreamTransformer.fromHandlers(
      handleData: (_Message data, EventSink<String> sink) {
        final msg = data.build();
        sink.add(msg);
      },
    );

    final responseTransformer = StreamTransformer.fromHandlers(
      handleData: (dynamic data, EventSink<List<int>> sink) {
        final message = _parseMessage(data);
        if (message == null) return;
        switch (message.path) {
          case "turn.start":
            break;
          case "audio":
            sink.add(message.payload.codeUnits);
            break;
          case "turn.end":
            connection.sink.close();
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

    final inputStream = Stream.fromIterable(
      [
        _buildConfigMessage(requestId, options.format),
        _buildSsmlMessage(requestId, text, options),
      ],
    ).transform(requestTransformer);
    final outputStream = connection.stream.transform(responseTransformer);

    connection.sink.addStream(inputStream);
    return outputStream.toList().then((value) => Uint8List.fromList(value.flattened.toList()));
  }

  _Message? _parseMessage(dynamic data) {
    try {
      if (data is String) {
        return _Message.parse(data);
      } else if (data is Uint8List) {
        return _Message.parse(String.fromCharCodes(data));
      } else {
        return null;
      }
    } catch (e, s) {
      return null;
    }
  }

  _Message _buildConfigMessage(String requestId, String format) {
    final data = {
      "context": {
        "synthesis": {
          "audio": {
            "metadataOptions": {
              "sentenceBoundaryEnabled": false,
              "wordBoundaryEnabled": false,
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

  _Message _buildSsmlMessage(String requestId, String text, MicrosoftVoiceOptions options) {
    return _Message(
      requestId: requestId,
      path: "ssml",
      contentType: "application/ssml+xml",
      payload: buildSSml(text, options),
    );
  }

  MicrosoftVoiceOptions _convert(VoiceOption voice) {
    switch (voice) {
      case VoiceOption.femaleYouthful:
        return const MicrosoftVoiceOptions(voice: "zh-CN-XiaoxiaoNeural");
      case VoiceOption.femaleAnime:
        return const MicrosoftVoiceOptions(voice: "zh-CN-XiaoyiNeural");
      case VoiceOption.maleCalm:
        return const MicrosoftVoiceOptions(voice: "zh-CN-YunxiNeural");
      case VoiceOption.maleMature:
        return const MicrosoftVoiceOptions(voice: "zh-CN-YunyangNeural");
      case VoiceOption.japaneseFemale:
        return const MicrosoftVoiceOptions(voice: "ja-JP-NanamiNeural");
      case VoiceOption.japaneseMale:
        return const MicrosoftVoiceOptions(voice: "ja-JP-KeitaNeural");
      case VoiceOption.englishFemale:
        return const MicrosoftVoiceOptions(voice: "en-US-EmmaNeural");
    }
  }
}

class MicrosoftVoiceOptions {
  /// 声音
  final String voice;

  /// 风格
  final String style;

  /// 风格强度
  final double styleDegree;

  /// 角色
  final String role;

  /// 音频格式
  final String format;

  const MicrosoftVoiceOptions({
    this.voice = "zh-CN-XiaoyiNeural",
    this.style = "general",
    this.styleDegree = 1.0,
    this.role = "default",
    this.format = "audio-24khz-48kbitrate-mono-mp3",
  });
}

class _Message {
  final String path;
  final String requestId;
  final String contentType;

  final String payload;

  _Message({required this.path, required this.requestId, required this.contentType, required this.payload});

  @override
  String toString() {
    return "Message(path:$path, requestId:$requestId, contentType:$contentType)";
  }

  String build() {
    final ts = DateTime.now().toUtc().toIso8601String();
    final config = [
      "X-Timestamp:$ts",
      "X-RequestId:$requestId",
      "Content-Type:$contentType",
      "Path:$path",
      "",
      payload,
    ].join("\r\n");
    return config;
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
