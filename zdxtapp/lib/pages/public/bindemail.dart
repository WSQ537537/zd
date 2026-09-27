import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zdxtapp/config.dart';
import 'package:zdxtapp/utils/toast.dart';

class BindEmailPage extends StatefulWidget {
  const BindEmailPage({super.key});

  @override
  State<BindEmailPage> createState() => _BindEmailPageState();
}

class _BindEmailPageState extends State<BindEmailPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();

  bool loading = false;
  bool sending = false;
  int countdown = 0;
  Timer? countdownTimer;

  String account = "";

  @override
  void initState() {
    super.initState();
    _loadAccount();
  }

  @override
  void dispose() {
    countdownTimer?.cancel();
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  // 加载当前账号
  Future<void> _loadAccount() async {
    final prefs = await SharedPreferences.getInstance();
    String acc = '';
    final userInfo = prefs.getString('userInfo');
    if (userInfo != null) {
      try {
        final user = jsonDecode(userInfo);
        acc = user['account'] ?? '';
      } catch (e) {
        acc = prefs.getString('account') ?? '';
      }
    } else {
      acc = prefs.getString('account') ?? '';
    }
    if (mounted) {
      setState(() {
        account = acc;
      });
    }
  }

  // 发送验证码
  Future<void> sendCode() async {
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      ToastUtil.showError(context, "请输入邮箱");
      return;
    }

    // 简单邮箱格式验证
    final emailReg = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    if (!emailReg.hasMatch(email)) {
      ToastUtil.showError(context, "邮箱格式不正确");
      return;
    }

    // 确保有 account
    if (account.isEmpty) {
      await _loadAccount();
      if (account.isEmpty) {
        if (!mounted) return;
        ToastUtil.showError(context, "未检测到登录账号，请先登录");
        Navigator.pushReplacementNamed(context, '/login');
        return;
      }
    }

    setState(() {
      sending = true;
    });

    try {
      final data = await jsonDecode((await http.post(
        Uri.parse('${Config.baseUrl}/api/user'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
        "action": "sendEmailCode",
        "account": account,
        "email": email,
        "purpose": "bind",
      }),
      )).body);
      if (!mounted) return;
      if (data['success'] == true) {
        ToastUtil.showSuccess(context, data['msg']);
        setState(() {
          countdown = 60;
        });
        startCountdown();
      } else {
        ToastUtil.showError(context, data['msg']);
      }
    } catch (e) {
      if (!mounted) return;
      ToastUtil.showError(context, "网络错误");
    } finally {
      if (mounted) {
        setState(() => sending = false);
      }
    }
  }

  // 开始倒计时
  void startCountdown() {
    countdownTimer?.cancel();
    countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (countdown > 0) {
        setState(() {
          countdown--;
        });
      } else {
        timer.cancel();
      }
    });
  }

  // 提交绑定
  Future<void> submitBind() async {
    final email = _emailController.text.trim();
    final code = _codeController.text.trim();

    if (email.isEmpty) {
      ToastUtil.showError(context, "请输入邮箱");
      return;
    }
    if (code.isEmpty) {
      ToastUtil.showError(context, "请输入验证码");
      return;
    }

    // 确保有 account
    if (account.isEmpty) {
      await _loadAccount();
      if (account.isEmpty) {
        if (!mounted) return;
        ToastUtil.showError(context, "未检测到登录账号，请先登录");
        Navigator.pushReplacementNamed(context, '/login');
        return;
      }
    }

    setState(() {
      loading = true;
    });

    try {
      final data = await jsonDecode((await http.post(
        Uri.parse('${Config.baseUrl}/api/user'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
        "action": "bindEmail",
        "account": account,
        "email": email,
        "code": code,
      }),
      )).body);
      if (!mounted) return;
      if (data['success'] == true) {
        ToastUtil.showSuccess(context, data['msg']);
        // 绑定成功，跳转到对应角色的首页（从本地 userInfo 读取 role）
        Future.delayed(const Duration(seconds: 1), () async {
          if (!mounted) return;
          _navigateToHome();
        });
      } else {
        ToastUtil.showError(context, data['msg']);
      }
    } catch (e) {
      if (!mounted) return;
      ToastUtil.showError(context, "网络错误");
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  void _navigateToHome() async {
    String route = '/student/home';
    try {
      final prefs = await SharedPreferences.getInstance();
      final userInfoStr = prefs.getString('userInfo');
      if (userInfoStr != null) {
        final user = jsonDecode(userInfoStr);
        final role = user['role'] ?? user['currentRole'] ?? 2;
        if (role == 1) {
          route = '/admin/home';
        } else if (role == 2) {
          route = '/student/home';
        } else {
          route = '/parent/home';
        }
      }
    } catch (_) {
      // ignore and fallback to student home
    }

    if (!mounted) return;
    Navigator.pushReplacementNamed(context, route);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1D2129)),
          onPressed: _navigateToHome,
        ),
        title: const Text(
          '绑定邮箱',
          style: TextStyle(color: Color(0xFF1D2129)),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 已删除标题
              // 已删除说明文字

              // 邮箱输入
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "邮箱地址",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF333333),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        hintText: "请输入邮箱地址",
                        prefixIcon: const Icon(Icons.email_outlined, color: Color(0xFF999999)),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFEEEEEE)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFEEEEEE)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF2877FF)),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      ),
                    ),
                    const SizedBox(height: 24),

                    const Text(
                      "验证码",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF333333),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          flex: 7,
                          child: TextField(
                            controller: _codeController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              hintText: "6位验证码",
                              prefixIcon: const Icon(Icons.verified_outlined, color: Color(0xFF999999)),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFFEEEEEE)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFFEEEEEE)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFF2877FF)),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 100,
                          height: 56,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: countdown > 0 ? Colors.grey : const Color(0xFF2877FF),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: EdgeInsets.zero,
                            ),
                            onPressed: (sending || countdown > 0) ? null : sendCode,
                            child: sending
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    countdown > 0 ? "${countdown}s" : "获取验证码",
                                    style: const TextStyle(fontSize: 12),
                                    textAlign: TextAlign.center,
                                  ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),

                    // 提交按钮
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2877FF),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: loading ? null : submitBind,
                        child: loading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                "立即绑定",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

                            // 提示信息
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F8FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Color(0xFF2877FF), size: 18),
                        SizedBox(width: 8),
                        Text(
                          "温馨提示",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF2877FF),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(
                      "• 绑定邮箱后可通过邮箱自主找回密码\n• 验证码有效期为5分钟\n• 每个邮箱只能绑定一个账号",
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF666666),
                        height: 1.6,
                      ),
                    ),
                    SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Color(0xFF2877FF), size: 18),
                        SizedBox(width: 8),
                        Text(
                          "请注意",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF2877FF),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(
                      "• 推荐使用QQ邮箱(或163邮箱或钉钉邮箱)\n• qq邮箱格式为:qq账号+@qq.com\n• 163邮箱格式为:163账号+@163.com\n• 钉钉邮箱格式为:钉钉号+@dingtalk.com\n(钉钉号：钉钉-我的-设置与隐私-我的信息-钉钉号中查看)",
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF666666),
                        height: 1.6,
                      ),
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
}
