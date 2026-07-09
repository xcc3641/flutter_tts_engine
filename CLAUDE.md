# tts_engine - Azure TTS Flutter Package
Dart + Flutter + WebSocket + Dio

## Architecture

```
lib/
  tts_engine.dart          - Barrel export (engine, factory, voice_option, tts_result, word_boundary)
  src/
    engine.dart            - TtsEngine 抽象基类 (convert, convertWithTimestamps, getVoiceList)
    factory.dart           - createTtsEngine({workerUrl?, headers}) 工厂：
                             workerUrl 空 → VoiceCacheEngine(AzureTtsEngine)（纯 demo，历史行为）；
                             非空 → VoiceCacheEngine(FallbackTtsEngine(primary: WorkerTtsEngine, fallback: AzureTtsEngine))
    tts_result.dart        - TtsResult 数据类 (audioBytes + boundaries)
    voice_option.dart      - VoiceOption enum (7 语言 × 男女声)
    word_boundary.dart     - WordBoundary 数据类 (offset, duration, text, textOffset, wordLength)
    impl/
      microsoft.dart       - MicrosoftTtsEngine 抽象基类，WebSocket 协议 + SSML + WordBoundary 解析；
                             顶层 microsoftVoiceOptionsFor(VoiceOption) 供各实现共用 voice 映射
      azure.dart           - AzureTtsEngine，demo 端点白嫖实现；顶层 buildAzureSsml() 共用 SSML 构建
      worker.dart          - WorkerTtsEngine，把合成卸载到后端(持真 Azure key)；纯音频，
                             convertWithTimestamps 抛 UnsupportedError（REST 无词级时间戳）
    decorator/
      voice_cache_engine.dart - 缓存装饰器，代理 voice list 请求
      fallback.dart        - FallbackTtsEngine，primary 抛错/超时落 fallback；
                             KTV 词级时间戳因 primary(Worker) 不支持而天然落 fallback(demo WS)

example/                   - Flutter 示例应用
tool/
  batch_test.dart          - Edge TTS 批量声音测试脚本
  debug_gec.dart           - SEC-MS-GEC 调试工具
```

[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
