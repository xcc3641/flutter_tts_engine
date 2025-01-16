import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:tts_engine/flutter_tts_engine.dart';


abstract class TtsEngine {
  Future<Uint8List> convert(String text, VoiceOption voice, {CancelToken? cancelToken,});

  Future<List<String>> getVoiceList();
}
