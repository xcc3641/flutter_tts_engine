// [INPUT]: 依赖 tts_engine 的 VoiceOption
// [OUTPUT]: 对外提供 exampleTexts 和 voiceDisplayName
// [POS]: example/lib/ 的静态数据层，存放声音示例文本与显示名称
// [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md

import 'package:tts_engine/tts_engine.dart';

// ============================================================
// 示例文本 — 每种声音对应的默认文本
// ============================================================

const exampleTexts = <VoiceOption, String>{
  // -------- 女声 --------
  VoiceOption.zhFemale: '你好，这是一个文字转语音的示例。',
  VoiceOption.japaneseFemale: 'こんにちは、音声合成のデモへようこそ。',
  VoiceOption.englishFemale:
      'Hello! Welcome to our text-to-speech demo. Feel free to try out different voices and languages.',
  VoiceOption.spanishFemale: '¡Hola! Bienvenido al demo de texto a voz. Prueba libremente diferentes voces e idiomas.',
  VoiceOption.koreanFemale: '안녕하세요! 텍스트를 음성으로 변환하는 데모에 오신 것을 환영합니다. 다양한 음성과 언어를 테스트해 보세요.',
  VoiceOption.frenchFemale:
      'Bonjour! Bienvenue dans la démo de conversion texte en voix. Essayez différentes voix et langues.',
  VoiceOption.italianFemale:
      'Ciao! Benvenuto nel demo di conversione testo in voce. Sentiti libero di provare diverse voci e lingue.',
  // -------- 男声 --------
  VoiceOption.zhMale: '你好，这是一个文字转语音的示例。',
  VoiceOption.japaneseMale: 'こんにちは、音声合成のデモへようこそ。',
  VoiceOption.englishMale:
      'Hello! Welcome to our text-to-speech demo. Feel free to try out different voices and languages.',
  VoiceOption.spanishMale: '¡Hola! Bienvenido al demo de texto a voz. Prueba libremente diferentes voces e idiomas.',
  VoiceOption.koreanMale: '안녕하세요! 텍스트를 음성으로 변환하는 데모에 오신 것을 환영합니다. 다양한 음성과 언어를 테스트해 보세요.',
  VoiceOption.frenchMale:
      'Bonjour! Bienvenue dans la démo de conversion texte en voix. Essayez différentes voix et langues.',
  VoiceOption.italianMale:
      'Ciao! Benvenuto nel demo di conversione testo in voce. Sentiti libero di provare diverse voci e lingue.',
};

// ============================================================
// 声音显示名称
// ============================================================

String voiceDisplayName(VoiceOption voice) => switch (voice) {
      VoiceOption.zhFemale => '女声 - 中文',
      VoiceOption.japaneseFemale => '女声 - 日语',
      VoiceOption.englishFemale => '女声 - 英语',
      VoiceOption.spanishFemale => '女声 - 西班牙语',
      VoiceOption.koreanFemale => '女声 - 韩语',
      VoiceOption.frenchFemale => '女声 - 法语',
      VoiceOption.italianFemale => '女声 - 意大利语',
      VoiceOption.zhMale => '男声 - 中文',
      VoiceOption.japaneseMale => '男声 - 日语',
      VoiceOption.englishMale => '男声 - 英语',
      VoiceOption.spanishMale => '男声 - 西班牙语',
      VoiceOption.koreanMale => '男声 - 韩语',
      VoiceOption.frenchMale => '男声 - 法语',
      VoiceOption.italianMale => '男声 - 意大利语',
    };
