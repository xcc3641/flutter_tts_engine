/// [INPUT]: 依赖 flutter, tts_demo_page.dart
/// [OUTPUT]: 应用入口
/// [POS]: example/lib/ 的根入口，只负责 MaterialApp 壳
/// [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md

import 'package:flutter/material.dart';

import 'tts_demo_page.dart';

void main() => runApp(const MyApp());

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
      home: const TtsDemoPage(),
    );
  }
}
