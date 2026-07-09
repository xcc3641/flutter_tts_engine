/**
 * [INPUT]: 依赖 dio，依赖 engine/tts_result/voice_option，复用 azure(buildAzureSsml)/microsoft(microsoftVoiceOptionsFor)
 * [OUTPUT]: 对外提供 WorkerTtsEngine —— 把合成卸载到后端(持真 Azure key)的引擎
 * [POS]: impl/ 的一员，纯音频；无词级时间戳(REST 合成不返回 boundary)，靠上层 fallback 兜
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../engine.dart';
import '../tts_result.dart';
import '../voice_option.dart';
import '../word_boundary.dart';
import 'azure.dart' show buildAzureSsml;
import 'microsoft.dart' show microsoftVoiceOptionsFor;

/// 后端 TTS 引擎：客户端构 SSML（与 demo 同款 voice/音色），POST 到 [endpoint]
/// （通常是自家 Worker，云端持真 Azure Speech key），拿合成结果。
///
/// - **两条路径**：[convert] 走后端 REST，回音频字节（拍照单词/句子，快）；
///   [convertWithTimestamps] 带 `timestamps:true`，后端走 Azure WebSocket 取
///   词级时间戳，回 `{ audio_b64, boundaries }`（对话 KTV 高亮）。
/// - **鉴权不硬编码**：[headers] 由调用方注入（如 `{ 'x-kachika-token': '...' }`），
///   库不认识任何业务端点/凭据，保持通用。
/// - **超时即失败**：REST 3s、WS 8s（WS 后端要多一跳 Azure 长连），慢或死的
///   后端会抛错，交给上层 fallback（落 demo），不哑。
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

  // 熔断:worker 回 429(F0 额度耗尽)后进入冷却，期间直接抛 → 上层 fallback
  // 直落 demo，不再每次白打一趟注定失败的 Azure。
  static const Duration _cooldown = Duration(seconds: 60);
  DateTime _cooldownUntil = DateTime.fromMillisecondsSinceEpoch(0);

  Future<T> _guarded<T>(Future<T> Function() op) async {
    if (DateTime.now().isBefore(_cooldownUntil)) {
      throw StateError('WorkerTtsEngine cooling down after 429');
    }
    try {
      return await op();
    } on DioException catch (e) {
      if (e.response?.statusCode == 429) {
        _cooldownUntil = DateTime.now().add(_cooldown);
      }
      rethrow;
    }
  }

  @override
  Future<Uint8List> convert(
    String text,
    VoiceOption voice, {
    CancelToken? cancelToken,
  }) {
    return _guarded(() async {
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
    });
  }

  @override
  Future<TtsResult> convertWithTimestamps(
    String text,
    VoiceOption voice, {
    CancelToken? cancelToken,
  }) {
    return _guarded(() async {
      final options = microsoftVoiceOptionsFor(voice);
      final ssml = buildAzureSsml(text, options);
      final resp = await _dio.post<Map<String, dynamic>>(
        endpoint,
        data: {'ssml': ssml, 'format': options.format, 'timestamps': true},
        options: Options(
          headers: headers,
          responseType: ResponseType.json,
          receiveTimeout: const Duration(seconds: 16), // 后端多一跳 Azure WS，放宽
        ),
        cancelToken: cancelToken,
      );
      final data = resp.data;
      final audioB64 = data?['audio_b64'] as String?;
      if (audioB64 == null || audioB64.isEmpty) {
        throw StateError('WorkerTtsEngine: empty audio from $endpoint');
      }
      final rawBoundaries = (data?['boundaries'] as List?) ?? const [];
      final boundaries = rawBoundaries
          .map((e) => WordBoundary.fromMetadata(Map<String, dynamic>.from(e as Map)))
          .toList();
      return TtsResult(audioBytes: base64Decode(audioB64), boundaries: boundaries);
    });
  }

  @override
  Future<List<String>> getVoiceList() {
    throw UnsupportedError('WorkerTtsEngine has no voice list');
  }
}
