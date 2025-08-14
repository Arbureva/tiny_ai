import 'package:tiny_ai/tiny_ai.dart';

class ChatCompletion {
  final String id;
  final String object;
  final int created;
  final String model;
  final List<ChatCompletionChoice> choices;
  final Usage usage;

  const ChatCompletion({required this.id, required this.object, required this.created, required this.model, required this.choices, required this.usage});

  factory ChatCompletion.fromJson(Map<String, dynamic> json) {
    return ChatCompletion(id: json['id'], object: json['object'], created: json['created'], model: json['model'], choices: (json['choices'] as List).map((c) => ChatCompletionChoice.fromJson(c)).toList(), usage: Usage.fromJson(json['usage']));
  }
}

class ChatCompletionChoice {
  final int index;
  final ChatMessage message;
  final String finishReason;

  const ChatCompletionChoice({required this.index, required this.message, required this.finishReason});

  factory ChatCompletionChoice.fromJson(Map<String, dynamic> json) {
    return ChatCompletionChoice(index: json['index'], message: ChatMessage.fromJson(json['message']), finishReason: json['finish_reason']);
  }
}

class Usage {
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;

  const Usage({required this.promptTokens, required this.completionTokens, required this.totalTokens});

  factory Usage.fromJson(Map<String, dynamic> json) {
    return Usage(promptTokens: json['prompt_tokens'], completionTokens: json['completion_tokens'], totalTokens: json['total_tokens']);
  }
}
