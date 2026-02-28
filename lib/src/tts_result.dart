/**
 * [INPUT]: 依赖 dart:typed_data 的 Uint8List，依赖 word_boundary.dart 的 WordBoundary
 * [OUTPUT]: 对外提供 TtsResult 数据类
 * [POS]: src/ 的模型层，convertWithTimestamps 的返回类型，聚合音频与时间戳
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import 'dart:typed_data';

import 'word_boundary.dart';

// ============================================================
// TtsResult — 合成结果 (音频 + 词级时间戳)
// ============================================================

class TtsResult {
  /// 合成的音频数据 (MP3)
  final Uint8List audioBytes;

  /// 词级时间戳列表，按 offset 递增排列
  final List<WordBoundary> boundaries;

  const TtsResult({
    required this.audioBytes,
    required this.boundaries,
  });

  @override
  String toString() => 'TtsResult(${audioBytes.length} bytes, ${boundaries.length} boundaries)';
}
