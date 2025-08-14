import 'dart:convert';
import 'dart:developer';

void jsonDebugPrint(dynamic json) {
  var encoder = const JsonEncoder.withIndent('  ');

  log(encoder.convert(json));
}

void prettyJsonPrint(String tag, dynamic data) {
  if (data == null) {
    log('$tag: null');
    return;
  }

  if (data is String) {
    log('$tag:$data');
    return;
  }

  if (!(data is Map || data is List)) {
    log('$tag:$data');
    return;
  }

  // 这里需要实现具体的打印逻辑，例如使用jsonEncode将data转换为JSON字符串
  // 并进行格式化打印。以下是一个示例实现：
  var prettyJson = const JsonEncoder.withIndent('  ').convert(data);
  log('$tag:$prettyJson');
}
