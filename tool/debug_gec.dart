// ignore_for_file: avoid_print
// 临时调试脚本：打印 sec-ms-gec 计算值 + 服务器完整响应
import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

const _host = 'speech.platform.bing.com';
const _trustedToken = '6A5AA1D4EAFF4E9FB37E23D68491D6F4';
const _chromiumVersion = '130.0.2849.68';
const _secMsGecVersion = '1-$_chromiumVersion';

Future<void> main() async {
  final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
  var ticks = nowMs * 10000 + 116444736000000000;
  ticks -= ticks % 3000000000;
  final secMsGec = sha256.convert(utf8.encode('$ticks$_trustedToken')).toString().toUpperCase();

  print('nowMs:     $nowMs');
  print('ticks:     $ticks');
  print('hashInput: $ticks$_trustedToken');
  print('secMsGec:  $secMsGec');

  final requestId = _uuid();
  final wsKey = base64Encode(List<int>.generate(16, (_) => Random.secure().nextInt(256)));

  final path = '/consumer/speech/synthesize/readaloud/edge/v1'
      '?TrustedClientToken=$_trustedToken'
      '&Sec-MS-GEC=$secMsGec'
      '&Sec-MS-GEC-Version=$_secMsGecVersion'
      '&ConnectionId=$requestId';

  print('\nConnecting...');
  final socket = await SecureSocket.connect(_host, 443);
  print('TLS OK\n');

  final req = [
    'GET $path HTTP/1.1',
    'Host: $_host',
    'Upgrade: websocket',
    'Connection: Upgrade',
    'Sec-WebSocket-Key: $wsKey',
    'Sec-WebSocket-Version: 13',
    'Accept-Encoding: gzip, deflate, br',
    'Accept-Language: en-US,en;q=0.9',
    'Pragma: no-cache',
    'Cache-Control: no-cache',
    'Origin: chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold',
    'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/$_chromiumVersion Safari/537.36 Edg/$_chromiumVersion',
    'sec-ms-gec: $secMsGec',
    'sec-ms-gec-version: $_secMsGecVersion',
    '',
    '',
  ].join('\r\n');
  socket.add(utf8.encode(req));

  final buf = <int>[];
  await for (final chunk in socket) {
    buf.addAll(chunk);
    if (utf8.decode(buf, allowMalformed: true).contains('\r\n\r\n')) break;
  }
  final resp = utf8.decode(buf, allowMalformed: true);
  print('=== RESPONSE ===');
  print(resp);
  print('================');
  await socket.close();
}

String _uuid() {
  final rng = Random.secure();
  final b = List<int>.generate(16, (_) => rng.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String h(int v) => v.toRadixString(16).padLeft(2, '0');
  final s = b.map(h).toList();
  return '${s.sublist(0, 4).join()}-${s.sublist(4, 6).join()}-${s.sublist(6, 8).join()}-${s.sublist(8, 10).join()}-${s.sublist(10, 16).join()}';
}
