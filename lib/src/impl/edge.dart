import 'package:dio/dio.dart';
import 'microsoft.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/io.dart';

class EdgeTtsEngine extends MicrosoftTtsEngine {
  @override
  IOWebSocketChannel doConnect() {
    final uuid = const Uuid().v4();
    final url =
        "wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1?TrustedClientToken=6A5AA1D4EAFF4E9FB37E23D68491D6F4&ConnectionId=$uuid";
    final headers = {
      "Accept-Encoding": "gzip, deflate, br",
      // "Host": "speech.platform.bing.com",
      "Origin": "chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold",
      "User-Agent":
          "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/103.0.5060.66 Safari/537.36 Edg/103.0.1264.44",
    };
    final channel = IOWebSocketChannel.connect(
      url,
      headers: headers,
      pingInterval: const Duration(seconds: 10),
      connectTimeout: const Duration(seconds: 3),
    );

    return channel;
  }

  @override
  String buildSSml(String text, MicrosoftVoiceOptions options) {
    final ssml = '''
        <speak xmlns="http://www.w3.org/2001/10/synthesis" xmlns:mstts="http://www.w3.org/2001/mstts" xmlns:emo="http://www.w3.org/2009/10/emotionml" version="1.0" xml:lang="en-US">
          <voice name="${options.voice}">
              <prosody rate="0%" pitch="0%">$text</prosody>
          </voice>
        </speak>
    '''
        .trim();
    return ssml;
  }

  @override
  Future<List<String>> getVoiceList() async {
    final response = await Dio().get(
        "https://speech.platform.bing.com/consumer/speech/synthesize/readaloud/voices/list?trustedclienttoken=6A5AA1D4EAFF4E9FB37E23D68491D6F4");

    final List<dynamic> array = response.data;
    return array.where((element) => element['Locale'] == 'zh-CN').map((e) => e['ShortName'] as String).toList();
  }
}
