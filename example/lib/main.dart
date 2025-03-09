import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:tts_engine/tts_engine.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter TTS Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final _textController = TextEditingController();
  final _engines = {
    'Edge TTS': 'edge',
    'Azure TTS': 'azure',
  };
  String _selectedEngine = 'edge';
  VoiceOption _selectedVoice = VoiceOption.zhFemale;
  bool _isConverting = false;
  bool _isPlaying = false;

  final Map<VoiceOption, String> _exampleTexts = {
    VoiceOption.zhFemale: '你好，这是一个文字转语音的示例。',
    VoiceOption.japaneseFemale: 'こんにちは、音声合成のデモへようこそ。',
    VoiceOption.englishFemale:
        'Hello! Welcome to our text-to-speech demo. Feel free to try out different voices and languages.',
    VoiceOption.spanishFemale:
        '¡Hola! Bienvenido al demo de texto a voz. Prueba libremente diferentes voces e idiomas.',
    VoiceOption.koreanFemale: '안녕하세요! 텍스트를 음성으로 변환하는 데모에 오신 것을 환영합니다. 다양한 음성과 언어를 테스트해 보세요.',
    VoiceOption.frenchFemale:
        'Bonjour! Bienvenue dans la démo de conversion texte en voix. Essayez différentes voix et langues.',
    VoiceOption.italianFemale:
        'Ciao! Benvenuto nel demo di conversione testo in voce. Sentiti libero di provare diverse voci e lingue.',
  };

  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  String? _audioPath;

  TtsEngine get _ttsEngine => createTtsEngine(provider: _selectedEngine);

  @override
  void initState() {
    super.initState();
    _initializePlayer();
    _textController.text = _exampleTexts[_selectedVoice]!;
  }

  Future<void> _initializePlayer() async {
    await _player.openPlayer();
    await _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      final status = await Permission.storage.request();
      if (status != PermissionStatus.granted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('需要存储权限来播放音频')),
        );
      }
    }
  }

  Future<void> _convertToSpeech() async {
    if (_isConverting) return;

    setState(() {
      _isConverting = true;
    });

    try {
      final engine = _ttsEngine;
      final audioData = await engine.convert(
        _textController.text,
        _selectedVoice,
      );

      // 保存音频数据到临时文件
      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/tts_audio.mp3';
      final file = File(tempPath);
      await file.writeAsBytes(audioData);

      setState(() {
        _audioPath = tempPath;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('转换成功！点击播放按钮收听。')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('转换失败：$e')),
      );
    } finally {
      setState(() {
        _isConverting = false;
      });
    }
  }

  Future<void> _playAudio() async {
    if (_audioPath == null) return;

    if (_isPlaying) {
      await _player.stopPlayer();
      setState(() {
        _isPlaying = false;
      });
    } else {
      try {
        await _player.startPlayer(
          fromURI: _audioPath,
          whenFinished: () {
            setState(() {
              _isPlaying = false;
            });
          },
        );
        setState(() {
          _isPlaying = true;
        });
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('播放失败：$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flutter TTS Demo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 引擎选择
            DropdownButtonFormField<String>(
              value: _selectedEngine,
              decoration: const InputDecoration(
                labelText: '选择 TTS 引擎',
                border: OutlineInputBorder(),
              ),
              items: _engines.entries
                  .map((e) => DropdownMenuItem(
                        value: e.value,
                        child: Text(e.key),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _selectedEngine = value;
                });
              },
            ),
            const SizedBox(height: 16),

            // 声音选择
            DropdownButtonFormField<VoiceOption>(
              value: _selectedVoice,
              decoration: const InputDecoration(
                labelText: '选择声音',
                border: OutlineInputBorder(),
              ),
              items: VoiceOption.values
                  .map((e) => DropdownMenuItem(
                        value: e,
                        child: Text(_getVoiceName(e)),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _selectedVoice = value;
                  _textController.text = _exampleTexts[value]!;
                });
              },
            ),
            const SizedBox(height: 16),

            // 文本输入
            TextField(
              controller: _textController,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: '输入要转换的文本',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // 按钮行
            Row(
              children: [
                // 转换按钮
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isConverting ? null : _convertToSpeech,
                    child: _isConverting
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 12),
                              Text('转换中...'),
                            ],
                          )
                        : const Text('转换为语音'),
                  ),
                ),
                const SizedBox(width: 16),
                // 播放按钮
                if (_audioPath != null)
                  ElevatedButton.icon(
                    onPressed: _playAudio,
                    icon: Icon(_isPlaying ? Icons.stop : Icons.play_arrow),
                    label: Text(_isPlaying ? '停止' : '播放'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _getVoiceName(VoiceOption voice) {
    switch (voice) {
      case VoiceOption.zhFemale:
        return '女声 - 中文';
      case VoiceOption.japaneseFemale:
        return '女声 - 日语';
      case VoiceOption.englishFemale:
        return '女声 - 英语';
      case VoiceOption.spanishFemale:
        return '女声 - 西班牙语';
      case VoiceOption.koreanFemale:
        return '女声 - 韩语';
      case VoiceOption.frenchFemale:
        return '女声 - 法语';
      case VoiceOption.italianFemale:
        return '女声 - 意大利语';
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _player.closePlayer();
    super.dispose();
  }
}
