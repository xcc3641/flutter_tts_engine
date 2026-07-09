/**
 * [INPUT]: 依赖 decorator/voice_cache_engine, decorator/fallback, engine, impl/azure, impl/worker
 * [OUTPUT]: 对外提供 createTtsEngine 工厂函数
 * [POS]: src/ 的入口工厂，封装引擎创建与缓存装饰
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import 'decorator/fallback.dart';
import 'decorator/voice_cache_engine.dart';
import 'engine.dart';
import 'impl/azure.dart';
import 'impl/worker.dart';

/// 构建默认 TTS 引擎栈。
///
/// [workerUrl] 为空（默认）→ 纯 demo 端点白嫖，等价于历史行为，无参调用不破坏。
///
/// [workerUrl] 非空 → 叠 fallback 栈：
///   VoiceCacheEngine
///     └ FallbackTtsEngine
///         ├ primary  : WorkerTtsEngine  (后端持真 Azure key，快、有免费额度)
///         └ fallback : AzureTtsEngine   (demo 端点白嫖，兜底 + 承载 KTV 词级时间戳)
///
/// [headers] 附加请求头（如 `{ 'x-kachika-token': '...' }`），鉴权由调用方注入，
/// 库不硬编码任何业务端点/凭据。
TtsEngine createTtsEngine({
  String? workerUrl,
  Map<String, String> headers = const {},
}) {
  final fallback = AzureTtsEngine();
  if (workerUrl == null) {
    return VoiceCacheEngine(delegate: fallback);
  }
  return VoiceCacheEngine(
    delegate: FallbackTtsEngine(
      primary: WorkerTtsEngine(endpoint: workerUrl, headers: headers),
      fallback: fallback,
    ),
  );
}
