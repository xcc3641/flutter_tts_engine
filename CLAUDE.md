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
                             顶层 microsoftVoiceOptionsFor(VoiceOption) 供各实现共用 voice 映射；
                             兼管 WebSocket 生命周期：await ready 把惰性连接失败（403/超时）抛在
                             被 await 处、addStream 的 Future 就地消化、turn.end 与发送串行化、
                             finally 释放连接、cancelToken 透传并抛 DioException(cancel)。
                             铁律：不允许任何 Future 携带未处理错误逃到根 zone。
                             空音频**不算错误**：demo 端点对纯空白/纯标点会握手成功、0 帧、正常结束
                             （实测 '   ' → 0 帧 / 1.2s）。要不要拒绝 0 字节由消费方的缓存语义决定
      azure.dart           - AzureTtsEngine，demo 端点白嫖实现；顶层 buildAzureSsml() 共用 SSML 构建
      worker.dart          - WorkerTtsEngine，把合成卸载到后端(持真 Azure key)；纯音频，
                             convertWithTimestamps 抛 UnsupportedError（REST 无词级时间戳）
    decorator/
      voice_cache_engine.dart - 缓存装饰器，代理 voice list 请求
      fallback.dart        - FallbackTtsEngine，primary 抛错/超时落 fallback；
                             KTV 词级时间戳因 primary(Worker) 不支持而天然落 fallback(demo WS)

example/                   - Flutter 示例应用
test/
  microsoft_engine_test.dart - MicrosoftTtsEngine 失败路径回归：本地 HttpServer / 静默 TCP 端口造
                               403、connectTimeout 超时、断链、turn.end 竞态、取消；
                               核心断言是 runZonedGuarded onError 零调用（观察窗靠泵 microtask，不 sleep）
tool/
  batch_test.dart          - Edge TTS 批量声音测试脚本
  debug_gec.dart           - SEC-MS-GEC 调试工具
```

[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
