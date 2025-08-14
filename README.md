# TinyAI

这是一个超级轻量级的 AI 聊天插件，你只需要用简单的方式进行配制后即可通过 OpenAI 的标准进行 AI 聊天，支持流式对话、支持 FunctionCall。

## 特色功能

- 支持流式对话
- 支持 FunctionCall
- 使用超简单

## 开始使用

用起来超级简单，请看下面的示例代码

```dart
TinyAIConfig.instance
        .setBaseUrl('https://api.openai.com/openai')
        .setApiKey('sk-test') // 替换为实际的API密钥
        .setModel('gpt-4')
        .setLogging(true);

// 创建客户端和聊天管理器
final client = OpenAIClient();
final chatManager = ChatManager(client);

// 添加系统消息
_chatManager.addSystemMessage('你是一个有用的AI助手，请用中文回复。');

// 添加示例工具
_chatManager.addTool(WeatherTool());
_chatManager.addTool(CalculatorTool());

// 发送消息
chatManager.sendMessageStream(message)
```

这一切是不是太过简单？让我们看看如何创建一个自定义工具函数。你只需要实现 Function Tool 接口即可，插件会自动调用函数，只管逻辑无需关注流程。

```dart
// 添加一个简单的计算器工具示例
class CalculatorTool extends FunctionTool {
  @override
  String get name => 'calculate';

  @override
  String get description => '执行基本的数学计算';

  @override
  Map<String, dynamic> get parameters => {
    'type': 'object',
    'properties': {
      'expression': {'type': 'string', 'description': '数学表达式，例如: 2+2, 10*5, sqrt(16)'},
    },
    'required': ['expression'],
  };

  @override
  Future<String> handler(Map<String, dynamic> arguments) async {
    final expression = arguments['expression'] as String;

    try {
      // 这里可以使用 math_expressions 包来解析表达式
      // 为了简化，我们只处理一些基本情况
      if (expression.contains('+')) {
        final parts = expression.split('+');
        final result = double.parse(parts[0].trim()) + double.parse(parts[1].trim());
        return '计算结果: $expression = $result';
      } else if (expression.contains('-')) {
        final parts = expression.split('-');
        final result = double.parse(parts[0].trim()) - double.parse(parts[1].trim());
        return '计算结果: $expression = $result';
      } else if (expression.contains('*')) {
        final parts = expression.split('*');
        final result = double.parse(parts[0].trim()) * double.parse(parts[1].trim());
        return '计算结果: $expression = $result';
      } else if (expression.contains('/')) {
        final parts = expression.split('/');
        final result = double.parse(parts[0].trim()) / double.parse(parts[1].trim());
        return '计算结果: $expression = $result';
      } else {
        return '无法解析表达式: $expression';
      }
    } catch (e) {
      return '计算错误: $e';
    }
  }
}
```

## 图片示例：

![home](/Users/locter/Projects/FlutterApp/tiny_ai/example/assets/home.jpg)

![chat](/Users/locter/Projects/FlutterApp/tiny_ai/example/assets/chat.jpg)
