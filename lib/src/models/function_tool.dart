import 'dart:convert';
import 'dart:developer';

abstract class FunctionTool {
  String get name;
  String get description;
  Map<String, dynamic> get parameters;

  String? title;
  Map<String, dynamic> withProprty = {};

  /// 工具处理器 - 子类必须实现
  Future<String> handler(Map<String, dynamic> arguments);

  Map<String, dynamic> toJson() => {
    'type': 'function',
    'function': {'name': name, 'description': description, 'parameters': parameters},
  };
}

// 示例工具实现
class WeatherTool extends FunctionTool {
  @override
  String get name => 'get_weather';

  @override
  String get description => '获取指定城市的天气信息';

  @override
  Map<String, dynamic> get parameters => {
    'type': 'object',
    'properties': {
      'city': {'type': 'string', 'description': '城市名称'},
      'unit': {
        'type': 'string',
        'enum': ['celsius', 'fahrenheit'],
        'description': '温度单位',
      },
    },
    'required': ['city'],
  };

  @override
  Future<String> handler(Map<String, dynamic> arguments) async {
    final city = arguments['city'] as String;
    final unit = arguments['unit'] as String? ?? 'celsius';

    log('调用天气工具 城市：$city 单位：$unit');

    // 这里应该调用真实的天气API
    await Future.delayed(Duration(milliseconds: 500));

    return jsonEncode({'city': city, 'temperature': unit == 'celsius' ? 22 : 72, 'unit': unit, 'description': '晴天'});
  }

  @override
  String get title => "查询天气";
}
