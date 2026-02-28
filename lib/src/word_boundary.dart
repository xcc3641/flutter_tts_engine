/**
 * [INPUT]: 无外部依赖
 * [OUTPUT]: 对外提供 WordBoundary 数据类
 * [POS]: src/ 的模型层，表示单个词的时间戳信息，被 TtsResult 消费
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

// ============================================================
// WordBoundary — 词级时间戳
// Microsoft TTS audio.metadata 中 WordBoundary 事件的 Dart 表示
// Offset/Duration 原始单位 100ns ticks，构造时转为 Duration
// ============================================================

class WordBoundary {
  /// 音频起始偏移（相对于合成开始）
  final Duration offset;

  /// 该词的朗读持续时长
  final Duration duration;

  /// 原文内容
  final String text;

  /// 在输入文本中的字符偏移
  final int textOffset;

  /// 词的字符长度
  final int wordLength;

  const WordBoundary({
    required this.offset,
    required this.duration,
    required this.text,
    required this.textOffset,
    required this.wordLength,
  });

  /// 从 Microsoft audio.metadata JSON 的单条 Metadata 数据构造
  /// Offset/Duration 单位: 100ns ticks → microseconds (÷ 10)
  factory WordBoundary.fromMetadata(Map<String, dynamic> data) {
    final offsetTicks = data['Offset'] as int;
    final durationTicks = data['Duration'] as int;
    final textData = data['text'] as Map<String, dynamic>;

    return WordBoundary(
      offset: Duration(microseconds: offsetTicks ~/ 10),
      duration: Duration(microseconds: durationTicks ~/ 10),
      text: textData['Text'] as String,
      textOffset: textData['Offset'] as int? ?? 0,
      wordLength: textData['Length'] as int? ?? 0,
    );
  }

  @override
  String toString() => 'WordBoundary('
      '${offset.inMilliseconds}ms '
      '+${duration.inMilliseconds}ms '
      '"$text")';
}
