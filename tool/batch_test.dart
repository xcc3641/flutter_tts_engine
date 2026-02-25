// ignore_for_file: avoid_print
// [POS]: 独立批量测试脚本，验证所有 Edge TTS 声音可用性
// [INPUT]: 依赖 package:crypto 的 sha256，dart:io HttpClient + detachSocket
// [OUTPUT]: tool/output/{voice}.mp3，每个声音生成一个音频文件
// 用法: dart run tool/batch_test.dart
// [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md

import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

// ============================================================
// 测试用例：声音名 → 测试文本
// ============================================================
const _voices = <(String, String)>[
  // -------- 女声 --------
  ('zh-CN-XiaoxiaoNeural', '你好，这是一个文字转语音的示例。'),
  ('ja-JP-NanamiNeural', 'こんにちは、音声合成のデモへようこそ。'),
  ('en-US-EmmaNeural', 'Hello! Welcome to our text-to-speech demo.'),
  ('es-ES-ElviraNeural', '¡Hola! Bienvenido al demo de texto a voz.'),
  ('ko-KR-SunHiNeural', '안녕하세요! 텍스트를 음성으로 변환하는 데모입니다.'),
  ('fr-FR-DeniseNeural', 'Bonjour! Bienvenue dans la démo de conversion texte en voix.'),
  ('it-IT-ElsaNeural', 'Ciao! Benvenuto nel demo di conversione testo in voce.'),
  // -------- 男声 --------
  ('zh-CN-YunxiNeural', '你好，这是一个文字转语音的示例。'),
  ('ja-JP-KeitaNeural', 'こんにちは、音声合成のデモへようこそ。'),
  ('en-US-BrianNeural', 'Hello! Welcome to our text-to-speech demo.'),
  ('es-ES-AlvaroNeural', '¡Hola! Bienvenido al demo de texto a voz.'),
  ('ko-KR-InJoonNeural', '안녕하세요! 텍스트를 음성으로 변환하는 데모입니다.'),
  ('fr-FR-HenriNeural', 'Bonjour! Bienvenue dans la démo de conversion texte en voix.'),
  ('it-IT-DiegoNeural', 'Ciao! Benvenuto nel demo di conversione testo in voce.'),
];

// ============================================================
// 主入口
// ============================================================
Future<void> main() async {
  final outputDir = Directory('tool/output');
  if (!outputDir.existsSync()) outputDir.createSync(recursive: true);

  print('Edge TTS 批量测试 — 共 ${_voices.length} 个声音\n');

  var success = 0;
  var failure = 0;

  for (final (voice, text) in _voices) {
    stdout.write('  → $voice ... ');
    try {
      final bytes = await _synthesize(voice, text);
      final fileName = '${voice.replaceAll('-', '_')}.mp3';
      await File('tool/output/$fileName').writeAsBytes(bytes);
      print('✓  (${bytes.length} bytes)');
      success++;
    } catch (e) {
      print('✗  $e');
      failure++;
    }
  }

  print('\n完成：$success 成功 / $failure 失败');
  print('音频文件位于 tool/output/');
}

// ============================================================
// Edge TTS 合成
// 流程：HttpClient GET (Upgrade:websocket) → 101 → detachSocket → WebSocket
// HttpClient 负责读 HTTP header，detachSocket 后拿到干净的 WS 层 socket
// ============================================================
const _host = 'speech.platform.bing.com';
const _trustedToken = '6A5AA1D4EAFF4E9FB37E23D68491D6F4';
const _chromiumVersion = '143.0.3650.75';
const _secMsGecVersion = '1-$_chromiumVersion';

Future<Uint8List> _synthesize(String voice, String text) async {
  final requestId = _uuid();
  final wsKey = base64Encode(List<int>.generate(16, (_) => Random.secure().nextInt(256)));
  final secMsGec = _computeSecMsGec(_trustedToken);

  final uri = Uri.https(_host, '/consumer/speech/synthesize/readaloud/edge/v1', {
    'TrustedClientToken': _trustedToken,
    'Sec-MS-GEC': secMsGec,
    'Sec-MS-GEC-Version': _secMsGecVersion,
    'ConnectionId': requestId,
  });

  final client = HttpClient();
  final request = await client.openUrl('GET', uri);

  // WebSocket 升级 headers
  request.headers
    ..set(HttpHeaders.upgradeHeader, 'websocket')
    ..set(HttpHeaders.connectionHeader, 'Upgrade')
    ..set('Sec-WebSocket-Key', wsKey)
    ..set('Sec-WebSocket-Version', '13')
    ..set(HttpHeaders.acceptEncodingHeader, 'gzip, deflate, br')
    ..set('Accept-Language', 'en-US,en;q=0.9')
    ..set('Pragma', 'no-cache')
    ..set(HttpHeaders.cacheControlHeader, 'no-cache')
    ..set('Origin', 'chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold')
    ..set(HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/$_chromiumVersion Safari/537.36 Edg/$_chromiumVersion')
    ..set('sec-ms-gec', secMsGec)
    ..set('sec-ms-gec-version', _secMsGecVersion);

  final response = await request.close();

  if (response.statusCode != 101) {
    final body = await response.transform(utf8.decoder).join();
    client.close();
    throw Exception('WebSocket upgrade failed: HTTP ${response.statusCode} $body');
  }

  // detachSocket：HttpClient 已读完 HTTP header，socket 现在在 WebSocket 协议层
  final socket = await response.detachSocket();
  final ws = WebSocket.fromUpgradedSocket(socket, serverSide: false);

  ws.add(_buildConfigMessage(requestId));
  ws.add(_buildSsmlMessage(requestId, voice, text));

  final chunks = <int>[];
  await for (final data in ws) {
    final msg = _parseMessage(data);
    if (msg == null) continue;
    switch (msg.path) {
      case 'audio':
        chunks.addAll(msg.audioBytes ?? []);
      case 'turn.end':
        await ws.close();
        break;
    }
  }

  client.close();
  if (chunks.isEmpty) throw Exception('no audio data received');
  return Uint8List.fromList(chunks);
}

// ============================================================
// sec-ms-gec: SHA256(windowsTicks + trustedToken).toUpperCase()
// ticks = 100ns 间隔自 1601-01-01，对齐到 300s（5分钟）边界
// 300s = 300 × 10^7 = 3,000,000,000 ticks
// ============================================================
String _computeSecMsGec(String trustedToken) {
  final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
  var ticks = nowMs * 10000 + 116444736000000000;
  ticks -= ticks % 3000000000; // 5分钟对齐
  return sha256.convert(utf8.encode('$ticks$trustedToken')).toString().toUpperCase();
}

// ============================================================
// 消息构建
// ============================================================
String _buildConfigMessage(String requestId) {
  final ts = DateTime.now().toUtc().toIso8601String();
  final body = jsonEncode({
    'context': {
      'synthesis': {
        'audio': {
          'metadataOptions': {
            'sentenceBoundaryEnabled': false,
            'wordBoundaryEnabled': false,
          },
          'outputFormat': 'audio-24khz-48kbitrate-mono-mp3',
        }
      }
    }
  });
  return [
    'X-Timestamp:$ts',
    'X-RequestId:$requestId',
    'Content-Type:application/json',
    'Path:speech.config',
    '',
    body,
  ].join('\r\n');
}

String _buildSsmlMessage(String requestId, String voice, String text) {
  final ts = DateTime.now().toUtc().toIso8601String();
  final ssml = '<speak xmlns="http://www.w3.org/2001/10/synthesis" '
      'xmlns:mstts="http://www.w3.org/2001/mstts" version="1.0" xml:lang="en-US">'
      '<voice name="$voice">'
      '<prosody rate="0%" pitch="0%">$text</prosody>'
      '</voice></speak>';
  return [
    'X-Timestamp:$ts',
    'X-RequestId:$requestId',
    'Content-Type:application/ssml+xml',
    'Path:ssml',
    '',
    ssml,
  ].join('\r\n');
}

// ============================================================
// 消息解析
// ============================================================
class _Msg {
  final String path;
  final List<int>? audioBytes;
  _Msg(this.path, {this.audioBytes});
}

_Msg? _parseMessage(dynamic data) {
  try {
    if (data is String) return _Msg(_extractPath(data) ?? '');
    if (data is List<int>) return _parseBinaryMessage(Uint8List.fromList(data));
  } catch (_) {}
  return null;
}

// 二进制格式：[2字节头长度][头文本][音频数据]
_Msg? _parseBinaryMessage(Uint8List data) {
  if (data.length < 2) return null;
  final headerLen = (data[0] << 8) | data[1];
  if (data.length < 2 + headerLen) return null;

  final header = utf8.decode(data.sublist(2, 2 + headerLen));
  if (_extractPath(header) != 'audio') return null;

  return _Msg('audio', audioBytes: data.sublist(2 + headerLen));
}

String? _extractPath(String text) =>
    RegExp(r'Path:(\S+)').firstMatch(text)?.group(1);

// ============================================================
// UUID v4（纯 dart:math）
// ============================================================
String _uuid() {
  final rng = Random.secure();
  final b = List<int>.generate(16, (_) => rng.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String h(int v) => v.toRadixString(16).padLeft(2, '0');
  final s = b.map(h).toList();
  return '${s.sublist(0, 4).join()}-${s.sublist(4, 6).join()}'
      '-${s.sublist(6, 8).join()}-${s.sublist(8, 10).join()}'
      '-${s.sublist(10, 16).join()}';
}
