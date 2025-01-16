import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:tts_engine/engine.dart';
import 'package:tts_engine/voice_option.dart';


class VoiceCacheEngine extends TtsEngine {
  final TtsEngine delegate;

  static final List<String> _cache = [];

  VoiceCacheEngine({required this.delegate});

  @override
  Future<Uint8List> convert(String text, VoiceOption voice, {CancelToken? cancelToken,}) {
    return delegate.convert(text, voice, cancelToken: cancelToken);
  }

  @override
  Future<List<String>> getVoiceList() async {
    if (_cache.isNotEmpty) return _cache;
    final data = await delegate.getVoiceList();
    _cache.clear();
    _cache.addAll(data);
    return _cache;
  }
}
