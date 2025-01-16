
import 'package:tts_engine/decorator/voice_cache_engine.dart';
import 'package:tts_engine/engine.dart';
import 'package:tts_engine/impl/azure.dart';
import 'package:tts_engine/impl/edge.dart';

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
