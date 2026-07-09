/**
 * [INPUT]: 依赖 dio(CancelToken 判定)，依赖 engine/tts_result/voice_option
 * [OUTPUT]: 对外提供 FallbackTtsEngine —— primary 失败/超时落 fallback 的组合器
 * [POS]: decorator/ 的一员，包 primary+fallback；被 factory 组装进默认引擎栈
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../engine.dart';
import '../tts_result.dart';
import '../voice_option.dart';

/// 组合两个引擎：[primary] 抛错/超时 → 落 [fallback]。
///
/// convert / convertWithTimestamps / getVoiceList 三个口子统一「试 primary，
/// 失败落 fallback」，没有 per-method 特判 —— WorkerTtsEngine 的
/// convertWithTimestamps 同步抛 [UnsupportedError]（不发网络），因此 KTV 词级
/// 时间戳零成本落到 fallback（demo WS）。boundary「分水岭」化进正常控制流。
///
/// 唯一例外：显式取消（CancelToken）不算失败，直接向上抛，不误触 fallback。
class FallbackTtsEngine extends TtsEngine {
  FallbackTtsEngine({required this.primary, required this.fallback});

  final TtsEngine primary;
  final TtsEngine fallback;

  bool _isCancel(Object e) =>
      e is DioException && e.type == DioExceptionType.cancel;

  @override
  Future<Uint8List> convert(
    String text,
    VoiceOption voice, {
    CancelToken? cancelToken,
  }) async {
    try {
      return await primary.convert(text, voice, cancelToken: cancelToken);
    } catch (e) {
      if (_isCancel(e)) rethrow;
      return fallback.convert(text, voice, cancelToken: cancelToken);
    }
  }

  @override
  Future<TtsResult> convertWithTimestamps(
    String text,
    VoiceOption voice, {
    CancelToken? cancelToken,
  }) async {
    try {
      return await primary.convertWithTimestamps(text, voice, cancelToken: cancelToken);
    } catch (e) {
      if (_isCancel(e)) rethrow;
      return fallback.convertWithTimestamps(text, voice, cancelToken: cancelToken);
    }
  }

  @override
  Future<List<String>> getVoiceList() async {
    try {
      return await primary.getVoiceList();
    } catch (_) {
      return fallback.getVoiceList();
    }
  }
}
