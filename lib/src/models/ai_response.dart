import 'package:tiny_ai/tiny_ai.dart';

class AIResponse {
  final String content;
  final List<ToolCall>? toolCalls;
  final String? finishReason;
  final Usage? usage;
  final Map<String, dynamic>? metadata;

  const AIResponse({required this.content, this.toolCalls, this.finishReason, this.usage, this.metadata});

  bool get hasToolCalls => toolCalls != null && toolCalls!.isNotEmpty;
}
