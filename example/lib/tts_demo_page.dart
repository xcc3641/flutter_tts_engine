/// [INPUT]: 依赖 tts_engine (createTtsEngine, VoiceOption, TtsResult, WordBoundary)
///          依赖 flutter_sound, path_provider, permission_handler
///          依赖 voice_data.dart 的 exampleTexts / voiceDisplayName
/// [OUTPUT]: 对外提供 TtsDemoPage widget
/// [POS]: example/lib/ 的页面层，TTS 演示主页面，含合成 + 播放 + 时间戳展示
/// [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md

import 'dart:io';

import 'package:flutter/material.dart' hide WordBoundary;
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:tts_engine/tts_engine.dart';

import 'voice_data.dart';

// ============================================================
// TtsDemoPage — TTS 演示主界面
// ============================================================

class TtsDemoPage extends StatefulWidget {
  const TtsDemoPage({super.key});

  @override
  State<TtsDemoPage> createState() => _TtsDemoPageState();
}

class _TtsDemoPageState extends State<TtsDemoPage> {
  final _textController = TextEditingController();
  final _player = FlutterSoundPlayer();

  VoiceOption _selectedVoice = VoiceOption.zhFemale;
  bool _isConverting = false;
  bool _isPlaying = false;
  String? _audioPath;
  List<WordBoundary> _boundaries = [];

  TtsEngine get _engine => createTtsEngine();

  // -------- Lifecycle --------

  @override
  void initState() {
    super.initState();
    _initPlayer();
    _textController.text = exampleTexts[_selectedVoice]!;
  }

  @override
  void dispose() {
    _textController.dispose();
    _player.closePlayer();
    super.dispose();
  }

  Future<void> _initPlayer() async {
    await _player.openPlayer();
    if (Platform.isAndroid) {
      final status = await Permission.storage.request();
      if (!mounted || status.isGranted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('需要存储权限来播放音频')),
      );
    }
  }

  // -------- 合成 (使用 convertWithTimestamps) --------

  Future<void> _convert() async {
    if (_isConverting) return;
    setState(() => _isConverting = true);

    try {
      final result = await _engine.convertWithTimestamps(
        _textController.text,
        _selectedVoice,
      );

      final tempDir = await getTemporaryDirectory();
      final path = '${tempDir.path}/tts_audio.mp3';
      await File(path).writeAsBytes(result.audioBytes);

      setState(() {
        _audioPath = path;
        _boundaries = result.boundaries;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('转换成功！${result.boundaries.length} 个词边界')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('转换失败：$e')),
      );
    } finally {
      setState(() => _isConverting = false);
    }
  }

  // -------- 播放 --------

  Future<void> _togglePlay() async {
    if (_audioPath == null) return;

    if (_isPlaying) {
      await _player.stopPlayer();
      setState(() => _isPlaying = false);
    } else {
      try {
        await _player.startPlayer(
          fromURI: _audioPath,
          whenFinished: () => setState(() => _isPlaying = false),
        );
        setState(() => _isPlaying = true);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('播放失败：$e')),
        );
      }
    }
  }

  // -------- UI --------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flutter TTS Demo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildVoiceSelector(),
            const SizedBox(height: 16),
            _buildTextInput(),
            const SizedBox(height: 16),
            _buildActionRow(),
            const SizedBox(height: 16),
            if (_boundaries.isNotEmpty) Expanded(child: _buildBoundaryList()),
          ],
        ),
      ),
    );
  }

  // -------- 子组件 --------

  Widget _buildVoiceSelector() {
    return DropdownButtonFormField<VoiceOption>(
      initialValue: _selectedVoice,
      decoration: const InputDecoration(
        labelText: '选择声音',
        border: OutlineInputBorder(),
      ),
      items: VoiceOption.values.map((v) => DropdownMenuItem(value: v, child: Text(voiceDisplayName(v)))).toList(),
      onChanged: (v) {
        if (v == null) return;
        setState(() {
          _selectedVoice = v;
          _textController.text = exampleTexts[v]!;
          _boundaries = [];
        });
      },
    );
  }

  Widget _buildTextInput() {
    return TextField(
      controller: _textController,
      maxLines: 5,
      decoration: const InputDecoration(
        labelText: '输入要转换的文本',
        border: OutlineInputBorder(),
      ),
    );
  }

  Widget _buildActionRow() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: _isConverting ? null : _convert,
            child: _isConverting
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 12),
                      Text('转换中...'),
                    ],
                  )
                : const Text('转换为语音'),
          ),
        ),
        if (_audioPath != null) ...[
          const SizedBox(width: 16),
          ElevatedButton.icon(
            onPressed: _togglePlay,
            icon: Icon(_isPlaying ? Icons.stop : Icons.play_arrow),
            label: Text(_isPlaying ? '停止' : '播放'),
          ),
        ],
      ],
    );
  }

  /// 词级时间戳列表
  Widget _buildBoundaryList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '词级时间戳 (${_boundaries.length})',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: _boundaries.length,
            itemBuilder: (_, i) {
              final b = _boundaries[i];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '${b.offset.inMilliseconds}ms  +${b.duration.inMilliseconds}ms  "${b.text}"',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
