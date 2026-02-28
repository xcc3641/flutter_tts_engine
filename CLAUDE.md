# tts_engine - Azure TTS Flutter Package
Dart + Flutter + WebSocket + Dio

## Architecture

```
lib/
  tts_engine.dart          - Barrel export (engine, factory, voice_option, tts_result, word_boundary)
  src/
    engine.dart            - TtsEngine 抽象基类 (convert, convertWithTimestamps, getVoiceList)
    factory.dart           - createTtsEngine() 工厂，返回 VoiceCacheEngine 包装的 AzureTtsEngine
    tts_result.dart        - TtsResult 数据类 (audioBytes + boundaries)
    voice_option.dart      - VoiceOption enum (7 语言 × 男女声)
    word_boundary.dart     - WordBoundary 数据类 (offset, duration, text, textOffset, wordLength)
    impl/
      microsoft.dart       - MicrosoftTtsEngine 抽象基类，WebSocket 协议 + SSML + WordBoundary 解析
      azure.dart           - AzureTtsEngine，Azure Cognitive Services 端点实现
    decorator/
      voice_cache_engine.dart - 缓存装饰器，代理 voice list 请求

example/                   - Flutter 示例应用
tool/
  batch_test.dart          - Edge TTS 批量声音测试脚本
  debug_gec.dart           - SEC-MS-GEC 调试工具
```

[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
