import 'dart:async';
import 'dart:convert';
import 'dart:developer';

// 删除了 'dart:io'，引入了 'package:http'
import 'package:http/http.dart' as http;
import 'package:tiny_ai/src/utils/pretty.dart';
import 'config.dart';

class HttpService {
  static HttpService? _instance;
  final Duration _timeout;

  HttpService._internal() : _timeout = TinyAIConfig.instance.timeout;

  static HttpService get instance {
    _instance ??= HttpService._internal();
    return _instance!;
  }

  /// 普通 POST（返回完整响应）- 已更新为 package:http
  Future<Map<String, dynamic>> post(String url, {required Map<String, dynamic> data, Map<String, String>? headers}) async {
    final uri = Uri.parse(url);
    final requestBody = jsonEncode(data);

    // 准备 Headers
    final requestHeaders = {
      'Content-Type': 'application/json; charset=utf-8',
      ...?headers, // 将用户自定义 headers 合并进来
    };

    if (TinyAIConfig.instance.enableLogging) {
      log('[HTTP] POST $uri');
      log('[HTTP] Headers: $requestHeaders');
      prettyJsonPrint('[HTTP] Data', data);
    }

    try {
      final response = await http.post(uri, headers: requestHeaders, body: requestBody).timeout(_timeout); // 为请求添加超时

      // 使用 response.bodyBytes 并用 utf8解码，可以避免中文乱码问题
      final responseBody = utf8.decode(response.bodyBytes);

      if (TinyAIConfig.instance.enableLogging) {
        log('[HTTP] Response: ${response.statusCode}');
        prettyJsonPrint('[HTTP] Data', jsonDecode(responseBody));
      }

      if (response.statusCode != 200) {
        // 尝试从响应体中解析错误信息
        final errorJson = jsonDecode(responseBody);
        final errorMessage = errorJson['error']?['message'] ?? response.reasonPhrase;
        throw HttpException('HTTP ${response.statusCode} $errorMessage', uri: uri);
      }

      return jsonDecode(responseBody) as Map<String, dynamic>;
    } on TimeoutException {
      throw TimeoutException('Request to $uri timed out after $_timeout', _timeout);
    } catch (e) {
      // 重新抛出，以便上层可以捕获
      rethrow;
    }
  }

  /// 流式 POST（SSE）- 已更新为 package:http
  Stream<String> postStream(String url, {required Map<String, dynamic> data, Map<String, String>? headers}) {
    final uri = Uri.parse(url);
    final requestBody = jsonEncode(data);
    final client = http.Client();
    final streamController = StreamController<String>();

    // 准备 Headers
    final requestHeaders = {
      'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'text/event-stream', // SSE 最好显式声明
      ...?headers,
    };

    final request = http.Request('POST', uri)
      ..headers.addAll(requestHeaders)
      ..body = requestBody;

    if (TinyAIConfig.instance.enableLogging) {
      log('[HTTP] STREAM POST $uri');
      log('[HTTP] Headers: ${request.headers}');
      prettyJsonPrint('[HTTP] Data', data);
    }

    Future<void> forwardStream() async {
      try {
        final response = await client.send(request).timeout(_timeout);

        if (response.statusCode != 200) {
          final body = await response.stream.bytesToString();
          streamController.addError(HttpException('HTTP ${response.statusCode} $body', uri: uri));
          return;
        }

        // 流式读取 UTF8 + 按行切分 (这部分逻辑和你原来的一样)
        response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(streamController.add, onError: streamController.addError, onDone: streamController.close);
      } on TimeoutException {
        streamController.addError(TimeoutException('Request to $uri timed out', _timeout));
      } catch (e) {
        streamController.addError(e);
      }
    }

    // 当 Stream 被监听时，开始请求
    streamController.onListen = () {
      forwardStream();
    };

    // 当监听取消时，关闭 client
    streamController.onCancel = () {
      client.close();
    };

    return streamController.stream;
  }
}

// package:http 没有 HttpException，我们可以自己定义一个简单的，或者直接用 Exception
class HttpException implements Exception {
  final String message;
  final Uri? uri;

  HttpException(this.message, {this.uri});

  @override
  String toString() => 'HttpException: $message ${uri != null ? ', uri=$uri' : ''}';
}
