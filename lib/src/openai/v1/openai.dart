import 'dart:convert';
import 'dart:developer';
import 'package:tiny_ai/src/client.dart';
import 'package:tiny_ai/src/config.dart';
import 'package:tiny_ai/src/http.dart';
import 'package:tiny_ai/src/models/models.dart';

class OpenAIClient extends AIClient {
  final HttpService _http = HttpService.instance;
  final TinyAIConfig _config = TinyAIConfig.instance;

  String get _baseUrl => _config.baseUrl ?? 'https://api.openai.com/v1';
  String get _apiKey => _config.apiKey ?? '';
  String get _model => _config.model ?? 'gpt-3.5-turbo';

  @override
  Future<AIResponse> chat(List<ChatMessage> messages, {Map<String, dynamic>? options}) async {
    final data = {
      'model': options?['model'] ?? _model,
      'messages': messages.map((m) => m.toJson()).toList(),
      'temperature': options?['temperature'] ?? 0.7,
      'max_tokens': options?['max_tokens'],
      'top_p': options?['top_p'],
      'frequency_penalty': options?['frequency_penalty'],
      'presence_penalty': options?['presence_penalty'],
      'stop': options?['stop'],
    };

    // 清理null值
    data.removeWhere((key, value) => value == null);

    final response = await _http.post(
      '$_baseUrl/chat/completions',
      data: data,
      headers: {'Authorization': 'Bearer $_apiKey', 'Content-Type': 'application/json'},
    );

    final completion = ChatCompletion.fromJson(response['data']);
    final choice = completion.choices.first;

    return AIResponse(
      content: choice.message.content ?? '',
      toolCalls: choice.message.toolCalls,
      finishReason: choice.finishReason,
      usage: completion.usage,
    );
  }

  @override
  Future<AIResponse> chatWithTools(List<ChatMessage> messages, {List<FunctionTool>? tools, Map<String, dynamic>? options}) async {
    final data = {
      'model': options?['model'] ?? _model,
      'messages': messages.map((m) => m.toJson()).toList(),
      'temperature': options?['temperature'] ?? 0.7,
      'max_tokens': options?['max_tokens'],
      'tools': tools?.map((t) => t.toJson()).toList(),
      'tool_choice': options?['tool_choice'],
    };

    data.removeWhere((key, value) => value == null);

    final response = await _http.post(
      '$_baseUrl/chat/completions',
      data: data,
      headers: {'Authorization': 'Bearer $_apiKey', 'Content-Type': 'application/json'},
    );

    final completion = ChatCompletion.fromJson(response['data']);
    final choice = completion.choices.first;

    return AIResponse(
      content: choice.message.content ?? '',
      toolCalls: choice.message.toolCalls,
      finishReason: choice.finishReason,
      usage: completion.usage,
    );
  }

  @override
  Stream<ChatEvent> chatStream(List<ChatMessage> messages, {List<FunctionTool>? tools, Map<String, dynamic>? options}) async* {
    // --- 1) 组织请求体 ---
    final req = {
      'model': options?['model'] ?? _model,
      'messages': messages.map((m) => m.toJson()).toList(),
      'temperature': options?['temperature'] ?? 0.7,
      'stream': true,
      'tools': tools?.map((t) => t.toJson()).toList(),
      'tool_choice': options?['tool_choice'],
    }..removeWhere((k, v) => v == null);

    // --- 2) 用原生 HttpClient 流式请求 ---
    final headers = {'Authorization': 'Bearer $_apiKey', 'Content-Type': 'application/json'};

    final stream = HttpService.instance.postStream('$_baseUrl/chat/completions', data: req, headers: headers);

    // --- 3) 累积器 ---
    final Map<int, ToolCall> toolCalls = {};
    final Map<int, StringBuffer> toolArgsBuf = {};

    // --- 4) SSE 行缓冲逻辑 ---
    await for (final line in stream) {
      if (!line.startsWith('data: ')) continue;
      final payload = line.substring(6).trim();
      if (payload.isEmpty) continue;

      if (payload == '[DONE]') {
        if (toolCalls.isNotEmpty) {
          final completeCalls = toolCalls.entries.map((e) {
            final tc = e.value;
            final args = toolArgsBuf[e.key]?.toString() ?? tc.function.arguments;
            return ToolCall(
              id: tc.id,
              type: tc.type,
              function: FunctionCall(name: tc.function.name, arguments: args),
            );
          }).toList();
          yield ChatEvent.toolCalls(completeCalls);
        }
        return;
      }

      Map<String, dynamic> obj;
      try {
        obj = jsonDecode(payload) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }

      final choice = (obj['choices'] as List?)?.first;
      if (choice == null) continue;
      final delta = choice['delta'] as Map<String, dynamic>?;
      if (delta == null) continue;

      // 普通文本增量
      final content = delta['content'];
      if (content is String) {
        yield ChatEvent.content(content);
      }

      // tool_calls（数组，支持并行）
      final tcs = delta['tool_calls'];
      if (tcs is List) {
        for (final t in tcs) {
          if (t is! Map) continue;
          final index = t['index'] ?? 0;
          final fn = t['function'] as Map? ?? {};
          final name = fn['name'] ?? '';
          final argsFragment = fn['arguments'] ?? '';

          // 初始化或累加
          if (!toolCalls.containsKey(index)) {
            toolCalls[index] = ToolCall(
              id: t['id'] ?? 'call_$index',
              type: t['type'] ?? 'function',
              function: FunctionCall(name: name, arguments: ''),
            );
            toolArgsBuf[index] = StringBuffer();
          }
          if (name.isNotEmpty) {
            toolCalls[index] = toolCalls[index]!.copyWith(
              function: FunctionCall(name: name, arguments: toolCalls[index]!.function.arguments),
            );
          }
          if (argsFragment.isNotEmpty) {
            toolArgsBuf[index]!.write(argsFragment);
          }
        }
      }
    }

    // 收尾：防止循环意外退出
    if (toolCalls.isNotEmpty) {
      final complete = toolCalls.entries.map((e) {
        return ToolCall(
          id: e.value.id,
          type: e.value.type,
          function: FunctionCall(name: e.value.function.name, arguments: toolArgsBuf[e.key]!.toString()),
        );
      }).toList();
      yield ChatEvent.toolCalls(complete);
    }
  }

  @override
  Future<List<ChatMessage>> executeFunctionCalls(List<ToolCall> toolCalls, List<FunctionTool> availableTools) async {
    final results = <ChatMessage>[];

    for (final toolCall in toolCalls) {
      final tool = availableTools.firstWhere(
        (t) => t.name == toolCall.function.name,
        orElse: () => throw Exception('Tool ${toolCall.function.name} not found'),
      );

      log('调用的 Tool ${toolCall.function.name}');

      try {
        final arguments = jsonDecode(toolCall.function.arguments);
        final result = await tool.handler(arguments);

        results.add(
          ChatMessage(role: MessageRole.tool, content: result, toolCallId: toolCall.id, toolCallName: toolCall.function.name),
        );
      } catch (e) {
        results.add(
          ChatMessage(
            role: MessageRole.tool,
            content: 'Error executing tool: $e',
            toolCallId: toolCall.id,
            toolCallName: toolCall.function.name,
          ),
        );
      }
    }

    return results;
  }

  /// 根据对话内容生成标题
  @override
  Future<String> generateTitle(List<ChatMessage> messages, {required String model, int maxLength = 20}) async {
    // 构造用于生成标题的 prompt
    final titlePrompt = _buildTitlePrompt(messages, maxLength);

    final titleMessages = [ChatMessage(role: MessageRole.user, content: titlePrompt)];

    try {
      final response = await chat(
        titleMessages,
        options: {
          'model': model,
          'temperature': 0.3, // 较低的温度保证结果稳定
          'max_tokens': maxLength, // 限制标题长度
        },
      );

      return response.content.trim();
    } catch (e) {
      // 如果生成失败，返回默认标题
      return _generateFallbackTitle(messages);
    }
  }

  /// 构建标题生成的 prompt
  String _buildTitlePrompt(List<ChatMessage> messages, int maxLength) {
    // 获取前几条消息作为上下文
    final contextMessages = messages
        .take(3)
        .where((msg) => msg.role == MessageRole.user || msg.role == MessageRole.assistant)
        .toList();

    if (contextMessages.isEmpty) {
      throw ArgumentError('No context messages found');
    }

    final context = contextMessages.map((msg) => '${msg.role.name}: ${msg.content}').join('\n');

    return '为这个对话生成一个中文标题, 长度和对话信息 (max $maxLength characters):\n\n$context\n\nTitle:';
  }

  /// 生成备用标题（当 AI 生成失败时）
  String _generateFallbackTitle(List<ChatMessage> messages) {
    final userMessages = messages.where((msg) => msg.role == MessageRole.user).toList();

    if (userMessages.isEmpty) {
      return 'New Conversation';
    }

    // 取第一条用户消息的前50个字符作为标题
    final firstMessage = userMessages.first.content;
    if (firstMessage == null) return '新对话';

    if (firstMessage.length <= 50) {
      return firstMessage;
    }

    return '${firstMessage.substring(0, 47)}...';
  }

  /// 智能标题生成（根据对话长度和内容智能选择策略）
  Future<String> generateSmartTitle(List<ChatMessage> messages, String model) async {
    if (messages.isEmpty) {
      return '新对话';
    }

    // 如果对话很短，直接使用第一条用户消息
    final userMessages = messages.where((msg) => msg.role == MessageRole.user).toList();
    if (userMessages.length == 1) {
      final content = userMessages.first.content;
      if (content == null) return "新对话";

      return content.length > 50 ? '${content.substring(0, 47)}...' : content;
    }

    // 如果对话较长，使用 AI 生成标题
    return await generateTitle(messages, model: model);
  }
}

// OpenAI特定的扩展方法（可选）
extension OpenAIClientExtensions on OpenAIClient {
  /// OpenAI特定的图像生成
  Future<Map<String, dynamic>> generateImage(String prompt, {String? model, String? size, String? quality, int n = 1}) async {
    final data = {
      'model': model ?? 'dall-e-3',
      'prompt': prompt,
      'size': size ?? '1024x1024',
      'quality': quality ?? 'standard',
      'n': n,
    };

    final response = await _http.post(
      '$_baseUrl/images/generations',
      data: data,
      headers: {'Authorization': 'Bearer $_apiKey', 'Content-Type': 'application/json'},
    );

    return response['data'];
  }

  /// OpenAI特定的嵌入向量
  Future<Map<String, dynamic>> createEmbedding(String input, {String? model}) async {
    final data = {'model': model ?? 'text-embedding-ada-002', 'input': input};

    final response = await _http.post(
      '$_baseUrl/embeddings',
      data: data,
      headers: {'Authorization': 'Bearer $_apiKey', 'Content-Type': 'application/json'},
    );

    return response['data'];
  }
}
