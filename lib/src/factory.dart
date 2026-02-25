/**
 * [INPUT]: 依赖 decorator/voice_cache_engine, engine, impl/azure
 * [OUTPUT]: 对外提供 createTtsEngine 工厂函数
 * [POS]: src/ 的入口工厂，封装引擎创建与缓存装饰
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import 'decorator/voice_cache_engine.dart';
import 'engine.dart';
import 'impl/azure.dart';

TtsEngine createTtsEngine() {
  return VoiceCacheEngine(delegate: AzureTtsEngine());
}
