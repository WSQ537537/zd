import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:convert';
import 'dart:async';
import 'config.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController account = TextEditingController();
  final TextEditingController password = TextEditingController();
  String msg = "";
  bool loading = false;
  bool showPwd = false;

  // 二维码登录相关状态
  String loginMode = "account"; // "account" 或 "qrcode"
  String qrkey = "";
  String qrMsg = "请使用手机学生端扫码登录";
  bool qrLoading = false;
  Timer? pollTimer;

  @override
  void initState() {
    super.initState();
  }

  // 切换登录模式
  void switchLoginMode(String mode) {
    if (loginMode == mode) return;
    
    // 切换到账号登录时，停止轮询
    if (mode == "account") {
      stopPolling();
    }
    
    setState(() {
      loginMode = mode;
      msg = "";
      qrMsg = "请使用手机学生端扫码登录";
    });
    
    // 切换到二维码登录时，自动创建二维码
    if (mode == "qrcode") {
      createQRCode();
    }
  }

  // 创建二维码
  Future<void> createQRCode() async {
    setState(() {
      qrLoading = true;
      qrMsg = "正在生成二维码...";
      qrkey = "";
    });

    try {
      final response = await http.post(
        Uri.parse("${Config.baseUrl}/api/user"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"action": "qrcodecreate"}),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final res = jsonDecode(response.body);
        if (res["success"] == true) {
          setState(() {
            qrkey = res["qrkey"];
            qrMsg = "请使用手机学生端扫码登录";
            qrLoading = false;
          });
          // 开始轮询检查授权状态
          startPolling();
        } else {
          setState(() {
            qrMsg = res["msg"] ?? "二维码生成失败";
            qrLoading = false;
          });
        }
      } else {
        setState(() {
          qrMsg = "服务器异常";
          qrLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        qrMsg = "网络异常，请重试";
        qrLoading = false;
      });
    }
  }

  // 开始轮询检查授权状态
  void startPolling() {
    stopPolling(); // 先停止之前的轮询
    
    pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (qrkey.isEmpty || !mounted) {
        timer.cancel();
        return;
      }

      try {
        final response = await http.post(
          Uri.parse("${Config.baseUrl}/api/user"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "action": "qrcodecheck",
            "qrkey": qrkey,
          }),
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200 && mounted) {
          final res = jsonDecode(response.body);
          
          if (res["success"] == true && res["status"] == "authorized") {
            // 授权成功，停止轮询
            stopPolling();
            
            // 保存用户信息并跳转
            final acc = res["account"];
            final remark = res["remark"] ?? "";
            const int studentRole = 2;
            
            final sp = await SharedPreferences.getInstance();
            await sp.setString("userInfo", jsonEncode({
              "account": acc,
              "role": studentRole,
              "remark": remark,
              "loginTime": DateTime.now().millisecondsSinceEpoch,
            }));

            setState(() {
              qrMsg = "登录成功，正在跳转...";
            });

            if (mounted) {
              Navigator.pushReplacementNamed(context, "/exam");
            }
          } else if (res["status"] == "expired") {
            // 二维码过期
            stopPolling();
            setState(() {
              qrMsg = "二维码已过期，请点击刷新";
              qrkey = "";
            });
          }
          // 其他情况（waiting）继续轮询，不更新状态
        }
      } catch (e) {
        // 网络异常，继续轮询
        if (mounted) {
          setState(() {
            qrMsg = "网络异常，正在重试...";
          });
        }
      }
    });
  }

  // 停止轮询
  void stopPolling() {
    if (pollTimer != null) {
      pollTimer!.cancel();
      pollTimer = null;
    }
  }

  // 刷新二维码
  void refreshQRCode() {
    stopPolling();
    createQRCode();
  }

  Future<void> doLogin() async {
    final acc = account.text.trim();
    final pwd = password.text.trim();
    const int studentRole = 2; // 固定学生端

    if (acc.isEmpty || pwd.isEmpty) {
      setState(() => msg = "请填写完整账号密码");
      return;
    }
    if (loading) return;

    setState(() {
      loading = true;
      msg = "正在登录...";
    });

    try {
      final response = await http.post(
        Uri.parse("${Config.baseUrl}/api/user"),
        headers: {
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "action": "login",
          "account": acc,
          "password": pwd,
          "selected_role": studentRole,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final res = jsonDecode(response.body);

        if (res["success"] == true) {
          final sp = await SharedPreferences.getInstance();
          await sp.setString("userInfo", jsonEncode({
            "account": acc,
            "role": studentRole,
            "remark": res["remark"] ?? "",
            "loginTime": DateTime.now().millisecondsSinceEpoch,
          }));

          if (mounted) {
            // 统一跳转到考试页面
            Navigator.pushReplacementNamed(context, "/exam");
          }
        } else {
          setState(() => msg = res["msg"] ?? "登录失败");
        }
      } else {
        setState(() => msg = "服务器异常");
      }
    } catch (e) {
      setState(() => msg = "网络异常或登录超时");
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> logout() async {
    final sp = await SharedPreferences.getInstance();
    await sp.clear();
    if (mounted) {
      Navigator.pushReplacementNamed(context, "/login");
    }
  }

  @override
  void dispose() {
    account.dispose();
    password.dispose();
    stopPolling(); // 页面销毁时停止轮询
    super.dispose();
  }

  // ==================== 平板横屏居中布局 ====================
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      body: Stack(
        children: [
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0F172A),
                  Color(0xFF1E293B),
                  Color(0xFF2D3A4E),
                ],
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: isTablet ? screenWidth * 0.15 : 30,
                vertical: 40,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: isTablet ? 600 : double.infinity,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),
                    const Text(
                      "智答星途",
                      style: TextStyle(
                        fontSize: 48,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(
                            offset: Offset(0, 2),
                            blurRadius: 8,
                            color: Colors.blueAccent,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "考试系统端",
                      style: TextStyle(color: Colors.white60, fontSize: 18),
                    ),
                    const SizedBox(height: 60),

                    // 登录模式切换按钮（左右等分）
                    _loginModeBar(isTablet),
                    const SizedBox(height: 50),

                    // 根据模式显示不同内容
                    if (loginMode == "account") ...[
                      _inputField("👤 账号", false, account, "account", isTablet),
                      const SizedBox(height: 30),

                      _pwdField(isTablet),
                      const SizedBox(height: 20),

                      if (msg.isNotEmpty)
                        Text(
                          msg,
                          style: const TextStyle(color: Color(0xFFFF9F4A), fontSize: 16),
                        ),
                      const SizedBox(height: 40),

                      _loginButton(isTablet),
                    ] else ...[
                      // 二维码登录区域
                      _qrLoginSection(isTablet),
                    ],
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 登录模式切换按钮（左右等分，高亮选中）
  Widget _loginModeBar(bool isTablet) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black38,
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: Colors.white12),
      ),
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          // 账号登录按钮
          Expanded(
            child: GestureDetector(
              onTap: () => switchLoginMode("account"),
              child: Container(
                padding: EdgeInsets.symmetric(vertical: isTablet ? 16 : 12),
                decoration: BoxDecoration(
                  color: loginMode == "account" ? Colors.blueAccent : Colors.transparent,
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Text(
                  "账号登录",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: loginMode == "account" ? Colors.white : Colors.white60,
                    fontWeight: loginMode == "account" ? FontWeight.w500 : FontWeight.normal,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ),
          // 二维码登录按钮
          Expanded(
            child: GestureDetector(
              onTap: () => switchLoginMode("qrcode"),
              child: Container(
                padding: EdgeInsets.symmetric(vertical: isTablet ? 16 : 12),
                decoration: BoxDecoration(
                  color: loginMode == "qrcode" ? Colors.blueAccent : Colors.transparent,
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Text(
                  "二维码登录",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: loginMode == "qrcode" ? Colors.white : Colors.white60,
                    fontWeight: loginMode == "qrcode" ? FontWeight.w500 : FontWeight.normal,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 二维码登录区域
  Widget _qrLoginSection(bool isTablet) {
    return Column(
      children: [
        // 状态提示文案
        Text(
          qrMsg,
          style: const TextStyle(color: Colors.white70, fontSize: 16),
        ),
        const SizedBox(height: 30),

        // 二维码区域
        Container(
          width: isTablet ? 200 : 160,
          height: isTablet ? 200 : 160,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: qrLoading
              ? const Center(child: CircularProgressIndicator(color: Colors.blueAccent))
              : qrkey.isNotEmpty
                  ? Center(
                      child: QrImageView(
                        data: qrkey,
                        version: QrVersions.auto,
                        size: isTablet ? 180 : 140,
                        backgroundColor: Colors.white,
                      ),
                    )
                  : const Center(
                      child: Text(
                        "二维码已失效",
                        style: TextStyle(color: Colors.grey, fontSize: 14),
                      ),
                    ),
        ),
        const SizedBox(height: 30),

        // 刷新二维码按钮
        SizedBox(
          width: isTablet ? 200 : 160,
          height: isTablet ? 48 : 44,
          child: ElevatedButton(
            onPressed: qrLoading ? null : refreshQRCode,
            style: ElevatedButton.styleFrom(
              backgroundColor: qrLoading ? Colors.grey : Colors.blueAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(50),
              ),
            ),
            child: Text(
              "🔄 刷新二维码",
              style: TextStyle(
                color: Colors.white,
                fontSize: isTablet ? 16 : 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _inputField(String label, bool obscure, TextEditingController controller, String type, bool isTablet) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: TextStyle(color: Colors.white, fontSize: isTablet ? 16 : 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white70, fontSize: isTablet ? 16 : 14),
        filled: true,
        fillColor: Colors.black45,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(50),
          borderSide: BorderSide.none,
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: isTablet ? 24 : 20,
          vertical: isTablet ? 20 : 16,
        ),
      ),
    );
  }

  Widget _pwdField(bool isTablet) {
    return TextField(
      controller: password,
      obscureText: !showPwd,
      style: TextStyle(color: Colors.white, fontSize: isTablet ? 16 : 14),
      decoration: InputDecoration(
        labelText: "🔒 密码",
        labelStyle: TextStyle(color: Colors.white70, fontSize: isTablet ? 16 : 14),
        filled: true,
        fillColor: Colors.black45,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(50),
          borderSide: BorderSide.none,
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: isTablet ? 24 : 20,
          vertical: isTablet ? 20 : 16,
        ),
        suffixIcon: IconButton(
          icon: Icon(showPwd ? Icons.visibility : Icons.visibility_off, color: Colors.white60),
          onPressed: () => setState(() => showPwd = !showPwd),
        ),
      ),
    );
  }

  Widget _loginButton(bool isTablet) {
    return SizedBox(
      width: double.infinity,
      height: isTablet ? 56 : 50,
      child: ElevatedButton(
        onPressed: loading ? null : doLogin,
        style: ElevatedButton.styleFrom(
          backgroundColor: loading ? Colors.grey : Colors.blueAccent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(50),
          ),
        ),
        child: loading
            ? const CircularProgressIndicator(color: Colors.white)
            : Text(
                "🚀 登录",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isTablet ? 18 : 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }
}