// test/chat_demo_page.dart
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tiny_ai/tiny_ai.dart';

class ChatDemoPage extends StatefulWidget {
  const ChatDemoPage({super.key});

  @override
  State<ChatDemoPage> createState() => _ChatDemoPageState();
}

class _ChatDemoPageState extends State<ChatDemoPage> {
  late ChatManager _chatManager;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  String _status = '未连接';
  bool _useStreamMode = false;

  @override
  void initState() {
    super.initState();
    _initializeChat();
  }

  void _initializeChat() {
    TinyAIConfig.instance
        .setBaseUrl('https://api.openai.com/openai')
        .setApiKey('sk-test') // 替换为实际的API密钥
        .setModel('gpt-4')
        .setLogging(true);

    // 创建客户端和聊天管理器
    final client = OpenAIClient();
    _chatManager = ChatManager(client);

    // 添加系统消息
    _chatManager.addSystemMessage('你是一个有用的AI助手，请用中文回复。');

    // 添加示例工具
    _chatManager.addTool(WeatherTool());
    _chatManager.addTool(CalculatorTool());

    setState(() {
      _status = '已连接';
    });
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty || _isLoading) return;

    setState(() {
      _isLoading = true;
      _status = '思考中...';
    });

    _messageController.clear();

    try {
      // 使用流式模式（仅当没有工具时）
      await for (final _ in _chatManager.sendMessageStream(message)) {
        setState(() {
          // renderItems会自动包含流式内容
          log('更新后的值是：${_chatManager.streamingContent}');
        });

        // 自动滚动到底部
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottom();
        });
      }

      setState(() {
        _status = '已连接';
      });

      // 滚动到底部
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    } catch (e) {
      debugPrint('发送失败: $e');
      setState(() {
        _status = '错误: ${e.toString()}';
      });

      // 显示错误提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('发送失败: $e'), backgroundColor: Colors.red));
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _clearChat() {
    setState(() {
      _chatManager.clearHistory();
      _chatManager.addSystemMessage('你是一个有用的AI助手，请用中文回复。');
      _status = '已清除历史';
    });
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => _chatManager,
      builder: (context, child) => Scaffold(
        appBar: AppBar(
          title: const Text('TinyAI 聊天测试'),
          backgroundColor: Colors.deepPurple,
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'toggle_stream') {
                  setState(() {
                    _useStreamMode = !_useStreamMode;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(_useStreamMode ? '已开启流式模式' : '已关闭流式模式'), duration: const Duration(seconds: 1)),
                  );
                } else if (value == 'clear') {
                  _clearChat();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'toggle_stream',
                  child: Row(
                    children: [
                      Icon(_useStreamMode ? Icons.stream : Icons.layers),
                      const SizedBox(width: 8),
                      Text(_useStreamMode ? '关闭流式模式' : '开启流式模式'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'clear',
                  child: Row(children: [Icon(Icons.clear_all), SizedBox(width: 8), Text('清除聊天记录')]),
                ),
              ],
            ),
          ],
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.deepPurple.shade50, Colors.white],
            ),
          ),
          child: Column(
            children: [
              // 状态栏
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Colors.deepPurple.shade100,
                child: Row(
                  children: [
                    Icon(
                      _status == '已连接'
                          ? Icons.check_circle
                          : _status.startsWith('错误')
                          ? Icons.error
                          : Icons.hourglass_empty,
                      size: 16,
                      color: _status == '已连接'
                          ? Colors.green
                          : _status.startsWith('错误')
                          ? Colors.red
                          : Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Text('状态: $_status', style: TextStyle(fontSize: 14, color: Colors.deepPurple.shade700)),
                    const Spacer(),
                    Row(
                      children: [
                        if (_useStreamMode)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: Colors.green.shade200, borderRadius: BorderRadius.circular(12)),
                            child: const Text('流式', style: TextStyle(fontSize: 10)),
                          ),
                        const SizedBox(width: 8),
                        Text(
                          '消息数: ${_chatManager.messageCount}',
                          style: TextStyle(fontSize: 14, color: Colors.deepPurple.shade700),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // 聊天消息区域
              Expanded(
                child: _chatManager.messageCount == 0
                    ? _buildWelcomeScreen()
                    : ListView.builder(
                        key: ValueKey(_chatManager.streamingContent.hashCode),
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _chatManager.renderItems.length,
                        itemBuilder: (context, index) {
                          final renderItem = _chatManager.renderItems[index];
                          if (renderItem is ChatMessageItem && renderItem.role == MessageRole.system) {
                            return const SizedBox.shrink(); // 不显示系统消息
                          }
                          return _buildRenderItemBubble(renderItem);
                        },
                      ),
              ),

              // 输入区域
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, -2))],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        decoration: InputDecoration(
                          hintText: '输入消息...',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                        maxLines: null,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                        enabled: !_isLoading,
                      ),
                    ),
                    const SizedBox(width: 12),
                    FloatingActionButton(
                      onPressed: _isLoading ? null : _sendMessage,
                      backgroundColor: Colors.deepPurple,
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.send, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 80, color: Colors.deepPurple.shade300),
          const SizedBox(height: 24),
          Text(
            '欢迎使用 TinyAI 聊天测试',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.deepPurple.shade700),
          ),
          const SizedBox(height: 12),
          Text('发送消息开始对话', style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
          const SizedBox(height: 32),
          _buildFeatureList(),
        ],
      ),
    );
  }

  Widget _buildFeatureList() {
    final features = ['💬 支持多轮对话', '🔧 支持 Function Call', '🌤️ 内置天气查询工具', '🧮 内置计算器工具'];

    return Column(
      children: [
        ...features.map(
          (feature) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(feature, style: TextStyle(fontSize: 14, color: Colors.grey.shade700)),
          ),
        ),
      ],
    );
  }

  Widget _buildRenderItemBubble(ChatRenderItem renderItem) {
    if (renderItem is ChatMessageItem) {
      return _buildMessageBubble(renderItem.message);
    } else if (renderItem is ChatStreamingItem) {
      return _buildStreamingBubble(renderItem);
    }
    return const SizedBox.shrink();
  }

  Widget _buildStreamingBubble(ChatStreamingItem streamingItem) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: Colors.deepPurple,
            child: const Icon(Icons.android, size: 16, color: Colors.white),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              key: ValueKey(_chatManager.streamingContent), // 我原有的UI逻辑，现在应该怎么改进？
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_chatManager.streamingContent.isNotEmpty)
                    Text(_chatManager.streamingContent, style: const TextStyle(color: Colors.black87, fontSize: 16)),
                  if (_chatManager.streamingContent.isEmpty)
                    CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.deepPurple.shade300),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final isUser = message.role == MessageRole.user;
    final isAssistant = message.role == MessageRole.assistant;
    final isTool = message.role == MessageRole.tool;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: isTool ? Colors.orange : Colors.deepPurple,
              child: Icon(isTool ? Icons.build : Icons.android, size: 16, color: Colors.white),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isUser
                    ? Colors.deepPurple
                    : isTool
                    ? Colors.orange.shade100
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isTool) ...[
                    Text(
                      'Tool Result',
                      style: TextStyle(fontSize: 12, color: Colors.orange.shade700, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                  ],
                  Text(message.content ?? '', style: TextStyle(color: isUser ? Colors.white : Colors.black87, fontSize: 16)),
                  if (message.toolCalls != null && message.toolCalls!.isNotEmpty)
                    ...message.toolCalls!.map(
                      (toolCall) => Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.deepPurple.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.deepPurple.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '🔧 调用工具: ${toolCall.function.name}',
                                style: TextStyle(fontSize: 12, color: Colors.deepPurple.shade700, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                '参数: ${toolCall.function.arguments}',
                                style: TextStyle(fontSize: 12, color: Colors.deepPurple.shade600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            const CircleAvatar(
              radius: 16,
              backgroundColor: Colors.deepPurple,
              child: Icon(Icons.person, size: 16, color: Colors.white),
            ),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

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

void main() {
  runApp(const TinyAIChatDemoApp());
}

class TinyAIChatDemoApp extends StatelessWidget {
  const TinyAIChatDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TinyAI Chat Demo',
      theme: ThemeData(primarySwatch: Colors.deepPurple, useMaterial3: true),
      home: const ChatDemoPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}
