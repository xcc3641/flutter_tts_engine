import 'decorator/voice_cache_engine.dart';
import 'engine.dart';
import 'impl/azure.dart';
import 'impl/edge.dart';

TtsEngine createTtsEngine({String? provider}) {
  final TtsEngine engine;
  switch (provider) {
    case 'azure':
      engine = AzureTtsEngine();
      break;
    case 'edge':
      engine = EdgeTtsEngine();
      break;
    default:
      engine = EdgeTtsEngine();
      break;
  }

  return VoiceCacheEngine(delegate: engine);
}
