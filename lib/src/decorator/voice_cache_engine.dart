/**
 * [INPUT]: 依赖 engine.dart 的 TtsEngine，依赖 tts_result/voice_option
 * [OUTPUT]: 对外提供 VoiceCacheEngine 缓存装饰器
 * [POS]: decorator/ 的核心，代理 voice list 请求并缓存结果
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import 'dart:typed_data';

import 'package:dio/dio.dart';
import '../engine.dart';
import '../tts_result.dart';
import '../voice_option.dart';

class VoiceCacheEngine extends TtsEngine {
  final TtsEngine delegate;

  static final List<String> _cache = [];

  VoiceCacheEngine({required this.delegate});

  @override
  Future<Uint8List> convert(
    String text,
    VoiceOption voice, {
    CancelToken? cancelToken,
  }) {
    return delegate.convert(text, voice, cancelToken: cancelToken);
  }

  @override
  Future<TtsResult> convertWithTimestamps(
    String text,
    VoiceOption voice, {
    CancelToken? cancelToken,
  }) {
    return delegate.convertWithTimestamps(text, voice, cancelToken: cancelToken);
  }

  @override
  Future<List<String>> getVoiceList() async {
    if (_cache.isNotEmpty) return _cache;
    final data = await delegate.getVoiceList();
    _cache.clear();
    _cache.addAll(data);
    return _cache;
  }
}
