import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'models/models.dart';

abstract class AIClient {
  Future<AIResponse> chat(List<ChatMessage> messages, {Map<String, dynamic>? options});
  Future<AIResponse> chatWithTools(List<ChatMessage> messages, {List<FunctionTool>? tools, Map<String, dynamic>? options});
  Stream<ChatEvent> chatStream(List<ChatMessage> messages, {List<FunctionTool>? tools, Map<String, dynamic>? options});
  Future<List<ChatMessage>> executeFunctionCalls(List<ToolCall> toolCalls, List<FunctionTool> availableTools);
}

/// ChatManager
///
/// 负责管理聊天会话的状态、消息历史和与 AIClient 的交互。
/// 继承自 ChangeNotifier，以便在状态变化时通知 UI 更新。
class ChatManager extends ChangeNotifier {
  final AIClient _client;
  final List<ChatMessage> _messages = [];
  final List<FunctionTool> _tools = [];

  // 用于流式渲染的临时状态
  String _streamingContent = '';
  bool _isStreaming = false;

  // 用于管理异步操作的取消
  CancelToken? _currentOperation;

  ChatManager(this._client);

  // --- 公共状态访问器 ---

  /// 不可修改的消息列表
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  /// 不可修改的工具列表
  List<FunctionTool> get tools => List.unmodifiable(_tools);

  /// 用户和助手消息的总数
  int get messageCount => _messages.where((it) => it.role != MessageRole.system).length;

  /// 当前正在流式传输的文本内容
  String get streamingContent => _streamingContent;

  /// 是否正在进行流式传输
  bool get isStreaming => _isStreaming;

  /// 获取用于 UI 渲染的完整列表（包含稳定的历史消息和临时的流式消息）
  List<ChatRenderItem> get renderItems {
    final items = _messages.map((msg) => ChatRenderItem.message(msg)).toList();

    // 如果正在流式输出，添加一个临时的流式消息项
    if (_isStreaming) {
      items.add(ChatRenderItem.streaming(_streamingContent));
    }

    return items;
  }

  // --- 内部状态修改方法 ---

  void addTool(FunctionTool tool) {
    _tools.add(tool);
  }

  void addTools(List<FunctionTool> tools) {
    _tools.addAll(tools);
  }

  void addMessage(ChatMessage message) {
    _messages.add(message);
    notifyListeners(); // 通知 UI 更新
  }

  void importMessages(List<ChatMessage> messages) {
    // 取消当前正在执行的操作
    _currentOperation?.cancel();

    // 重置流式状态
    _isStreaming = false;
    _streamingContent = '';

    // 清空并导入新消息
    _messages.clear();
    _messages.addAll(messages);
    notifyListeners(); // 通知 UI 更新
  }

  void addSystemMessage(String content) {
    addMessage(ChatMessage(role: MessageRole.system, content: content));
  }

  void addUserMessage(String content) {
    addMessage(ChatMessage(role: MessageRole.user, content: content));
  }

  // --- 核心交互 API ---

  /// 标准多轮对话（非流式，但支持 Function Call）
  Future<void> sendMessage(String content, {Map<String, dynamic>? options}) async {
    // 创建新的取消令牌
    final cancelToken = CancelToken();
    _currentOperation = cancelToken;

    try {
      addUserMessage(content);

      // 检查是否已被取消
      if (cancelToken.isCancelled) return;

      final response = await _client.chatWithTools(_messages, tools: _tools.isNotEmpty ? _tools : null, options: options);

      // 检查是否已被取消
      if (cancelToken.isCancelled) return;

      // 添加助手的第一轮回复（可能包含工具调用请求）
      addMessage(ChatMessage(role: MessageRole.assistant, content: response.content, toolCalls: response.toolCalls));

      // 如果有工具调用，则执行它们并获取最终回复
      if (response.hasToolCalls) {
        // 检查是否已被取消
        if (cancelToken.isCancelled) return;

        // 1. 执行工具调用
        final toolResults = await _client.executeFunctionCalls(response.toolCalls!, _tools);

        // 检查是否已被取消
        if (cancelToken.isCancelled) return;

        _messages.addAll(toolResults); // 将工具调用的结果也添加到历史记录中
        notifyListeners();

        // 2. 携带工具调用结果，再次请求 AI 获取最终回复
        final finalResponse = await _client.chat(_messages, options: options);

        // 检查是否已被取消
        if (cancelToken.isCancelled) return;

        addMessage(ChatMessage(role: MessageRole.assistant, content: finalResponse.content));
      }
    } catch (e) {
      if (!cancelToken.isCancelled) {
        log("Error during sendMessage: $e");
        rethrow;
      }
      // 如果是因为取消而产生的异常，则静默处理
    } finally {
      // 清理当前操作引用（如果是当前操作）
      if (_currentOperation == cancelToken) {
        _currentOperation = null;
      }
    }
  }

  /// 流式多轮对话（支持 Function Call）
  Stream<String> sendMessageStream(String content, {Map<String, dynamic>? options}) async* {
    // 创建新的取消令牌
    final cancelToken = CancelToken();
    _currentOperation = cancelToken;

    addUserMessage(content);

    _isStreaming = true;
    _streamingContent = '';
    notifyListeners(); // 通知 UI 开始进入流式状态

    final textBuffer = StringBuffer();
    try {
      // 核心处理逻辑：处理来自客户端的事件流
      final contentStream = _processStream(textBuffer, cancelToken, options: options);

      await for (final chunk in contentStream) {
        if (cancelToken.isCancelled) break;
        yield chunk; // 将内容块向上层（UI）传递
      }

      // 流式传输结束后，将最终的完整消息添加到历史记录
      // 如果 textBuffer 为空（例如，如果 AI 只进行了工具调用而没有返回文本），则不添加空消息
      if (textBuffer.isNotEmpty && !cancelToken.isCancelled) {
        _messages.add(ChatMessage(role: MessageRole.assistant, content: textBuffer.toString()));
      }
    } catch (e) {
      if (!cancelToken.isCancelled) {
        log("Error during chat stream: $e");
        // 可以在这里添加一条错误消息到聊天记录中
        addMessage(ChatMessage(role: MessageRole.system, status: MessageStatus.error, content: '服务器繁忙，请稍后再试。'));
        rethrow; // 重新抛出异常，让 UI 层也能捕获
      }
    } finally {
      // 清理流式状态
      _isStreaming = false;
      _streamingContent = '';

      // 清理当前操作引用（如果是当前操作）
      if (_currentOperation == cancelToken) {
        _currentOperation = null;
      }

      notifyListeners(); // 通知 UI 流式状态结束
    }
  }

  /// 私有方法：处理来自 AIClient 的流事件（包括内容和工具调用）
  Stream<String> _processStream(StringBuffer textBuffer, CancelToken cancelToken, {Map<String, dynamic>? options}) async* {
    final clientStream = _client.chatStream(_messages, tools: _tools.isNotEmpty ? _tools : null, options: options);

    await for (final event in clientStream) {
      // 检查是否已被取消
      if (cancelToken.isCancelled) break;

      if (event.type == ChatEventType.content) {
        // --- 处理普通文本内容 ---
        final text = event.text ?? '';
        textBuffer.write(text);
        _streamingContent = textBuffer.toString();
        log('[Streaming Content] $text');

        notifyListeners(); // 通知 UI 更新流式内容
        yield text; // 将文本块产出给上层
      } else if (event.type == ChatEventType.toolCalls) {
        // --- 处理工具调用 ---
        // 检查是否已被取消
        if (cancelToken.isCancelled) break;

        // 1. 将助手的工具调用请求添加到历史记录
        _messages.add(ChatMessage(role: MessageRole.assistant, toolCalls: event.toolCalls));

        // 2. 执行工具调用
        final toolResults = await _client.executeFunctionCalls(event.toolCalls!, _tools);

        // 检查是否已被取消
        if (cancelToken.isCancelled) break;

        _messages.addAll(toolResults); // 将结果添加到历史记录
        notifyListeners(); // 通知 UI 显示工具调用及其结果

        // 3. 递归调用自身，以获取工具执行后的最终 AI 回复，并将其流式输出
        // 【结构改进】使用 yield* 将后续的流无缝合并到当前流中
        yield* _processStream(textBuffer, cancelToken, options: options);
      }
    }
  }

  void clearHistory() {
    _messages.clear();
    notifyListeners();
  }

  void clearTools() {
    _tools.clear();
  }

  @override
  void dispose() {
    // 取消任何正在进行的操作
    _currentOperation?.cancel();
    super.dispose();
  }
}

/// 简单的取消令牌实现
class CancelToken {
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void cancel() {
    _isCancelled = true;
  }
}

// 流式对话事件类型
abstract class ChatStreamEvent {
  const ChatStreamEvent();

  factory ChatStreamEvent.chunk(String content) = ChatStreamChunk;
  factory ChatStreamEvent.info(String message) = ChatStreamInfo;
  factory ChatStreamEvent.done() = ChatStreamDone;
}

class ChatStreamChunk extends ChatStreamEvent {
  final String content;
  const ChatStreamChunk(this.content);
}

class ChatStreamInfo extends ChatStreamEvent {
  final String message;
  const ChatStreamInfo(this.message);
}

class ChatStreamDone extends ChatStreamEvent {
  const ChatStreamDone();
}

// 聊天渲染项 - 用于UI渲染的统一数据结构
abstract class ChatRenderItem {
  const ChatRenderItem();

  factory ChatRenderItem.message(ChatMessage message) = ChatMessageItem;
  factory ChatRenderItem.streaming(String content) = ChatStreamingItem;
}

class ChatMessageItem extends ChatRenderItem {
  final ChatMessage message;

  const ChatMessageItem(this.message);

  MessageRole get role => message.role;
  String? get content => message.content;
  List<ToolCall>? get toolCalls => message.toolCalls;
  String? get toolCallId => message.toolCallId;
  String? get toolCallName => message.toolCallName;
  bool get isStreaming => false;
}

class ChatStreamingItem extends ChatRenderItem {
  final String content;

  const ChatStreamingItem(this.content);

  MessageRole get role => MessageRole.assistant;
  List<ToolCall>? get toolCalls => null;
  String? get toolCallId => null;
  bool get isStreaming => true;
}
