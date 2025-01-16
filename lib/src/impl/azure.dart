import 'package:dio/dio.dart';
import 'microsoft.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/io.dart';

class AzureTtsEngine extends MicrosoftTtsEngine {
  @override
  IOWebSocketChannel doConnect() {
    final uuid = const Uuid().v4();
    final url =
        "wss://eastus.api.speech.microsoft.com/cognitiveservices/websocket/v1?TricType=AzureDemo&X-ConnectionId=$uuid";
    final headers = {
      "Accept-Encoding": "gzip, deflate, br",
      // "Host": "eastus.tts.speech.microsoft.com",
      "Origin": "https://azure.microsoft.com",
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
            <mstts:express-as style="${options.style}" styledegree="${options.styleDegree}" role="${options.role}">
              <prosody rate="0%" pitch="0%">$text</prosody>
            </mstts:express-as>
          </voice>
        </speak>
    '''
        .trim();
    return ssml;
  }

  @override
  Future<List<String>> getVoiceList() async {
    final response = await Dio().get(
      "https://eastus.api.speech.microsoft.com/cognitiveservices/voices/list",
      options: Options(
        headers: {
          "User-Agent":
              "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/107.0.0.0 Safari/537.36 Edg/107.0.1418.26",
          "X-Ms-Useragent": "SpeechStudio/2021.05.001",
          "Content-Type": "application/json",
          "Origin": "https://azure.microsoft.com",
          "Referer": "https://azure.microsoft.com",
        },
      ),
    );

    final List<dynamic> array = response.data;

    return array.where((element) => element['Locale'] == 'zh-CN').map((e) => e['ShortName'] as String).toList();
  }
}
