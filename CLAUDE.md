# tts_engine - Azure TTS Flutter Package
Dart + Flutter + WebSocket + Dio

## Architecture

```
lib/
  tts_engine.dart          - Barrel export (engine, factory, voice_option)
  src/
    engine.dart            - TtsEngine 抽象基类 (convert, getVoiceList)
    factory.dart           - createTtsEngine() 工厂，返回 VoiceCacheEngine 包装的 AzureTtsEngine
    voice_option.dart      - VoiceOption enum (7 语言 × 男女声)
    impl/
      microsoft.dart       - MicrosoftTtsEngine 抽象基类，WebSocket 协议 + SSML 构建 + voice mapping
      azure.dart           - AzureTtsEngine，Azure Cognitive Services 端点实现
    decorator/
      voice_cache_engine.dart - 缓存装饰器，代理 voice list 请求

example/                   - Flutter 示例应用
```

[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
