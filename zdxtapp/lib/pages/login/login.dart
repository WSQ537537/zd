import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:zdxtapp/config.dart';
import 'help.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../main.dart'; // ✅ 导入main.dart以使用resetWebSocketConnection和appStateKey
import '../../widgets/user_agreement.dart'; // ✅ 用户声明：精确清理用户键

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  int currentRole = 2;
  final TextEditingController account = TextEditingController();
  final TextEditingController password = TextEditingController();
  String msg = "";
  bool loading = false;
  bool showPwd = false;

  @override
  void initState() {
    super.initState();
  }

  void switchRole(int role) {
    setState(() => currentRole = role);
  }

  void handleInputClick(String type) {
    // Input click handling logic can remain if needed for other purposes, 
    // but emoji logic is removed.
  }

  Future<void> doLogin() async {
    final acc = account.text.trim();
    final pwd = password.text.trim();

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
          "selected_role": currentRole,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final res = jsonDecode(response.body);

        if (res["success"] == true) {
          // ✅ 登录成功前，先断开旧的WebSocket连接
          resetWebSocketConnection();

          final sp = await SharedPreferences.getInstance();
          final userInfo = {
            "account": acc,
            "role": currentRole,
            "remark": res["remark"] ?? "",
            "loginTime": DateTime.now().millisecondsSinceEpoch,
          };
          await sp.setString("userInfo", jsonEncode(userInfo));

          // 🔥 登录成功后立即重连 WebSocket
          appStateKey.currentState?.connectWebSocket(userInfo);

          // 管理员角色跳过邮箱绑定检测，直接进入首页
          if (currentRole == 1) {
            if (mounted) Navigator.pushReplacementNamed(context, "/admin/home");
            return;
          }

          // 学生/家长：检查邮箱绑定状态，未绑定则跳转到绑定页（页面可返回单次跳过）
          final emailCheckRes = await http.post(
            Uri.parse("${Config.baseUrl}/api/user"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "action": "checkEmailBind",
              "account": acc,
            }),
          ).timeout(const Duration(seconds: 10));

          if (emailCheckRes.statusCode == 200) {
            final emailData = jsonDecode(emailCheckRes.body);
            if (emailData["success"] == true && emailData["hasEmail"] != true) {
              // 未绑定邮箱，跳转到邮箱绑定页面；bind 页面有返回按钮可单次跳过
              if (mounted) {
                Navigator.pushReplacementNamed(context, "/bindemail");
                return;
              }
            }
          }

          // 已绑定或检查接口异常：继续按角色进入对应首页
          if (mounted) {
            if (currentRole == 2) {
              Navigator.pushReplacementNamed(context, "/student/home");
            } else {
              Navigator.pushReplacementNamed(context, "/parent/home");
            }
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

  // ====================== 退出登录（清空状态） ======================
  Future<void> logout() async {
    // ✅ 退出登录前，先断开WebSocket连接
    resetWebSocketConnection();

    // 🔥 精确清理用户会话 key（userInfo 等），保留声明一次性标记 agreement_ever_shown
    await UserAgreementWidget.removeUserKeys();
    if (mounted) {
      Navigator.pushReplacementNamed(context, "/login");
    }
  }

  @override
  void dispose() {
    account.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 80),
            child: Column(
              children: [
                const SizedBox(height: 60),
                const Text(
                  "智答星途",
                  style: TextStyle(
                    fontSize: 42,
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
                const SizedBox(height: 6),
                const Text(
                  "智能问答·星途相伴",
                  style: TextStyle(color: Colors.white60, fontSize: 16),
                ),
                const SizedBox(height: 50),

                _roleBar(),
                const SizedBox(height: 40),

                _inputField("👤 账号", false, account, "account"),
                const SizedBox(height: 25),

                _pwdField(),
                const SizedBox(height: 15),

                if (msg.isNotEmpty)
                  Text(
                    msg,
                    style: const TextStyle(color: Color(0xFFFF9F4A), fontSize: 14),
                  ),
                const SizedBox(height: 30),

                _loginButton(),
                const SizedBox(height: 60),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const HelpPage(type: "forgot"),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                        ),
                        child: const Text(
                          "🔐 忘记密码",
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const HelpPage(type: "appeal"),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                        ),
                        child: const Text(
                          "📋 申诉查询",
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _roleBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black38,
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: Colors.white12),
      ),
      padding: const EdgeInsets.all(6),
      child: Row(
        children: [
          _roleBtn("管理端", 1),
          _roleBtn("学生端", 2),
          _roleBtn("家长端", 3),
        ],
      ),
    );
  }

  Widget _roleBtn(String text, int role) {
    return Expanded(
      child: GestureDetector(
        onTap: () => switchRole(role),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: currentRole == role ? Colors.blueAccent : Colors.transparent,
            borderRadius: BorderRadius.circular(50),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: currentRole == role ? Colors.white : Colors.white60,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _inputField(String label, bool obscure, TextEditingController controller, String type) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white),
      onTap: () => handleInputClick(type),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        filled: true,
        fillColor: Colors.black45,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(50),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
    );
  }

  Widget _pwdField() {
    return TextField(
      controller: password,
      obscureText: !showPwd,
      style: const TextStyle(color: Colors.white),
      onTap: () => handleInputClick("pwd"),
      decoration: InputDecoration(
        labelText: "🔒 密码",
        labelStyle: const TextStyle(color: Colors.white70),
        filled: true,
        fillColor: Colors.black45,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(50),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        suffixIcon: IconButton(
          icon: Icon(showPwd ? Icons.visibility : Icons.visibility_off, color: Colors.white60),
          onPressed: () => setState(() => showPwd = !showPwd),
        ),
      ),
    );
  }

  Widget _loginButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
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
            : const Text(
                "🚀 登录",
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
      ),
    );
  }
}