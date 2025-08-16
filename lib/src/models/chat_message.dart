enum MessageRole { system, user, assistant, tool }

enum MessageStatus { normal, info, warning, error }

class ChatMessage {
  final MessageRole role;
  final MessageStatus status;

  String? content;
  final String? name;
  final String? toolCallId;
  final String? toolCallName;
  final List<ToolCall>? toolCalls;
  final Map<String, dynamic>? metadata;

  ChatMessage({
    required this.role,
    this.content,
    this.name,
    this.toolCallId,
    this.toolCallName,
    this.toolCalls,
    this.metadata,
    this.status = MessageStatus.normal,
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{'role': role.name};

    if (content != null) json['content'] = content;
    if (name != null) json['name'] = name;
    if (toolCallId != null) json['tool_call_id'] = toolCallId;
    if (toolCalls != null) json['tool_calls'] = toolCalls!.map((tc) => tc.toJson()).toList();
    if (toolCallName != null) json['tool_call_name'] = toolCallName;
    if (metadata != null) json['metadata'] = metadata;
    if (status != MessageStatus.normal) json['status'] = status.name;

    return json;
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      role: MessageRole.values.firstWhere((e) => e.name == json['role'], orElse: () => MessageRole.user),
      status: MessageStatus.values.firstWhere((e) => e.name == json['status'], orElse: () => MessageStatus.normal),
      content: json['content'],
      name: json['name'],
      toolCallId: json['tool_call_id'],
      toolCallName: json['tool_call_name'],
      toolCalls: json['tool_calls']?.map<ToolCall>((tc) => ToolCall.fromJson(tc)).toList(),
      metadata: json['metadata'],
    );
  }
}

class ToolCall {
  final String id;
  final String type;
  final FunctionCall function;

  const ToolCall({required this.id, required this.type, required this.function});

  Map<String, dynamic> toJson() => {'id': id, 'type': type, 'function': function.toJson()};

  factory ToolCall.fromJson(Map<String, dynamic> json) =>
      ToolCall(id: json['id'], type: json['type'], function: FunctionCall.fromJson(json['function']));

  ToolCall copyWith({String? id, String? type, FunctionCall? function}) =>
      ToolCall(id: id ?? this.id, type: type ?? this.type, function: function ?? this.function);
}

class FunctionCall {
  final String name;
  final String arguments;

  const FunctionCall({required this.name, required this.arguments});

  Map<String, dynamic> toJson() => {'name': name, 'arguments': arguments};

  factory FunctionCall.fromJson(Map<String, dynamic> json) => FunctionCall(name: json['name'], arguments: json['arguments']);
}

class ChatEventType {
  static const String content = 'content';
  static const String toolCalls = 'tool_calls';
}

/// 事件：普通文本 / 工具调用（单或多）
class ChatEvent {
  final String type;
  final String? text;
  final List<ToolCall>? toolCalls;
  final String? functionName;
  final String? functionArguments;

  const ChatEvent._({required this.type, this.text, this.toolCalls, this.functionName, this.functionArguments});

  ChatEvent.content(String? text) : this._(type: 'content', text: text);
  ChatEvent.toolCalls(List<ToolCall>? toolCalls) : this._(type: 'tool_calls', toolCalls: toolCalls);
}
