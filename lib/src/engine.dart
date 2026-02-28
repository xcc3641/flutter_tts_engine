/**
 * [INPUT]: 依赖 dio 的 CancelToken，依赖 tts_result/word_boundary/voice_option
 * [OUTPUT]: 对外提供 TtsEngine 抽象基类
 * [POS]: src/ 的核心接口，定义 convert / convertWithTimestamps / getVoiceList
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'tts_result.dart';
import 'voice_option.dart';

abstract class TtsEngine {
  /// 纯音频合成
  Future<Uint8List> convert(String text, VoiceOption voice, {CancelToken? cancelToken});

  /// 音频 + 词级时间戳合成
  Future<TtsResult> convertWithTimestamps(String text, VoiceOption voice, {CancelToken? cancelToken});

  Future<List<String>> getVoiceList();
}
