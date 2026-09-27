import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/services.dart'; // 🔥 添加 Clipboard
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async'; // 🔥 添加 Timer
import 'dart:io'; // 🔥 添加 File
import 'package:dio/dio.dart'; // 🔥 添加 Dio
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zdxtapp/utils/formula_renderer.dart'; // 🔥 新公式渲染器（支持Markdown）
import 'package:zdxtapp/utils/toast.dart'; // 🔥 添加 ToastUtil

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
  bool _showMenuPop = false;
  bool _loading = false;
  double _statusBarHeight = 0;
  double _keyboardHeight = 0;
  bool _showAboutModal = false;
  final ScrollController _scrollController = ScrollController();

  // 🔥 新增：用于跟踪正在流式输出的消息索引，避免频繁setState
  int? _streamingMessageIndex;
  
  // 🔥 新增：用于取消正在进行的 AI 请求
  http.Client? _currentClient; // 保存当前的 HTTP 客户端
  CancelToken? _imageCancelToken; // 🔥 新增：用于取消图片生成请求
  bool _isGeneratingImage = false; // 🔥 新增：标记是否正在生成图片（控制按钮状态）

  // 🔥 新增：防抖定时器，减少setState频率
  Timer? _debounceTimer;
  static const Duration _debounceDuration = Duration(milliseconds: 50); // 50ms防抖
  
  // 🔥 新增：智能滚动控制
  bool _shouldAutoScroll = true; // 是否应该自动滚动到底部
  static const double _autoScrollThreshold = 50.0; // 距离底部多少像素内视为在底部

  // 🔥 新增：生成模式（text: 文本生成, image: 图片生成）
  String _generationMode = "text";
  
  // 🔥 新增：图片生成配置（根据官方文档修正）
  String _imageQuality = "standard"; // 🔥 修复：cogview-3-flash 默认使用 standard（5-10秒），hd 需要20秒
  String _imageSize = "1024x1024"; // 🔥 修复：使用 cogview-3-flash 支持的默认尺寸
  
  // 🔥 新增：悬浮选择器状态
  String? _activeSelector; // "quality" 或 "size"，null 表示关闭
  Offset? _selectorPosition; // 选择器弹出位置
  
  // 🔥 新增：多选模式状态
  bool _isMultiSelectMode = false; // 是否处于多选模式
  final Set<int> _selectedIndices = {}; // 选中的消息索引集合
  
  // 🔥 需求2：全屏编辑模式状态
  bool _isFullScreenEdit = false; // 是否处于全屏编辑模式
  
  // 🔥 需求2：输入框内容是否超过最大高度
  bool _showExpandButton = false; // 是否显示放大按钮
  
  // 🔥 需求3：加载动画定时器
  Timer? _loadingAnimationTimer;
  int _loadingDots = 0; // 加载动画点数（0-3循环）

  // 智谱AI配置（文本生成专用）
  static const String apiKey = "d73ef586c3e4447e844924b5bf7f4b2b.dtFpAYPIaZBOdHlm";
  static const String aiUrl = "https://open.bigmodel.cn/api/paas/v4/chat/completions";
  static const String modelName = "glm-4-flash";
  
  // 🔥 新增：图片生成API配置（独立密钥，与文本生成完全隔离）
  static const String imageUrl = "https://open.bigmodel.cn/api/paas/v4/images/generations";
  static const String imageModelName = "cogview-3-flash";
  
  // 🔥 需求1-5：图片生成专用密钥池（2组独立密钥）
  static const List<String> _imageApiKeys = [
    "efd4323801264c6c8bdd4cba8d453969.FmkSNYxXn7dtL2Cj",
    "6f44d415b1ff43759a066d84a33822d7.1LiyONhFTVzB1MQX",
  ];
  
  // 🔥 需求3：当前会话使用的图片生成密钥索引（首次随机选择，后续固定使用）
  int? _currentImageApiKeyIndex;
  
  @override
  void initState() {
    super.initState();
    _initStatusBar();

    // 🔥 修复：先加载历史 → 再处理初始问题 → 保证新问题在最下面
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadChat(); // 先加载历史对话

      // 🔥 修复：加载完成后立即跳到底部，无滚动过渡
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(
            _scrollController.position.maxScrollExtent,
          );
        }
      });

      // 有初始问题才追加
      if (widget.initialQuestion != null && widget.initialQuestion!.isNotEmpty) {
        await _sendInitialQuestion(widget.initialQuestion!);
      }
    });

    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        _scrollToBottom();
      }
    });

    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;

      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.position.pixels;
      final distanceFromBottom = maxScroll - currentScroll;

      if (distanceFromBottom > _autoScrollThreshold) {
        _shouldAutoScroll = false;
      } else {
        _shouldAutoScroll = true;
      }
    });
  }

  @override
  void dispose() {
    // 🔥 清理定时器
    _debounceTimer?.cancel();
    _loadingAnimationTimer?.cancel(); // 🔥 需求3：清理加载动画定时器
    _inputController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initStatusBar() async {
    _statusBarHeight = MediaQuery.of(context).padding.top;
  }

  // 本地存储
  Future<void> _saveChat() async {
    final prefs = await SharedPreferences.getInstance();
    // 🔥 核心修复：统一使用 'ai_chat_list' 作为键名，与_loadChat保持一致
    await prefs.setString('ai_chat_list', jsonEncode(_chatList));
  }

  Future<void> _loadChat() async {
    // 🔥 核心修复：无论是否有初始问题，都先加载历史记录
    // 这样从 exam detail 进入时，新问题是接在原有对话下面的
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('ai_chat_list');
    if (data != null && data.isNotEmpty) {
      try {
        final dynamic decoded = jsonDecode(data);
        if (decoded is List) {
          _chatList.addAll(decoded.map((e) => Map<String, dynamic>.from(e)));
        } else {
          _chatList.add(_welcomeMessage());
        }
      } catch (_) {
        // 本地数据损坏：丢弃旧数据并重置为欢迎消息
        _chatList.clear();
        _chatList.add(_welcomeMessage());
      }
      // 🔥 修复：加载完成后必须 setState 通知 UI 重绘，否则首帧仍是空的
      if (mounted) {
        setState(() {});
      }
    } else {
      // 只有在没有历史记录时才添加欢迎消息
      _chatList.add(_welcomeMessage());
      await _saveChat();
      if (mounted) {
        setState(() {});
      }
    }
  }

  /// 欢迎消息（统一构造，避免多处重复）
  Map<String, dynamic> _welcomeMessage() => {
        "id": "msg-welcome",
        "role": "assistant",
        "content": "你好！我是智答星途专属AI助手，您有任何学习问题都可以问我哦！",
        "tipText": ""
      };

  // 新增：发送初始问题
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
      _shouldAutoScroll = true; // 🔥 发送初始问题时重置自动滚动
    });
    await _saveChat();
    _scrollToBottom();
    
    // 发送AI请求
    await _sendAiRequest(question, aiMsg["id"] as String);
  }
  
  // 🔥 修改：原来的_sendMessage方法也需要调用_sendAiRequest
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
      "tipText": _generationMode == "text" ? "AI思考中..." : "图片生成中..."
    };

    setState(() {
      _chatList.add(userMsg);
      _chatList.add(aiMsg);
      _inputController.clear();
      _shouldAutoScroll = true; // 🔥 发送新消息时重置自动滚动
      // 🔥 发送后退出放大状态，恢复正常布局
      _isFullScreenEdit = false;
      _showExpandButton = false;
    });
    await _saveChat();
    _scrollToBottom();
    
    // 🔥 根据模式选择不同的请求方法
    if (_generationMode == "image") {
      await _generateImage(content, aiMsg["id"] as String);
    } else {
      await _sendAiRequest(content, aiMsg["id"] as String);
    }
  }

  // 🔥 修改：支持流式输出的通用方法（优化版 + 上下文记忆）
  Future<void> _sendAiRequest(String content, String aiMsgId) async {
    setState(() {
      _loading = true;
    });

    // 🔥 需求3：启动加载动画定时器
    _startLoadingAnimation();

    try {
      final client = http.Client();
      _currentClient = client; // 🔥 保存当前客户端，用于取消请求
      
      // 🔥 核心修复：构建完整的消息历史（包含system + 所有对话记录）
      final messages = <Map<String, dynamic>>[];
      
      // 1. 添加system消息（设定AI角色和规则）
      messages.add({
        "role": "system",
        "content": "你是专业的智答星途AI解题助手，只返回纯文本内容。数学公式必须使用标准LaTeX格式：行内公式用 \$...\$ 包裹（如：\$x^2 + y^2 = z^2\$），块级公式用 \$\$...\$\$ 包裹（如：\$\$\\frac{a}{b}\$\$）。上标用 ^{}（如：\$x^{2}\$），下标用 _{}（如：\$x_{1}\$），分数用 \\frac{}{}（如：\$\\frac{1}{2}\$），根号用 \\sqrt{}（如：\$\\sqrt{x}\$）。不要使用特殊字符如²  × ÷，统一使用LaTeX语法。禁止返回图片、禁止使用其他格式，保持简洁。"
      });
      
      // 2.  核心修复：添加历史对话记录（除当前消息外）
      // 找到当前AI消息在列表中的索引
      final currentIndex = _chatList.indexWhere((msg) => msg["id"] == aiMsgId);
      
      // 添加当前消息之前的所有对话（用户和AI的交替对话）
      for (int i = 0; i < currentIndex; i++) {
        final msg = _chatList[i];
        // 跳过欢迎消息和空内容消息
        if (msg["id"] == "msg-welcome" || 
            msg["content"] == null || 
            msg["content"].toString().isEmpty) {
          continue;
        }
        
        messages.add({
          "role": msg["role"],
          "content": msg["content"].toString()
        });
      }
      
      // 3. 添加当前用户消息
      messages.add({
        "role": "user",
        "content": content
      });
      
      debugPrint('📝 [上下文记忆] 发送消息数量: ${messages.length}');
      debugPrint('📝 [上下文记忆] 消息列表:');
      for (int i = 0; i < messages.length; i++) {
        debugPrint('   [$i] ${messages[i]["role"]}: ${messages[i]["content"].toString().substring(0, messages[i]["content"].toString().length > 50 ? 50 : messages[i]["content"].toString().length)}...');
      }
      
      final request = http.Request('POST', Uri.parse(aiUrl))
        ..headers['Content-Type'] = 'application/json'
        ..headers['Authorization'] = 'Bearer $apiKey'
        ..body = jsonEncode({
          "model": modelName,
          "messages": messages,  // 🔥 使用完整的消息历史
          "stream": true, // 🔥 开启流式输出
          "temperature": 0.7
        });

      final streamedResponse = await client.send(request);
      
      if (!mounted) return;

      final index = _chatList.indexWhere((msg) => msg["id"] == aiMsgId);
      if (index == -1) return;

      // 🔥 标记当前正在流式输出的消息索引
      _streamingMessageIndex = index;

      // 🔥 处理流式响应
      String fullContent = "";
      int chunkCount = 0;
      
      // 🔥 核心修复：SSE数据缓冲区，处理跨chunk的JSON分割问题
      String sseBuffer = "";
      
      await for (final chunk in streamedResponse.stream.transform(utf8.decoder)) {
        if (!mounted) break;
        
        // 🔥 将新数据追加到缓冲区
        sseBuffer += chunk;
        
        // 🔥 按行分割，但保留最后一行（可能不完整）
        final lines = sseBuffer.split('\n');
        
        // 如果最后一行不以 \n 结尾，说明是不完整的，保留在缓冲区
        if (!chunk.endsWith('\n')) {
          sseBuffer = lines.removeLast();
        } else {
          sseBuffer = "";
        }
        
        // 处理完整的行
        for (final line in lines) {
          final trimmedLine = line.trim();
          if (trimmedLine.isEmpty) continue;
          
          if (trimmedLine.startsWith('data: ')) {
            final jsonData = trimmedLine.substring(6).trim();
            
            // 跳过结束标记
            if (jsonData == '[DONE]') {
              continue;
            }
            
            // 跳过空数据
            if (jsonData.isEmpty) {
              continue;
            }
            
            try {
              final data = jsonDecode(jsonData);
              final delta = data["choices"]?[0]?["delta"]?["content"];
              
              if (delta != null && delta is String) {
                fullContent += delta;
                chunkCount++;
                
                // 🔥 优化1：使用防抖机制，减少setState频率
                _debounceTimer?.cancel();
                _debounceTimer = Timer(_debounceDuration, () {
                  if (!mounted) return;
                  
                  setState(() {
                    _chatList[index]["content"] = fullContent;
                    // 🔥 优化2：只在第一次收到内容时清除"思考中"提示
                    if (chunkCount == 1) {
                      _chatList[index]["tipText"] = "";
                      // 🔥 需求3：停止加载动画
                      _stopLoadingAnimation();
                    }
                  });
                  
                  // 🔥 优化3：降低滚动频率，每5个chunk滚动一次
                  if (chunkCount % 5 == 0) {
                    _scrollToBottom();
                  }
                });
              }
            } catch (e) {
              // 🔥 核心修复：只在真正失败时打印错误，忽略不完整JSON的临时错误
              if (e.toString().contains('FormatException')) {
                debugPrint('️ SSE数据格式异常: ${jsonData.substring(0, jsonData.length > 50 ? 50 : jsonData.length)}...');
              } else {
                debugPrint('❌ 解析SSE数据失败: $e');
                debugPrint('   数据: $jsonData');
              }
            }
          }
        }
      }
      
      //  优化4：确保最后一次更新立即执行（不受防抖影响）
      _debounceTimer?.cancel();
      if (mounted) {
        setState(() {
          _chatList[index]["content"] = fullContent;
          _chatList[index]["tipText"] = "";
          _streamingMessageIndex = null; // 清除流式输出标记
          _currentClient = null; // 🔥 清除客户端引用
          _stopLoadingAnimation(); // 🔥 需求3：停止加载动画
        });
        _scrollToBottom();
      }
      
      // 流式传输完成
      if (fullContent.isEmpty) {
        setState(() {
          _chatList[index]["content"] = "AI 没有返回内容";
          _stopLoadingAnimation(); // 🔥 需求3：停止加载动画
        });
      }
      
      await _saveChat();
      
    } catch (e) {
      if (!mounted) return;
      
      final index = _chatList.indexWhere((msg) => msg["id"] == aiMsgId);
      if (index != -1) {
        setState(() {
          _chatList[index]["content"] = "请求失败：$e";
          _chatList[index]["tipText"] = "";
          _streamingMessageIndex = null;
          _currentClient = null; // 🔥 清除客户端引用
          _stopLoadingAnimation(); //  需求3：停止加载动画
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  // 🔥 新增：使用 Dio 实现图片生成，添加超时控制和重试机制
  Future<void> _generateImage(String prompt, String aiMsgId) async {
    setState(() {
      _loading = true;
      _isGeneratingImage = true; // 🔥 标记图片生成中，按钮显示停止
    });

    // 🔥 需求3：启动加载动画定时器
    _startLoadingAnimation();

    // 🔥 创建 CancelToken 用于中断请求
    _imageCancelToken = CancelToken();

    // 🔥 创建 Dio 实例并配置超时
    final dio = Dio();
    dio.options.connectTimeout = const Duration(seconds: 30); // 连接超时 30 秒
    dio.options.receiveTimeout = const Duration(seconds: 120); // 接收超时 120 秒（高清图片生成较慢）
    dio.options.sendTimeout = const Duration(seconds: 30); // 发送超时 30 秒

    int retryCount = 0;
    const maxRetries = 2; // 最多重试 2 次

    // 🔥 需求3：获取当前会话使用的密钥（首次随机选择，后续固定使用）
    String currentApiKey = _getCurrentImageApiKey();

    while (retryCount <= maxRetries) {
      try {
        if (!mounted) return;

        // 🔥 检查是否已取消
        if (_imageCancelToken?.isCancelled ?? false) {
          debugPrint('🚫 图片生成已取消，退出重试循环');
          return;
        }

        final response = await dio.post(
          imageUrl,
          options: Options(
            headers: {
              'Content-Type': 'application/json',
              // 🔥 需求1：使用独立的图片生成密钥，与文本生成完全隔离
              'Authorization': 'Bearer $currentApiKey',
            },
          ),
          data: {
            "model": imageModelName,
            "prompt": prompt,
            "size": _imageSize,
            "quality": _imageQuality,
            "watermark_enabled": true
          },
          cancelToken: _imageCancelToken, // 🔥 添加取消令牌
        );

        if (!mounted) return;

        final index = _chatList.indexWhere((msg) => msg["id"] == aiMsgId);
        if (index == -1) return;

        final data = response.data;
        
        if (data["data"] != null && data["data"].isNotEmpty) {
          final generatedImageUrl = data["data"][0]["url"];
          
          setState(() {
            _chatList[index]["content"] = "";
            _chatList[index]["imageUrl"] = generatedImageUrl;
            _chatList[index]["tipText"] = "";
            _stopLoadingAnimation(); // 🔥 需求3：停止加载动画
          });
          
          // 🔥 需求1：图片生成成功后自动滚动到底部
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToBottom();
          });
          
          ToastUtil.show(context, "图片生成成功");
        } else {
          setState(() {
            _chatList[index]["content"] = "图片生成失败，请重试";
            _chatList[index]["tipText"] = "";
            _stopLoadingAnimation(); // 🔥 需求3：停止加载动画
          });
        }
        
        await _saveChat();
        break; // 成功后退出重试循环
        
      } catch (e) {
        // 🔥 检查是否为用户取消
        if (e is DioException && e.type == DioExceptionType.cancel) {
          debugPrint('🚫 图片生成被用户取消');
          // 🔥 取消时不显示错误，已在 _stopAiGeneration 中处理
          // 🔥 不再 return，让流程走到方法末尾统一清理 _loading 和 _isGeneratingImage
          break; // 跳出重试循环
        }

        retryCount++;

        // 🔥 详细错误处理
        String errorMsg = "图片生成失败";

        if (e is DioException) {
          switch (e.type) {
            case DioExceptionType.connectionTimeout:
              errorMsg = "连接超时，请检查网络后重试";
              break;
            case DioExceptionType.receiveTimeout:
              errorMsg = "响应超时，图片生成可能需要更长时间";
              break;
            case DioExceptionType.sendTimeout:
              errorMsg = "请求发送超时，请重试";
              break;
            case DioExceptionType.connectionError:
              errorMsg = "网络连接失败，请检查网络";
              break;
            case DioExceptionType.badResponse:
              final statusCode = e.response?.statusCode;
              final responseData = e.response?.data;
              String errorMessage = '未知错误';
              if (responseData is Map && responseData['error'] != null) {
                errorMessage = responseData['error']['message'] ?? '未知错误';
              }
              errorMsg = "服务器错误 ($statusCode): $errorMessage";
              break;
            default:
              errorMsg = "请求失败: ${e.message}";
          }
        } else {
          errorMsg = "图片生成失败: ${e.toString()}";
        }
        
        // 🔥 如果还有重试次数，显示重试提示并切换密钥
        if (retryCount <= maxRetries) {
          if (!mounted) return;
          
          // 🔥 需求4：检测到并发限制、额度超限或风控时，自动切换下一个密钥
          bool shouldSwitchKey = false;
          
          if (e is DioException && e.type == DioExceptionType.badResponse) {
            final statusCode = e.response?.statusCode;
            final responseData = e.response?.data;
            
            // 检测常见的风控/限流错误
            if (statusCode == 429 || statusCode == 403 || statusCode == 401) {
              shouldSwitchKey = true;
              debugPrint('⚠️ 检测到限流/风控错误 ($statusCode)，准备切换密钥');
            } else if (responseData is Map) {
              final errorMessage = responseData['error']?['message']?.toString().toLowerCase() ?? '';
              // 检测错误消息中的关键词
              if (errorMessage.contains('rate limit') || 
                  errorMessage.contains('quota') || 
                  errorMessage.contains('concurrent') ||
                  errorMessage.contains('frequency')) {
                shouldSwitchKey = true;
                debugPrint('⚠️ 检测到限流关键词，准备切换密钥');
              }
            }
          }
          
          // 如果需要切换密钥，则切换到下一个
          if (shouldSwitchKey) {
            _switchToNextImageApiKey();
            currentApiKey = _getCurrentImageApiKey(); // 更新当前使用的密钥
          }
          
          ToastUtil.show(context, "$errorMsg\n正在重试 ($retryCount/$maxRetries)...");
          await Future.delayed(const Duration(seconds: 2)); // 等待 2 秒后重试
        } else {
          // 🔥 所有重试都失败，显示最终错误
          if (!mounted) return;
          
          final index = _chatList.indexWhere((msg) => msg["id"] == aiMsgId);
          if (index != -1) {
            setState(() {
              _chatList[index]["content"] = errorMsg;
              _chatList[index]["tipText"] = "";
              _stopLoadingAnimation(); // 🔥 需求3：停止加载动画
            });
            await _saveChat();
          }
          
          if (!mounted) return;
          ToastUtil.showError(context, errorMsg);
        }
      }
    }

    if (mounted) {
      setState(() {
        _loading = false;
        _isGeneratingImage = false; // 🔥 图片生成结束，恢复发送箭头
      });
    }
    
    // 🔥 关闭 Dio 实例
    dio.close();
  }

  // 🔥 需求1：重新生成方法 - 区分文本和图片
  Future<void> _regenerateMessage(int index) async {
    if (_loading || index <= 0) return;
    final aiMsg = _chatList[index];
    final userMsg = _chatList[index - 1];
    if (userMsg["role"] != "user") return;

    setState(() {
      aiMsg["tipText"] = aiMsg["imageUrl"] != null ? "图片重新生成中.." : "重新生成中..";
      aiMsg["content"] = "";
      // 🔥 如果是图片，清空旧图片URL
      if (aiMsg["imageUrl"] != null) {
        aiMsg["imageUrl"] = null;
      }
    });
    
    // 🔥 需求1：根据消息类型选择不同的生成方式
    if (aiMsg["imageUrl"] != null || _generationMode == "image") {
      // 图片重新生成
      await _generateImage(userMsg["content"], aiMsg["id"]);
    } else {
      // 文本重新生成
      await _sendAiRequest(userMsg["content"], aiMsg["id"]);
    }
  }

  // 复制文本
  Future<void> _copyText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ToastUtil.showSuccess(context, "复制成功");
    }
  }

  // 🔥 新增：保存图片到公共目录（手机文件管理器可直接识别）
  Future<void> _saveImage(String imageUrl) async {
    try {
      ToastUtil.show(context, "正在保存...");
      
      // 下载图片
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode != 200) {
        throw Exception("图片下载失败");
      }
      
      // 🔥 使用公共目录（Pictures 文件夹）
      final String fileName = "ai_generated_${DateTime.now().millisecondsSinceEpoch}.png";
      final String publicDir = 'Pictures';
      final String savePath = '/storage/emulated/0/$publicDir/$fileName';
      
      debugPrint('📂 保存到公共目录: $publicDir');
      debugPrint('💾 完整路径: $savePath');
      
      // 写入文件到公共目录
      final file = File(savePath);
      await file.writeAsBytes(response.bodyBytes);
      
      if (!mounted) return;
      
      ToastUtil.showSuccess(context, "✅ 已保存到相册\n路径: $savePath");
    } catch (e) {
      if (!mounted) return;
      ToastUtil.showError(context, "保存失败: $e");
    }
  }

  // 清空记录
  Future<void> _handleClearChat() async {
    setState(() {
      _chatList.clear();
      // 🔥 清空后添加欢迎气泡
      _chatList.add({
        "id": "msg-welcome",
        "role": "assistant",
        "content": "你好！我是智答星途专属AI助手，您有任何学习问题都可以问我哦！",
        "tipText": ""
      });
      _showMenuPop = false;
    });
    await _saveChat();
  }

  // 关于
  void _handleAbout() {
    setState(() {
      _showAboutModal = true;
      _showMenuPop = false;
    });
  }

  // 滚动到底（智能滚动：只有当用户在底部附近时才自动滚动）
  void _scrollToBottom() {
    if (!_shouldAutoScroll) return; // 🔥 如果用户手动滚动了，不自动滚动
    
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(
          _scrollController.position.maxScrollExtent,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    if (bottom != _keyboardHeight) {
      setState(() => _keyboardHeight = bottom);
    }

    return PopScope(
      canPop: !_isMultiSelectMode, // 🔥 删除模式下不允许直接退出
      onPopInvokedWithResult: (didPop, result) {
        if (_isMultiSelectMode) {
          // 🔥 删除模式下按返回键，退出删除模式
          setState(() {
            _isMultiSelectMode = false;
            _selectedIndices.clear();
          });
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // 🔥 修复：允许Scaffold自动调整底部偏移，使输入框跟随键盘上移
        resizeToAvoidBottomInset: true,
        body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFFFF0F5), // 浅樱花粉
              Color(0xFFF0E6FF), // 薰衣草紫
              Color(0xFFE6F7FF), // 淡天蓝
            ],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // 卡通装饰层：浮动气泡 + 星星
            const _CartoonBgDecor(),
            // 聊天列表
            Positioned(
              top: 56 + _statusBarHeight,
              left: 0,
              right: 0,
              bottom: 60, // 🔥 底部留白：仅预留输入框基础高度，按钮现在在输入框容器内
              child: ListView.builder(
                controller: _scrollController,
                padding: EdgeInsets.only(
                  left: 15,
                  right: 15,
                  top: 15,
                  bottom: 80, // 🔥 增加底部预留空间，确保气泡在模式按钮上方
                ),
                itemCount: _chatList.length,
                itemBuilder: (context, i) {
                  final item = _chatList[i];
                  final isUser = item["role"] == "user";
                  final isSelected = _selectedIndices.contains(i);
                  
                  return Stack(
                    children: [
                      // 🔥 多选模式下显示圆形选择框（统一左对齐）
                      if (_isMultiSelectMode)
                        Positioned(
                          left: 15, // 🔥 固定在左侧，与 ListView padding 一致
                          top: 6, // 🔥 与气泡 margin 一致
                          child: GestureDetector(
                            onTap: () => _toggleSelection(i),
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected ? const Color(0xFF1890ff) : Colors.white.withValues(alpha: 0.5),
                                  width: 2,
                                ),
                                color: isSelected ? const Color(0xFF1890ff) : Colors.transparent,
                              ),
                              child: isSelected
                                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                                  : null,
                            ),
                          ),
                        ),
                      // 气泡容器（根据类型左右对齐）
                      Align(
                        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: GestureDetector(
                          // 🔥 长按进入多选模式
                          onLongPress: () {
                            if (!_isMultiSelectMode) {
                              _enterMultiSelectMode(i);
                            }
                          },
                          // 🔥 多选模式下点击切换选中状态
                          onTap: _isMultiSelectMode ? () => _toggleSelection(i) : null,
                          child: Container(
                            margin: EdgeInsets.only(
                              top: 6,
                              bottom: 6,
                              left: _isMultiSelectMode ? 40 : 0, // 🔥 多选模式下左侧留出选择框空间
                              right: 0,
                            ),
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.of(context).size.width * 0.85,
                            ),
                            decoration: BoxDecoration(
                              color: isUser
                                  ? const Color(0xFF1890ff)
                                  : const Color(0xFFD6EAF8), // 浅蓝不透明（AI 回复卡片）
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(isUser ? 18 : 6),
                                topRight: Radius.circular(isUser ? 6 : 18),
                                bottomLeft: const Radius.circular(18),
                                bottomRight: const Radius.circular(18),
                              ),
                              border: Border.all(
                                color: isUser
                                    ? Colors.transparent
                                    : const Color(0xFFB3D4F5), // 浅蓝描边
                              ),
                            ),
                            padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (item["tipText"]?.isNotEmpty ?? false)
                            Text(
                              // 🔥 需求3：使用动态加载文本
                              _loading && item["role"] == "assistant" && item["content"]?.isEmpty
                                ? _generateLoadingText(item["tipText"])
                                : item["tipText"],
                              style: TextStyle(
                                color: isUser ? Colors.white70 : const Color(0xFF34495E),
                                fontSize: 12,
                              ),
                            ),
                          if (item["content"]?.isNotEmpty ?? false)
                            // 🔥 核心修复：移除 maxHeight 限制，让气泡根据内容自动调整高度
                            LayoutBuilder(
                              builder: (context, constraints) {
                                // 🔥 使用新的 FormulaRenderer 渲染 AI 消息（支持 Markdown + 公式）
                                return FormulaRenderer.renderAIMessage(
                                  item["content"],
                                  baseStyle: TextStyle(
                                    color: isUser ? Colors.white : const Color(0xFF2C3E50), // 浅蓝卡片用深色字
                                    fontSize: 14,
                                    height: 1.5,
                                  ),
                                  isStreaming: _streamingMessageIndex == i,
                                  // ✅ 不传 maxHeight 参数，让内容自然流动，避免溢出
                                );
                              },
                            ),
                          // 🔥 新增：如果消息包含图片，显示图片
                          if (item["imageUrl"] != null && item["imageUrl"].toString().isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(top: 8),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  item["imageUrl"],
                                  fit: BoxFit.cover,
                                  loadingBuilder: (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return Container(
                                      height: 200,
                                      alignment: Alignment.center,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const CircularProgressIndicator(
                                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            "加载中 ${loadingProgress.expectedTotalBytes != null ? '${(loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes! * 100).toInt()}%' : ''}",
                                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      height: 200,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFCDE5F7),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Text(
                                        "图片加载失败",
                                        style: TextStyle(color: Color(0xFF5B7A9D), fontSize: 12),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          const SizedBox(height: 8),
                          // 🔥 多选模式下隐藏操作按钮，AI 流式输出时也隐藏
                          if (!_isMultiSelectMode && _streamingMessageIndex != i)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // 🔥 修复3：如果有图片，显示保存按钮；否则显示复制按钮
                                if (item["imageUrl"] != null && item["imageUrl"].toString().isNotEmpty)
                                  TextButton(
                                    onPressed: () => _saveImage(item["imageUrl"]),
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      backgroundColor: isUser ? Colors.white.withValues(alpha: 0.15) : const Color(0xFFB3D4F5),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: Text(
                                      "保存",
                                      style: TextStyle(color: isUser ? Colors.white : const Color(0xFF2C3E50), fontSize: 12),
                                    ),
                                  )
                                else
                                  TextButton(
                                    onPressed: () => _copyText(item["content"] ?? ""),
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      backgroundColor: isUser ? Colors.white.withValues(alpha: 0.15) : const Color(0xFFB3D4F5),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: Text(
                                      "复制",
                                      style: TextStyle(color: isUser ? Colors.white : const Color(0xFF2C3E50), fontSize: 12),
                                    ),
                                  ),
                                if (!isUser)
                                  const SizedBox(width: 10),
                                if (!isUser && !(item["tipText"]?.isNotEmpty ?? false))
                                  TextButton(
                                    onPressed: () => _regenerateMessage(i),
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      backgroundColor: const Color(0xFFB3D4F5),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: const Text(
                                      "重新生成",
                                      style: TextStyle(color: Color(0xFF2C3E50), fontSize: 12),
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ), // Container (气泡)
                ), // GestureDetector
              ), // Align
            ], // children of Stack
          ); // Stack
                },
              ),
            ),

            // 顶部导航
            Positioned(
              top: _statusBarHeight,
              left: 0,
              right: 0,
              child: Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 15),
                decoration: BoxDecoration(
                  color: const Color(0xFFD6EAF8), // 浅蓝不透明（顶部栏）
                  border: Border.all(color: const Color(0xFFB3D4F5)),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(12), // 长方形圆角
                    bottomRight: Radius.circular(12), // 长方形圆角
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (_isMultiSelectMode) ...[
                      // 多选模式：左侧"取消"按钮
                      GestureDetector(
                        onTap: _exitMultiSelectMode,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: const Text(
                            "取消",
                            style: TextStyle(color: Color(0xFF2C3E50), fontSize: 14),
                          ),
                        ),
                      ),
                      // 多选模式：中间"选择对话"文字
                      const Text(
                        "选择对话",
                        style: TextStyle(
                          color: Color(0xFF2C3E50),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      // 多选模式：右侧"全选"按钮
                      GestureDetector(
                        onTap: _toggleSelectAll,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Text(
                            _selectedIndices.length == _chatList.length ? "取消全选" : "全选",
                            style: const TextStyle(color: Color(0xFF2C3E50), fontSize: 14),
                          ),
                        ),
                      ),
                    ] else ...[
                      // 正常模式：返回按钮
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          child: const Text(
                            "←",
                            style: TextStyle(color: Color(0xFF2C3E50), fontSize: 24),
                          ),
                        ),
                      ),
                      const Text(
                        "AI 助手",
                        style: TextStyle(
                          color: Color(0xFF1890ff),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      // 三横线图标
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _showMenuPop = !_showMenuPop;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          child: const Text(
                            "☰",
                            style: TextStyle(color: Color(0xFF2C3E50), fontSize: 24),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // ✅ 菜单弹窗（带模糊背景）
            if (_showMenuPop) ...[
              // 模糊背景层
              Positioned.fill(
                child: GestureDetector(
                  onTap: () {
                    setState(() => _showMenuPop = false);
                  },
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.3),
                  ),
                ),
              ),
              // 缩小的菜单弹窗
              Positioned(
                top: _statusBarHeight + 66,
                right: 15,
                child: Container(
                  width: 180, // ✅ 从240缩小到180
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _menuItem("清空记录", onTap: _handleClearChat),
                      _menuItem("关于助手", onTap: _handleAbout),
                    ],
                  ),
                ),
              ),
            ],

            // 🔥 新增：悬浮选择器（质量/尺寸）
            if (_activeSelector != null && _selectorPosition != null) ...[
              // 背景遮罩
              Positioned.fill(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _activeSelector = null;
                      _selectorPosition = null;
                    });
                  },
                  child: Container(
                    color: Colors.transparent,
                  ),
                ),
              ),
              // 悬浮选择框
              Positioned(
                left: () {
                  // 🔥 智能计算左右位置：以按钮为中心，限制在屏幕范围内
                  final screenWidth = MediaQuery.of(context).size.width;
                  final popupWidth = 160.0;
                  final centerX = _selectorPosition!.dx;
                  var leftPos = centerX - popupWidth / 2;
                  
                  // 限制左边界
                  if (leftPos < 10) leftPos = 10;
                  // 限制右边界
                  if (leftPos + popupWidth > screenWidth - 10) {
                    leftPos = screenWidth - popupWidth - 10;
                  }
                  
                  return leftPos;
                }(),
                top: () {
                  // 🔥 智能计算上下位置：优先显示在按钮上方，保持适当间距
                  final screenHeight = MediaQuery.of(context).size.height;
                  final popupHeight = _activeSelector == "quality" ? 100.0 : 280.0; // quality约100px, size约280px
                  final buttonY = _selectorPosition!.dy;
                  
                  // 🔥 调整：增加与按钮的间距，让弹窗更靠上
                  final spacing = _activeSelector == "size" ? 70.0 : 35.0; // 尺寸弹窗间距70px，质量弹窗间距35px
                  
                  // 判断按钮上方是否有足够空间
                  final spaceAbove = buttonY;
                  final spaceBelow = screenHeight - buttonY;
                  
                  if (spaceAbove >= popupHeight + spacing + 20) {
                    // 上方有足够空间，显示在按钮上方
                    return buttonY - popupHeight - spacing;
                  } else if (spaceBelow >= popupHeight + spacing + 20) {
                    // 下方有足够空间，显示在按钮下方
                    return buttonY + spacing;
                  } else {
                    // 上下都不足，显示在中间（尽量靠上）
                    return (screenHeight - popupHeight) / 2;
                  }
                }(),
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 160,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_activeSelector == "quality") ...[
                          // 🔥 修复：添加时间说明，让用户清楚了解速度差异
                          _buildQualityOption("高清 (20秒)", "hd"),
                          const SizedBox(height: 4),
                          _buildQualityOption("标准 (5-10秒)", "standard"),
                        ] else if (_activeSelector == "size") ...[
                          // 🔥 需求3：移除多余描述，只显示比例
                          _buildSizeOption("1024x1024", "1:1"),
                          const SizedBox(height: 4),
                          _buildSizeOption("1344x768", "16:9"),
                          const SizedBox(height: 4),
                          _buildSizeOption("768x1344", "9:16"),
                          const SizedBox(height: 4),
                          _buildSizeOption("1152x864", "4:3"),
                          const SizedBox(height: 4),
                          _buildSizeOption("864x1152", "3:4"),
                          const SizedBox(height: 4),
                          _buildSizeOption("1440x720", "2:1"),
                          const SizedBox(height: 4),
                          _buildSizeOption("720x1440", "1:2"),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],

            // 🔥 需求2+3：输入框区域 - 输入框自带不透明背景
            Positioned(
              left: 0,
              right: 0,
              bottom: 20, // 🔥 上移，使输入框和按钮更靠近底部
              child: _isMultiSelectMode
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                      child: _buildMultiSelectBottomBar(),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 🔥 需求2：模式切换按钮紧贴输入框上方，随输入框同步移动（仅按钮自身不透明）
                        if (!_isMultiSelectMode && !_isFullScreenEdit)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _buildModeButton("文本生成", "text"),
                                _buildModeButton("图片生成", "image"),
                                if (_generationMode == "image") ...[
                                  // 🔥 需求1&2：质量按钮只显示选中内容，不显示"质量"文字和秒数
                                  _buildConfigButton("", _imageQuality == "hd" ? "高清" : "标准", "quality"),
                                  _buildConfigButton("", _getDimensionRatio(_imageSize), "size"),
                                ],
                              ],
                            ),
                          ),
                        // 🔥 需求5+6：放大后的顶部栏（仅在放大状态显示）- 已移除，改为内嵌在输入框中
                        // 输入框容器
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          constraints: BoxConstraints(
                            maxHeight: _isFullScreenEdit 
                                ? MediaQuery.of(context).size.height * 0.5 // 🔥 放大时最大高度为屏幕的一半
                                : double.infinity,
                          ),
                          child: Stack(
                            children: [
                              // 输入框背景容器
                              Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1890ff), // 🔥 始终保持蓝色完全不透明背景
                                  borderRadius: BorderRadius.circular(12), // 🔥 长方形圆角
                                ),
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.vertical,
                                  physics: const BouncingScrollPhysics(), // 🔥 使用弹性滚动效果
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minHeight: 0,
                                      maxHeight: _isFullScreenEdit 
                                          ? MediaQuery.of(context).size.height * 0.5 - 16 // 🔥 减去padding
                                          : double.infinity,
                                    ),
                                    child: TextField(
                                      controller: _inputController,
                                      focusNode: _focusNode,
                                      style: const TextStyle(color: Colors.white, fontSize: 14),
                                      decoration: InputDecoration(
                                        hintText: _generationMode == "text" ? "输入问题..." : "描述想要生成的图片...",
                                        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                                        filled: false,
                                        border: InputBorder.none,
                                        contentPadding: EdgeInsets.only(
                                          left: 15,
                                          right: _isFullScreenEdit ? 60.0 : 60.0, // 🔥 始终预留右侧空间给按钮（放大/缩小/发送）
                                          top: _isFullScreenEdit ? 45.0 : 8.0, // 🔥 放大时预留顶部空间给"编辑"文字
                                          bottom: 8.0,
                                        ),
                                      ),
                                      maxLines: _isFullScreenEdit ? null : 4, // 🔥 放大时不限制行数
                                      minLines: 1,
                                      textInputAction: TextInputAction.newline, // 🔥 需求1：支持换行
                                      keyboardType: TextInputType.multiline, // 🔥 需求1：启用多行键盘，确保换行功能正常
                                      // 🔥 需求2：监听内容变化，判断是否显示放大按钮
                                      onChanged: (value) {
                                        // 🔥 修复：使用防抖，避免频繁 setState 影响换行
                                        _debounceTimer?.cancel();
                                        _debounceTimer = Timer(const Duration(milliseconds: 300), () {
                                          if (mounted) {
                                            setState(() {
                                              // 🔥 当内容为空时，自动退出放大状态
                                              if (value.isEmpty && _isFullScreenEdit) {
                                                _isFullScreenEdit = false;
                                                _showExpandButton = false;
                                              }
                                              
                                              // 当内容达到最高高度（4行）时显示放大按钮
                                              final lines = value.split('\n').length;
                                              if (lines >= 4 && !_showExpandButton) {
                                                _showExpandButton = true;
                                              } else if (lines < 4 && _showExpandButton) {
                                                _showExpandButton = false;
                                              }
                                            });
                                          }
                                        });
                                      },
                                    ),
                                  ),
                                ),
                              ),
                              // 🔥 需求4：放大按钮显示在输入框右上角（非全屏状态）
                              if (_showExpandButton && !_isFullScreenEdit)
                                Positioned(
                                  right: 8, // 输入框右侧
                                  top: 4, // 输入框顶部附近
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _isFullScreenEdit = true; // 🔥 进入放大状态
                                      });
                                    },
                                    child: Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.2),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white.withValues(alpha: 0.3),
                                          width: 1,
                                        ),
                                      ),
                                      child: const Center(
                                        child: Icon(
                                          Icons.open_in_full, // 🔥 需求4：对角双向向外箭头
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              // 🔥 放大状态：左上角显示"编辑"，右上角显示缩小按钮（仅在有内容时显示）
                              if (_isFullScreenEdit && _inputController.text.isNotEmpty) ...[
                                // 左上角"编辑"文字
                                Positioned(
                                  left: 15,
                                  top: 12,
                                  child: const Text(
                                    "编辑",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                // 右上角缩小按钮
                                Positioned(
                                  right: 8,
                                  top: 8,
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _isFullScreenEdit = false;
                                      });
                                    },
                                    child: Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.2),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white.withValues(alpha: 0.3),
                                          width: 1,
                                        ),
                                      ),
                                      child: const Center(
                                        child: Icon(
                                          Icons.close_fullscreen, // 对角双向向内箭头
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              // 🔥 需求3：发送按钮内嵌在输入框右下角
                              if (!_isMultiSelectMode)
                                Positioned(
                                  right: 8,
                                  bottom: 4, // 🔥 下移4px，使发送按钮在输入框内上下间距相同
                                  child: GestureDetector(
                                    onTap: (_streamingMessageIndex != null || _isGeneratingImage) ? _stopAiGeneration : _sendMessage,
                                    child: Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: (_streamingMessageIndex != null || _isGeneratingImage) 
                                            ? Colors.red.withValues(alpha: 0.8)
                                            : const Color(0xFF1890ff),
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.2),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Center(
                                        child: Text(
                                          (_streamingMessageIndex != null || _isGeneratingImage) ? "■" : "↑",
                                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),

            // 关于弹窗
            if (_showAboutModal)
              GestureDetector(
                onTap: () {
                  setState(() => _showAboutModal = false);
                },
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
                            "1.请勿发送违法、违规、违背公序良俗的内容\n2.所有回复内容仅供参考，不构成专业决策依据\n3.若长时间无响应，可退出重进重新发起提问\n4.清空对话记录后，本地保存的全部聊天内容将会被删除",
                            style: TextStyle(color: Colors.white, height: 1.8),
                          ),
                          const SizedBox(height: 30),
                          GestureDetector(
                            onTap: () {
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
          ],
        ),
      ),
    ), // Scaffold
    ); // PopScope
  }

  Widget _menuItem(String text, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16), // ✅ 减小垂直间距
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.2)), // ✅ 改为灰色边框
          ),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.black87, // ✅ 改为深色文字
            fontSize: 15, // ✅ 稍微减小字体
          ),
        ),
      ),
    );
  }

  // 🔥 优化：构建模式切换按钮 - 现代化UI
  Widget _buildModeButton(String label, String mode) {
    final isSelected = _generationMode == mode;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _generationMode = mode;
          // 🔥 需求2：切换到文本生成页时，自动关闭所有悬浮弹窗
          if (mode == "text") {
            _activeSelector = null;
            _selectorPosition = null;
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected 
              ? Colors.white // 🔥 选中时完全不透明白色
              : const Color(0xFF1890ff), // 🔥 未选中时蓝色不透明背景
          borderRadius: BorderRadius.circular(8), // 🔥 长方形圆角
          border: Border.all(
            color: isSelected 
                ? const Color(0xFF1890ff)  // 🔥 选中时使用主题蓝色边框
                : Colors.white.withValues(alpha: 0.5), // 🔥 未选中时使用白色边框
            width: 1,
          ),
          boxShadow: isSelected ? [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ] : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? const Color(0xFF1890ff) : Colors.white, // 🔥 选中时蓝色文字，未选中时白色
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }

  // 🔥 优化：构建配置按钮，支持悬浮弹窗 - 现代化UI
  Widget _buildConfigButton(String label, String value, String selectorType) {
    return GestureDetector(
      onTapDown: (details) {
        //  修复①：点击按钮时先关闭键盘，然后在下一帧重新计算位置
        _focusNode.unfocus();
        
        // 延迟设置位置，等待键盘收起动画完成
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            setState(() {
              // 🔥 修复②：再次点击同一按钮时关闭弹窗
              if (_activeSelector == selectorType) {
                _activeSelector = null;
                _selectorPosition = null;
              } else {
                _activeSelector = selectorType;
                // 🔥 修复②：使用按钮中心位置作为参考点，弹窗显示在按钮上方
                _selectorPosition = details.globalPosition;
              }
            });
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _generationMode == "image" ? Colors.white : Colors.white.withValues(alpha: 0.35), // 🔥 图片生成模式下为白色
          borderRadius: BorderRadius.circular(8), // 🔥 长方形圆角
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.5), // 🔥 需求2：更清晰的边框
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1), // 🔥 微妙的阴影
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Text(
          label.isEmpty ? value : "$label: $value",
          style: TextStyle(
            color: _generationMode == "image" ? const Color(0xFF1890ff) : Colors.white, // 🔥 图片生成模式下为蓝色文字
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
  
  // 🔥 新增：获取尺寸比例（用于按钮显示，移除多余描述）
  String _getDimensionRatio(String size) {
    switch (size) {
      case "1024x1024":
        return "1:1";
      case "1344x768":
        return "16:9";
      case "768x1344":
        return "9:16";
      case "1152x864":
        return "4:3";
      case "864x1152":
        return "3:4";
      case "1440x720":
        return "2:1";
      case "720x1440":
        return "1:2";
      default:
        return size;
    }
  }
  
  // 🔥 需求3：启动加载动画定时器
  void _startLoadingAnimation() {
    _loadingAnimationTimer?.cancel();
    _loadingAnimationTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _loadingDots = (_loadingDots + 1) % 4; // 0, 1, 2, 3 循环
      });
    });
  }
  
  // 🔥 需求3：停止加载动画
  void _stopLoadingAnimation() {
    _loadingAnimationTimer?.cancel();
    _loadingDots = 0;
  }
  
  // 🔥 需求3：生成加载动画文本（如："AI思考中." "AI思考中.." "AI思考中..."）
  String _generateLoadingText(String baseText) {
    final dots = '.' * _loadingDots;
    return '$baseText$dots';
  }
  
  // 🔥 新增：构建质量选项（用于悬浮弹窗）
  Widget _buildQualityOption(String label, String value) {
    final isSelected = _imageQuality == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _imageQuality = value;
          _activeSelector = null; // 关闭选择器
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1890ff).withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected ? const Color(0xFF1890ff) : Colors.black87,
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            if (isSelected)
              const Icon(Icons.check, color: Color(0xFF1890ff), size: 18),
          ],
        ),
      ),
    );
  }
  
  // 🔥 新增：构建尺寸选项（用于悬浮弹窗）
  Widget _buildSizeOption(String value, String label) {
    final isSelected = _imageSize == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _imageSize = value;
          _activeSelector = null; // 关闭选择器
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1890ff).withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected ? const Color(0xFF1890ff) : Colors.black87,
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            if (isSelected)
              const Icon(Icons.check, color: Color(0xFF1890ff), size: 18),
          ],
        ),
      ),
    );
  }
  
  // 🔥 需求3：获取或初始化当前会话使用的图片生成密钥
  String _getCurrentImageApiKey() {
    // 如果已经选择了密钥，直接返回
    if (_currentImageApiKeyIndex != null) {
      return _imageApiKeys[_currentImageApiKeyIndex!];
    }
    
    // 首次调用时随机选择一个密钥
    final random = DateTime.now().millisecondsSinceEpoch % _imageApiKeys.length;
    _currentImageApiKeyIndex = random;
    
    debugPrint('🔑 图片生成密钥初始化：使用索引 $_currentImageApiKeyIndex');
    return _imageApiKeys[random];
  }
  
  // 🔥 需求4：切换到下一个可用的密钥（当当前密钥失败时）
  void _switchToNextImageApiKey() {
    if (_currentImageApiKeyIndex == null) return;
    
    // 循环切换到下一个密钥
    _currentImageApiKeyIndex = (_currentImageApiKeyIndex! + 1) % _imageApiKeys.length;
    
    debugPrint('⚠️ 图片生成密钥切换：切换到索引 $_currentImageApiKeyIndex');
  }
  
  // 🔥 新增：进入多选模式
  void _enterMultiSelectMode(int index) {
    setState(() {
      _isMultiSelectMode = true;
      _selectedIndices.clear();
      _selectedIndices.add(index); // 长按的气泡默认勾选
    });
  }
  
  // 🔥 修改：停止 AI 生成，保留已接收的内容，不显示报错
  void _stopAiGeneration() {
    // 🔥 处理文本生成中断
    if (_currentClient != null) {
      // 关闭 HTTP 客户端，中断请求
      _currentClient!.close();
      _currentClient = null;

      // 🔥 修改：找到当前正在生成的消息，保留已接收的内容
      final currentIndex = _streamingMessageIndex;
      if (currentIndex != null && currentIndex < _chatList.length) {
        setState(() {
          // 🔥 保留已接收的内容，不显示任何报错信息
          _chatList[currentIndex]["tipText"] = ""; // 清除提示文本
          _streamingMessageIndex = null; // 清除流式输出标记
          _loading = false; // 停止加载状态
        });

        _saveChat(); // 🔥 异步保存当前状态（不阻塞UI）
      } else {
        setState(() {
          _streamingMessageIndex = null; // 清除流式输出标记
          _loading = false; // 停止加载状态
        });
      }

      _stopLoadingAnimation(); // 停止加载动画
      // 🔥 不显示Toast提示
    }

    // 🔥 处理图片生成中断
    if (_imageCancelToken != null && !_imageCancelToken!.isCancelled) {
      _imageCancelToken!.cancel("用户中断图片生成");
      _imageCancelToken = null;

      // 🔥 找到当前正在生成的图片消息，显示"已中断"
      final currentIndex = _chatList.indexWhere((msg) =>
          msg["role"] == "assistant" &&
          msg["tipText"] == "图片生成中...");

      if (currentIndex != -1) {
        setState(() {
          _chatList[currentIndex]["content"] = "已中断"; // 🔥 显示"已中断"
          _chatList[currentIndex]["tipText"] = "";
          _chatList[currentIndex]["imageUrl"] = null; // 🔥 丢弃未完成的图片
          _loading = false;
          _isGeneratingImage = false; // 🔥 恢复发送箭头
        });

        _saveChat();
      } else {
        setState(() {
          _loading = false;
          _isGeneratingImage = false; // 🔥 恢复发送箭头
        });
      }

      _stopLoadingAnimation();
    }
  }
  
  // 🔥 新增：退出多选模式
  void _exitMultiSelectMode() {
    setState(() {
      _isMultiSelectMode = false;
      _selectedIndices.clear();
    });
  }
  
  // 🔥 新增：切换选中状态
  void _toggleSelection(int index) {
    setState(() {
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
      } else {
        _selectedIndices.add(index);
      }
    });
  }
  
  // 🔥 新增：全选/取消全选
  void _toggleSelectAll() {
    setState(() {
      if (_selectedIndices.length == _chatList.length) {
        _selectedIndices.clear();
      } else {
        for (int i = 0; i < _chatList.length; i++) {
          _selectedIndices.add(i);
        }
      }
    });
  }
  
  // 🔥 新增：删除选中的消息
  void _deleteSelectedMessages() {
    if (_selectedIndices.isEmpty) {
      ToastUtil.show(context, "请先选择要删除的消息");
      return;
    }
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF096dd9),
        title: const Text("确认删除", style: TextStyle(color: Colors.white)),
        content: Text(
          "确定要删除选中的 ${_selectedIndices.length} 条消息吗？",
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("取消", style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              // 按索引从大到小排序，避免删除时索引变化
              final sortedIndices = _selectedIndices.toList()..sort((a, b) => b.compareTo(a));
              
              setState(() {
                for (final index in sortedIndices) {
                  if (index >= 0 && index < _chatList.length) {
                    _chatList.removeAt(index);
                  }
                }
                _selectedIndices.clear();
                _isMultiSelectMode = false;
                
                // 🔥 如果删除后聊天列表为空，重新添加欢迎气泡
                if (_chatList.isEmpty) {
                  _chatList.add({
                    "id": "msg-welcome",
                    "role": "assistant",
                    "content": "你好！我是智答星途专属AI助手，您有任何学习问题都可以问我哦！",
                    "tipText": ""
                  });
                }
              });
              
              _saveChat();
              ToastUtil.showSuccess(context, "已删除 ${sortedIndices.length} 条消息");
            },
            child: const Text("删除", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
  
  // 🔥 新增：构建多选模式底部栏
  Widget _buildMultiSelectBottomBar() {
    return GestureDetector(
      onTap: _deleteSelectedMessages,
      child: Container(
        width: double.infinity,
        height: 50,
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(25),
        ),
        child: Center(
          child: Text(
            "删除 (${_selectedIndices.length})",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

}

/// 卡通风格背景装饰：半透明气泡 + 星星点缀
class _CartoonBgDecor extends StatelessWidget {
  const _CartoonBgDecor();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(children: [
        Positioned(top: -30, left: -40, child: _Bubble(r: 90, color: const Color(0xFFEE82EE).withValues(alpha: 0.18))),
        Positioned(top: 40, right: -50, child: _Bubble(r: 110, color: const Color(0xFF87CEEB).withValues(alpha: 0.15))),
        Positioned(top: 260, left: -25, child: _Bubble(r: 65, color: const Color(0xFFFFDAB9).withValues(alpha: 0.20))),
        Positioned(top: 520, right: -20, child: _Bubble(r: 80, color: const Color(0xFFDDA0DD).withValues(alpha: 0.16))),
        Positioned(bottom: 120, left: -15, child: _Bubble(r: 70, color: const Color(0xFF98FB98).withValues(alpha: 0.14))),
        Positioned(top: 70, left: 60, child: _Star(size: 18, color: Color(0xFFFFD700).withValues(alpha: 0.45))),
        Positioned(top: 120, right: 80, child: _Star(size: 12, color: Color(0xFFFFAEC7).withValues(alpha: 0.50))),
        Positioned(top: 300, right: 30, child: _Star(size: 14, color: Color(0xFFB0E0E6).withValues(alpha: 0.45))),
        Positioned(bottom: 200, left: 40, child: _Star(size: 11, color: Color(0xFFFFE4B5).withValues(alpha: 0.50))),
        Positioned(bottom: 160, left: 160, child: _Star(size: 10, color: Color(0xFFDDA0DD).withValues(alpha: 0.40))),
        Positioned(top: 180, left: 120, child: _Dot(r: 5, color: const Color(0xFFEE82EE).withValues(alpha: 0.30))),
        Positioned(top: 240, right: 100, child: _Dot(r: 4, color: const Color(0xFF87CEEB).withValues(alpha: 0.35))),
        Positioned(top: 400, left: 30, child: _Dot(r: 6, color: const Color(0xFFFFDAB9).withValues(alpha: 0.28))),
        Positioned(bottom: 300, right: 60, child: _Dot(r: 5, color: const Color(0xFF98FB98).withValues(alpha: 0.25))),
        Positioned(bottom: 250, left: 100, child: _Dot(r: 4, color: const Color(0xFFFFAEC7).withValues(alpha: 0.30))),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  final double r;
  final Color color;
  const _Bubble({required this.r, required this.color});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: r * 2, height: r * 2,
    child: CustomPaint(painter: _BubblePainter(r, color)),
  );
}

class _BubblePainter extends CustomPainter {
  final double r;
  final Color color;
  _BubblePainter(this.r, this.color);
  @override
  void paint(Canvas c, Size s) {
    final cx = s.width / 2, cy = s.height / 2;
    c.drawCircle(Offset(cx, cy), r, Paint()..color = color..style = PaintingStyle.fill);
    c.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r * 0.85),
      -0.9, 1.2, false,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }
  @override bool shouldRepaint(_) => false;
}

class _Star extends StatelessWidget {
  final double size;
  final Color color;
  const _Star({required this.size, required this.color});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size, height: size,
    child: CustomPaint(painter: _StarPainter(color)),
  );
}

class _StarPainter extends CustomPainter {
  final Color color;
  _StarPainter(this.color);
  @override
  void paint(Canvas c, Size s) {
    final cx = s.width / 2, cy = s.height / 2;
    final outerR = s.width / 2, innerR = outerR * 0.4;
    final path = ui.Path();
    for (int i = 0; i < 5; i++) {
      final aO = (i * 72 - 90) * 3.14159265 / 180;
      final aI = ((i * 72 + 36) - 90) * 3.14159265 / 180;
      if (i == 0) {
        path.moveTo(cx + outerR * math.cos(aO), cy + outerR * math.sin(aO));
      } else {
        path.lineTo(cx + outerR * math.cos(aO), cy + outerR * math.sin(aO));
      }
      path.lineTo(cx + innerR * math.cos(aI), cy + innerR * math.sin(aI));
    }
    path.close();
    c.drawPath(path, Paint()..color = color..style = PaintingStyle.fill);
  }
  @override bool shouldRepaint(_) => false;
}

class _Dot extends StatelessWidget {
  final double r;
  final Color color;
  const _Dot({required this.r, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    width: r * 2, height: r * 2,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}
