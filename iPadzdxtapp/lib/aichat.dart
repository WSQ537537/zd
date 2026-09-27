import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'utils/toast.dart';
import 'formula_renderer.dart';

class AiChatPage extends StatefulWidget {
  final String? initialQuestion;

  const AiChatPage({super.key, this.initialQuestion});

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  final List<Map<String, dynamic>> _chatList = [];
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _loading = false;
  double _statusBarHeight = 0;
  double _keyboardHeight = 0;
  bool _showAboutModal = false;
  final ScrollController _scrollController = ScrollController();

  static const String apiKey = "d73ef586c3e4447e844924b5bf7f4b2b.dtFpAYPIaZBOdHlm";
  static const String aiUrl = "https://open.bigmodel.cn/api/paas/v4/chat/completions";
  static const String modelName = "glm-4-flash";

  @override
  void initState() {
    super.initState();

    // 延后到首帧再初始化：先测量状态栏、加载历史，再（若有）发送初始问题
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initStatusBar();
      await _loadChat();
      if (widget.initialQuestion != null && widget.initialQuestion!.isNotEmpty) {
        await _sendInitialQuestion(widget.initialQuestion!);
      }
      // 🔥 修复：加载完成后立即跳到底部，无滚动过渡
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(
            _scrollController.position.maxScrollExtent,
          );
        }
      });
    });

    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        _scrollToBottom();
      }
    });
  }

  Future<void> _initStatusBar() async {
    _statusBarHeight = MediaQuery.of(context).padding.top;
    setState(() {});
  }

  Future<void> _saveChat() async {
    // 限制聊天记录最多保留200条消息（100组对话）
    if (_chatList.length > 200) {
      _chatList.removeRange(1, _chatList.length - 200);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ai_chat_list', jsonEncode(_chatList));
  }

  Future<void> _loadChat() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('ai_chat_list');
    if (data != null && data.isNotEmpty) {
      try {
        final list = jsonDecode(data) as List;
        _chatList.addAll(list.map((e) => Map<String, dynamic>.from(e)));
      } catch (e) {
        _chatList.clear();
      }
    }

    if (_chatList.isEmpty) {
      _chatList.add({
        "id": "msg-welcome",
        "role": "assistant",
        "content": "你好！我是AI助手",
        "tipText": ""
      });
      await _saveChat();
    }
    setState(() {});
  }

  Future<void> _sendInitialQuestion(String question) async {
    if (question.isEmpty || _loading) return;

    final userMsg = {
      "id": "msg-${DateTime.now().millisecondsSinceEpoch}",
      "role": "user",
      "content": question,
      "tipText": ""
    };

    final aiMsg = {
      "id": "msg-${DateTime.now().millisecondsSinceEpoch + 1}",
      "role": "assistant",
      "content": "",
      "tipText": "AI思考中..."
    };

    setState(() {
      _chatList.add(userMsg);
      _chatList.add(aiMsg);
    });
    await _saveChat();
    _scrollToBottom();
    
    await _sendAiRequest(question, aiMsg["id"] as String);
  }
  
  Future<void> _sendMessage() async {
    final content = _inputController.text.trim();
    if (content.isEmpty || _loading) return;

    final userMsg = {
      "id": "msg-${DateTime.now().millisecondsSinceEpoch}",
      "role": "user",
      "content": content,
      "tipText": ""
    };

    final aiMsg = {
      "id": "msg-${DateTime.now().millisecondsSinceEpoch + 1}",
      "role": "assistant",
      "content": "",
      "tipText": "AI思考中..."
    };

    setState(() {
      _chatList.add(userMsg);
      _chatList.add(aiMsg);
      _inputController.clear();
    });
    await _saveChat();
    _scrollToBottom();
    
    await _sendAiRequest(content, aiMsg["id"] as String);
  }

  Future<void> _sendAiRequest(String content, String aiMsgId) async {
    setState(() {
      _loading = true;
    });

    try {
      final request = http.Request('POST', Uri.parse(aiUrl));
      request.headers.addAll({
        "Content-Type": "application/json",
        "Authorization": "Bearer $apiKey"
      });
      request.body = jsonEncode({
        "model": modelName,
        "messages": [
          {"role": "system", "content": "你是专业解题助手，只返回纯文本内容。数学公式必须使用标准LaTeX格式：行内公式用 \$...\$ 包裹（如：\$x^2 + y^2 = z^2\$），块级公式用 \$\$...\$\$ 包裹（如：\$\$\\frac{a}{b}\$\$）。上标用 ^{}（如：\$x^{2}\$），下标用 _{}（如：\$x_{1}\$），分数用 \\frac{}{}（如：\$\\frac{1}{2}\$），根号用 \\sqrt{}（如：\$\\sqrt{x}\$）。不要使用特殊字符如² √ × ÷，统一使用LaTeX语法。禁止返回图片、禁止使用其他格式，保持简洁。"},
          {"role": "user", "content": content}
        ],
        "stream": true,
        "temperature": 0.7
      });

      final client = http.Client();
      try {
        final streamedResponse = await client.send(request);

        if (!mounted) return;

        final index = _chatList.indexWhere((msg) => msg["id"] == aiMsgId);
        if (index == -1) return;

        if (streamedResponse.statusCode != 200) {
          setState(() {
            _chatList[index]["content"] = "错误 ${streamedResponse.statusCode}";
            _chatList[index]["tipText"] = "";
          });
          return;
        }

        // 流式处理
        StringBuffer fullContent = StringBuffer();
        await for (final chunk in streamedResponse.stream.transform(utf8.decoder)) {
          if (!mounted) return;

          final lines = chunk.split('\n');
          for (final line in lines) {
            if (line.isEmpty || line.trim() == 'data: [DONE]') continue;

            if (line.startsWith('data: ')) {
              try {
                final jsonData = jsonDecode(line.substring(6));
                final delta = jsonData["choices"]?[0]?["delta"]?["content"];
                if (delta != null && delta is String) {
                  fullContent.write(delta);
                  setState(() {
                    _chatList[index]["content"] = fullContent.toString();
                    _chatList[index]["tipText"] = "";
                  });
                  _scrollToBottom();
                }
              } catch (e) {
                // 忽略解析错误
              }
            }
          }
        }

        if (fullContent.isEmpty) {
          setState(() {
            _chatList[index]["content"] = "AI 没有返回内容";
          });
        }

        await _saveChat();
      } finally {
        client.close();
      }
    } catch (e) {
      if (!mounted) return;

      final index = _chatList.indexWhere((msg) => msg["id"] == aiMsgId);
      if (index != -1) {
        setState(() {
          _chatList[index]["content"] = "请求失败";
          _chatList[index]["tipText"] = "";
        });
        await _saveChat();
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _regenerateMessage(int index) async {
    if (_loading || index <= 0) return;
    final aiMsg = _chatList[index];
    final userMsg = _chatList[index - 1];
    if (userMsg["role"] != "user") return;

    setState(() {
      aiMsg["tipText"] = "重新生成中..";
      aiMsg["content"] = "";
    });
    
    await _sendAiRequest(userMsg["content"], aiMsg["id"]);
  }

  Future<void> _copyText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ToastUtil.showSuccess(context, "复制成功");
    }
  }

  Future<void> _handleClearChat() async {
    // 显示二次确认弹窗
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("清空记录"),
        content: const Text("确定要清空所有聊天记录吗？此操作不可恢复。"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("清空"),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() {
        _chatList.retainWhere((m) => m["id"] == "msg-welcome");
        if (_chatList.isEmpty) {
          _chatList.add({
            "id": "msg-welcome",
            "role": "assistant",
            "content": "你好！我是AI助手",
            "tipText": ""
          });
        }
      });
      await _saveChat();
      if (mounted) {
        ToastUtil.showSuccess(context, "已清空，已保留欢迎消息");
      }
    }
  }

  void _handleAbout() {
    debugPrint('🔔 [关于助手] 按钮被点击');
    setState(() {
      _showAboutModal = true;
    });
    debugPrint('🔔 [关于助手] 模态框状态: $_showAboutModal');
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(
          _scrollController.position.maxScrollExtent,
        );
      }
    });
  }

  // ==================== 平板横屏聊天布局 ====================
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    
    if (bottom != _keyboardHeight) {
      setState(() => _keyboardHeight = bottom);
    }

    if (!isTablet) {
      return _buildMobileLayout(bottom);
    }

    return Stack(
      children: [
        Scaffold(
          backgroundColor: const Color(0xFFF5F7FA),
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Color(0xFF1890FF)),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text("AI 助手", style: TextStyle(color: Color(0xFF333333))),
          ),
          body: Row(
            children: [
              Expanded(
                flex: 2,
                child: _buildChatList(),
              ),
              Container(width: 1, color: Colors.grey.shade200),
              Expanded(
                flex: 1,
                child: _buildRightPanel(),
              ),
            ],
          ),
          bottomNavigationBar: _buildInputArea(),
        ),
        // 🔥 平板端关于助手模态框
        if (_showAboutModal)
          Positioned.fill(
            child: GestureDetector(
              onTap: () {
                debugPrint('🔔 [关于助手] 点击背景关闭');
                setState(() => _showAboutModal = false);
              },
              behavior: HitTestBehavior.opaque,
              child: Container(
                color: Colors.black.withValues(alpha: 0.7),
                child: Center(
                  child: Container(
                    width: 400,
                    padding: const EdgeInsets.all(30),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          "使用须知",
                          style: TextStyle(
                            color: Color(0xFF333333),
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          "1. 请勿发送违法违规内容\n2. 回复结果仅供参考\n3. 长时间无响应可重新生成\n4. 清空记录会删除本地所有聊天记录",
                          style: TextStyle(color: Color(0xFF666666), height: 1.8, fontSize: 14),
                          textAlign: TextAlign.left,
                        ),
                        const SizedBox(height: 30),
                        GestureDetector(
                          onTap: () {
                            debugPrint('🔔 [关于助手] 点击确定按钮关闭');
                            setState(() => _showAboutModal = false);
                          },
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1890FF),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Center(
                              child: Text(
                                "确定",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildChatList() {
    return Container(
      color: const Color(0xFFF5F7FA),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(20),
        itemCount: _chatList.length,
        itemBuilder: (context, i) {
          final item = _chatList[i];
          final isUser = item["role"] == "user";
          return Align(
            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 6),
              constraints: const BoxConstraints(maxWidth: 600),
              decoration: BoxDecoration(
                color: isUser ? const Color(0xFF1890ff) : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(isUser ? 18 : 6),
                  topRight: Radius.circular(isUser ? 6 : 18),
                  bottomLeft: const Radius.circular(18),
                  bottomRight: const Radius.circular(18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (item["tipText"]?.isNotEmpty ?? false)
                    Text(
                      item["tipText"],
                      style: TextStyle(
                        color: isUser ? Colors.white70 : Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  if (item["content"]?.isNotEmpty ?? false)
                    // 🔥 平板端适配：使用 renderMixedText 替代 renderMathText
                    FormulaRenderer.renderMixedText(
                      item["content"],
                      style: TextStyle(
                        color: isUser ? Colors.white : const Color(0xFF333333),
                        fontSize: 15,
                        height: 1.6,
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () => _copyText(item["content"] ?? ""),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          backgroundColor: (isUser ? Colors.white : const Color(0xFF1890FF)).withValues(alpha: 0.15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text(
                          "复制",
                          style: TextStyle(color: isUser ? Colors.white : const Color(0xFF1890FF), fontSize: 12),
                        ),
                      ),
                      if (!isUser) const SizedBox(width: 10),
                      if (!isUser && !(item["tipText"]?.isNotEmpty ?? false))
                        TextButton(
                          onPressed: () => _regenerateMessage(i),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            backgroundColor: const Color(0xFF1890FF).withValues(alpha: 0.15),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text(
                            "重新生成",
                            style: TextStyle(color: Color(0xFF1890FF), fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRightPanel() {
    return Container(
      color: Colors.white,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(30, 20, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "对话信息",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF333333)),
            ),
            const SizedBox(height: 20),
            _buildInfoItem("消息数量", "${_chatList.length} 条", Icons.chat),
            const SizedBox(height: 12),
            _buildInfoItem("用户消息", "${_chatList.where((m) => m['role'] == 'user').length} 条", Icons.person),
            const SizedBox(height: 12),
            _buildInfoItem("AI回复", "${_chatList.where((m) => m['role'] == 'assistant').length} 条", Icons.smart_toy),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            const Text(
              "快捷操作",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF666666)),
            ),
            const SizedBox(height: 12),
            _buildActionBtn("清空记录", Icons.delete_outline, Colors.red, _handleClearChat),
            const SizedBox(height: 8),
            _buildActionBtn("关于助手", Icons.info_outline, const Color(0xFF1890FF), _handleAbout),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF1890FF), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(height: 4),
                Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBtn(String label, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(fontSize: 14, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputController,
              focusNode: _focusNode,
              style: const TextStyle(color: Color(0xFF333333), fontSize: 15),
              decoration: InputDecoration(
                hintText: "输入问题...",
                hintStyle: TextStyle(color: Colors.grey.shade400),
                filled: true,
                fillColor: const Color(0xFFF5F7FA),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
              maxLines: 4,
              minLines: 1,
              textInputAction: TextInputAction.newline,
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _sendMessage,
            child: Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFF1890ff), Color(0xFF096dd9)]),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Icon(Icons.send, color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 手机端布局 ====================
  Widget _buildMobileLayout(double bottom) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: true,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1890ff), Color(0xFF096dd9)],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: 56 + _statusBarHeight,
              left: 0,
              right: 0,
              bottom: 70 + (bottom > 0 ? 0 : 10),
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
                itemCount: _chatList.length,
                itemBuilder: (context, i) {
                  final item = _chatList[i];
                  final isUser = item["role"] == "user";
                  return Align(
                    alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.85,
                      ),
                      decoration: BoxDecoration(
                        color: isUser
                            ? const Color(0xFF1890ff)
                            : Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(isUser ? 18 : 6),
                          topRight: Radius.circular(isUser ? 6 : 18),
                          bottomLeft: const Radius.circular(18),
                          bottomRight: const Radius.circular(18),
                        ),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                      ),
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (item["tipText"]?.isNotEmpty ?? false)
                            Text(
                              item["tipText"],
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          if (item["content"]?.isNotEmpty ?? false)
                            LayoutBuilder(
                              builder: (context, constraints) {
                                return ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: constraints.maxWidth,
                                  ),
                                  // 🔥 平板端适配：使用 renderMixedText 替代 renderMathText
                                  child: FormulaRenderer.renderMixedText(
                                    item["content"],
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      height: 1.5,
                                    ),
                                  ),
                                );
                              },
                            ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton(
                                onPressed: () => _copyText(item["content"] ?? ""),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: const Text(
                                  "复制",
                                  style: TextStyle(color: Colors.white, fontSize: 12),
                                ),
                              ),
                              if (!isUser) const SizedBox(width: 10),
                              if (!isUser && !(item["tipText"]?.isNotEmpty ?? false))
                                TextButton(
                                  onPressed: () => _regenerateMessage(i),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    backgroundColor: Colors.white.withValues(alpha: 0.15),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: const Text(
                                    "重新生成",
                                    style: TextStyle(color: Colors.white, fontSize: 12),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            Positioned(
              top: _statusBarHeight,
              left: 0,
              right: 0,
              child: Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 15),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                ),
                child: Stack(
                  children: [
                    // 返回按钮 - 左侧
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Center(
                          child: Text(
                            "←",
                            style: TextStyle(color: Colors.white, fontSize: 24),
                          ),
                        ),
                      ),
                    ),
                    // 标题 - 居中
                    const Center(
                      child: Text(
                        "AI 助手",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 手机端快捷操作按钮
            Positioned(
              right: 15,
              bottom: 80,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: _handleClearChat,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.8),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.delete_outline, color: Colors.white, size: 22),
                    ),
                  ),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: _handleAbout,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1890FF).withValues(alpha: 0.8),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.info_outline, color: Colors.white, size: 22),
                    ),
                  ),
                ],
              ),
            ),

            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _inputController,
                        focusNode: _focusNode,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: "输入框",
                          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.2),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                        ),
                        maxLines: 4,
                        minLines: 1,
                        textInputAction: TextInputAction.newline,
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: _sendMessage,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          color: Color(0xFF1890ff),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Text(
                            "↑",
                            style: TextStyle(color: Colors.white, fontSize: 16),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (_showAboutModal)
              Positioned.fill(
                child: GestureDetector(
                  onTap: () {
                    debugPrint('🔔 [关于助手] 点击背景关闭');
                    setState(() => _showAboutModal = false);
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.7),
                    child: Center(
                      child: Container(
                        width: MediaQuery.of(context).size.width * 0.8,
                        padding: const EdgeInsets.all(30),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              "使用须知",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              "1. 请勿发送违法违规内容\n2. 回复结果仅供参考\n3. 长时间无响应可退出重进重新生成\n4. 清空记录会删除本地所有聊天记录，请谨慎操作！",
                              style: TextStyle(color: Colors.white, height: 1.8),
                            ),
                            const SizedBox(height: 30),
                            GestureDetector(
                              onTap: () {
                                debugPrint('🔔 [关于助手] 点击确定按钮关闭');
                                setState(() => _showAboutModal = false);
                              },
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 15),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Center(
                                  child: Text(
                                    "确定",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
