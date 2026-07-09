/**
 * [INPUT]: 依赖 dio，依赖 engine/tts_result/voice_option，复用 azure(buildAzureSsml)/microsoft(microsoftVoiceOptionsFor)
 * [OUTPUT]: 对外提供 WorkerTtsEngine —— 把合成卸载到后端(持真 Azure key)的引擎
 * [POS]: impl/ 的一员，纯音频；无词级时间戳(REST 合成不返回 boundary)，靠上层 fallback 兜
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../engine.dart';
import '../tts_result.dart';
import '../voice_option.dart';
import 'azure.dart' show buildAzureSsml;
import 'microsoft.dart' show microsoftVoiceOptionsFor;

/// 后端 TTS 引擎：客户端构 SSML（与 demo 同款 voice/音色），POST 到 [endpoint]
/// （通常是自家 Worker，云端持真 Azure Speech key），拿音频字节。
///
/// - **纯音频**：REST 合成不含词级时间戳，[convertWithTimestamps] 抛
///   [UnsupportedError] —— 由 FallbackTtsEngine 落到支持 boundary 的 demo 引擎。
/// - **鉴权不硬编码**：[headers] 由调用方注入（如 `{ 'x-kachika-token': '...' }`），
///   库不认识任何业务端点/凭据，保持通用。
/// - **超时即失败**：默认 3s connect/send/receive 超时，慢或死的后端会快速抛错，
///   交给上层 fallback，不拖点播体验。
class WorkerTtsEngine extends TtsEngine {
  WorkerTtsEngine({
    required this.endpoint,
    this.headers = const {},
    Dio? dio,
    Duration timeout = const Duration(seconds: 3),
  }) : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: timeout,
              sendTimeout: timeout,
              receiveTimeout: timeout,
            ));

  final String endpoint;
  final Map<String, String> headers;
  final Dio _dio;

  @override
  Future<Uint8List> convert(
    String text,
    VoiceOption voice, {
    CancelToken? cancelToken,
  }) async {
    final options = microsoftVoiceOptionsFor(voice);
    final ssml = buildAzureSsml(text, options);
    final resp = await _dio.post<List<int>>(
      endpoint,
      data: {'ssml': ssml, 'format': options.format},
      options: Options(headers: headers, responseType: ResponseType.bytes),
      cancelToken: cancelToken,
    );
    final data = resp.data;
    if (data == null || data.isEmpty) {
      throw StateError('WorkerTtsEngine: empty audio from $endpoint');
    }
    return Uint8List.fromList(data);
  }

  @override
  Future<TtsResult> convertWithTimestamps(
    String text,
    VoiceOption voice, {
    CancelToken? cancelToken,
  }) {
    // REST 合成无 WordBoundary；词级时间戳交给 fallback(demo WS)。
    throw UnsupportedError('WorkerTtsEngine has no word boundaries');
  }

  @override
  Future<List<String>> getVoiceList() {
    throw UnsupportedError('WorkerTtsEngine has no voice list');
  }
}
