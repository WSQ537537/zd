import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:zdxtapp/config.dart';
import 'package:zdxtapp/utils/toast.dart';

class HelpPage extends StatefulWidget {
  final String type;

  const HelpPage({
    super.key,
    required this.type,
  });

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // 公共状态
  bool loading = false;
  String msg = "";
  Color msgColor = const Color(0xFF2877FF);

  // 邮箱找回 - 步骤控制
  int emailStep = 1; // 1:输入账号 2:输入验证码和新密码
  bool isSendingCode = false; // 发送验证码独立加载

  // 邮箱找回 - 控制器
  final TextEditingController _emailAccountController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _emailCodeController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();

  // 邮箱找回 - 倒计时
  int countdown = 0;
  Timer? countdownTimer;

  // 申诉找回 - 控制器
  final TextEditingController _appealAccountController = TextEditingController();
  String appealCode = "";

  // 申诉查询 - 控制器
  final TextEditingController _appealCodeController = TextEditingController();
  String resultPwd = "";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    countdownTimer?.cancel();
    _emailAccountController.dispose();
    _emailController.dispose();
    _emailCodeController.dispose();
    _newPasswordController.dispose();
    _appealAccountController.dispose();
    _appealCodeController.dispose();
    super.dispose();
  }

  // 返回
  void goBack() {
    Navigator.pop(context);
  }

  // ==============================
  // 邮箱找回 - 发送验证码
  // ==============================
  Future<void> sendEmailCode() async {
    final account = _emailAccountController.text.trim();
    final email = _emailController.text.trim();

    if (account.isEmpty) {
      setState(() {
        msg = "请输入账号";
        msgColor = Colors.red;
      });
      return;
    }
    if (email.isEmpty) {
      setState(() {
        msg = "请输入邮箱";
        msgColor = Colors.red;
      });
      return;
    }

    setState(() {
      isSendingCode = true;
      msg = "";
    });

    try {
      final data = await jsonDecode((await http.post(
        Uri.parse('${Config.baseUrl}/api/user'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
        "action": "sendEmailCode",
        "account": account,
        "email": email,
        "purpose": "reset",
      }),
      )).body);
      if (data['success'] == true) {
        setState(() {
          msg = data['msg'];
          msgColor = Colors.green;
          emailStep = 2;
          countdown = 60;
        });
        startCountdown();
      } else {
        setState(() {
          msg = data['msg'];
          msgColor = Colors.red;
        });
      }
    } catch (e) {
      setState(() {
        msg = "网络错误";
        msgColor = Colors.red;
      });
    } finally {
      setState(() => isSendingCode = false);
    }
  }

  // 开始倒计时
  void startCountdown() {
    countdownTimer?.cancel();
    countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (countdown > 0) {
        setState(() => countdown--);
      } else {
        timer.cancel();
      }
    });
  }

  // ==============================
  // 邮箱找回 - 重置密码
  // ==============================
  Future<void> resetPasswordByEmail() async {
    final account = _emailAccountController.text.trim();
    final email = _emailController.text.trim();
    final code = _emailCodeController.text.trim();
    final newPassword = _newPasswordController.text.trim();

    if (code.isEmpty) {
      setState(() {
        msg = "请输入验证码";
        msgColor = Colors.red;
      });
      return;
    }
    if (newPassword.isEmpty) {
      setState(() {
        msg = "请输入新密码";
        msgColor = Colors.red;
      });
      return;
    }
    if (newPassword.length < 6) {
      setState(() {
        msg = "新密码长度不能少于6位";
        msgColor = Colors.red;
      });
      return;
    }

    setState(() {
      loading = true;
      msg = "";
    });

    try {
      final data = await jsonDecode((await http.post(
        Uri.parse('${Config.baseUrl}/api/user'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
        "action": "resetPasswordByEmail",
        "account": account,
        "email": email,
        "code": code,
        "newPassword": newPassword,
      }),
      )).body);
      if (data['success'] == true) {
        setState(() {
          msg = data['msg'];
          msgColor = Colors.green;
        });
        // 延迟返回登录页
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) Navigator.pop(context);
        });
      } else {
        setState(() {
          msg = data['msg'];
          msgColor = Colors.red;
        });
      }
    } catch (e) {
      setState(() {
        msg = "网络错误";
        msgColor = Colors.red;
      });
    } finally {
      setState(() => loading = false);
    }
  }

  // ==============================
  // 申诉找回 - 提交申诉
  // ==============================
  Future<void> submitForgotPassword() async {
    final account = _appealAccountController.text.trim();
    if (account.isEmpty) {
      setState(() {
        msg = "请输入账号";
        msgColor = Colors.red;
      });
      return;
    }

    setState(() {
      loading = true;
      msg = "";
      appealCode = "";
    });

    try {
      final data = await jsonDecode((await http.post(
        Uri.parse('${Config.baseUrl}/api/user'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
        "action": "submitForgotPassword",
        "account": account,
      }),
      )).body);
      if (data['success'] == true) {
        setState(() {
          appealCode = data['appealCode'];
          msg = data['msg'];
          msgColor = Colors.green;
        });
      } else {
        setState(() {
          msg = data['msg'];
          msgColor = Colors.red;
        });
      }
    } catch (e) {
      setState(() {
        msg = "网络错误";
        msgColor = Colors.red;
      });
    } finally {
      setState(() => loading = false);
    }
  }

  // 复制申诉码
  Future<void> copyAppealCode() async {
    if (appealCode.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: appealCode));
    if (mounted) {
      ToastUtil.showSuccess(context, "复制成功");
    }
  }

  // ==============================
  // 申诉查询 - 查询密码
  // ==============================
  Future<void> queryAppealResult() async {
    final code = _appealCodeController.text.trim();
    if (code.isEmpty) {
      setState(() {
        msg = "请输入申诉码";
        msgColor = Colors.red;
      });
      return;
    }

    setState(() {
      loading = true;
      msg = "";
      resultPwd = "";
    });

    try {
      final data = await jsonDecode((await http.post(
        Uri.parse('${Config.baseUrl}/api/user'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
        "action": "queryAppealResult",
        "appealCode": code,
      }),
      )).body);
      if (data['success'] == true) {
        setState(() {
          resultPwd = data['password'];
          msg = data['msg'];
          msgColor = Colors.green;
        });
      } else {
        setState(() {
          msg = data['msg'];
          msgColor = Colors.red;
        });
      }
    } catch (e) {
      setState(() {
        msg = "网络错误";
        msgColor = Colors.red;
      });
    } finally {
      setState(() => loading = false);
    }
  }

  // 复制密码
  Future<void> copyPassword() async {
    if (resultPwd.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: resultPwd));
    if (mounted) {
      ToastUtil.showSuccess(context, "密码复制成功");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FF),
      body: SafeArea(
        child: Column(
          children: [
            // 标题栏
            _buildTitleBar(),

            // Tab栏
            if (widget.type == "forgot")
              _buildTabBar()
            else
              const SizedBox(height: 20),

            // 内容区域
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    // 根据 type 显示对应页面
                    if (widget.type == "forgot")
                      _buildForgotPasswordView()
                    else
                      _buildAppealQueryView(),

                    // 提示信息
                    if (msg.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: Text(
                          msg,
                          style: TextStyle(color: msgColor, fontSize: 14),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

    // 标题栏
  Widget _buildTitleBar() {
    return SizedBox(
      height: 50,
      child: Row(
        children: [
          // 右移 + 放大
          Padding(
            padding: const EdgeInsets.only(left: 10),
            child: IconButton(
              icon: const Text(
                "←",
                style: TextStyle(fontSize: 22, color: Color(0xFF2877FF)),
              ),
              onPressed: goBack,
            ),
          ),
          // 标题居中
          Expanded(
            child: Center(
              child: Text(
                widget.type == "forgot" ? "找回密码" : "申诉查询密码",
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1D2129),
                ),
              ),
            ),
          ),
          // 右侧占位，保持对称
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  // Tab栏
  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: const Color(0xFF2877FF),
          borderRadius: BorderRadius.circular(12),
        ),
        labelColor: Colors.white,
        unselectedLabelColor: const Color(0xFF666666),
        indicatorSize: TabBarIndicatorSize.tab,
        tabs: const [
          Tab(text: "自主找回"),
          Tab(text: "申诉找回"),
        ],
      ),
    );
  }

  // ==============================
  // 找回密码界面（双标签）
  // ==============================
  Widget _buildForgotPasswordView() {
    return SizedBox(
      height: 500,
      child: TabBarView(
        controller: _tabController,
        children: [
          // 邮箱自主找回
          _buildEmailResetView(),
          // 申诉找回
          _buildAppealResetView(),
        ],
      ),
    );
  }

  // 邮箱自主找回界面
  Widget _buildEmailResetView() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: emailStep == 1
          ? _buildEmailStep1()
          : _buildEmailStep2(),
    );
  }

  // 邮箱找回 - 步骤1：输入账号和邮箱
  Widget _buildEmailStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "请输入账号",
          style: TextStyle(fontSize: 16, color: Color(0xFF333333)),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _emailAccountController,
          decoration: InputDecoration(
            hintText: "请输入账号",
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: const BorderSide(color: Color(0xFFEEEEEE)),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 15),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          "请输入绑定邮箱",
          style: TextStyle(fontSize: 16, color: Color(0xFF333333)),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            hintText: "请输入邮箱地址",
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: const BorderSide(color: Color(0xFFEEEEEE)),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 15),
          ),
        ),
        const SizedBox(height: 30),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2877FF),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            onPressed: isSendingCode ? null : sendEmailCode,
            child: Text(
              isSendingCode ? "发送中.." : "发送验证码",
              style: const TextStyle(fontSize: 16, color: Colors.white),
            ),
          ),
        ),
                const SizedBox(height: 12),
        Center(
          child: Text(
            "若只记得账号，请在申诉找回中找回密码",
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF2877FF),
            ),
          ),
        ),
      ],
    );
  }

  // 邮箱找回 - 步骤2：输入验证码和新密码
  Widget _buildEmailStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "请输入验证码",
          style: TextStyle(fontSize: 16, color: Color(0xFF333333)),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _emailCodeController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: "6位验证码",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: const BorderSide(color: Color(0xFFEEEEEE)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 15),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 120,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: (isSendingCode || countdown > 0) ? Colors.grey : const Color(0xFF2877FF),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                onPressed: (isSendingCode || countdown > 0) ? null : sendEmailCode,
                child: Text(
                  isSendingCode ? "发送中.." : (countdown > 0 ? "${countdown}s" : "重新发送"),
                  style: const TextStyle(fontSize: 14, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text(
          "请输入新密码",
          style: TextStyle(fontSize: 16, color: Color(0xFF333333)),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _newPasswordController,
          obscureText: true,
          decoration: InputDecoration(
            hintText: "请输入新密码（至少6位）",
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: const BorderSide(color: Color(0xFFEEEEEE)),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 15),
          ),
        ),
        const SizedBox(height: 30),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2877FF),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            onPressed: loading ? null : resetPasswordByEmail,
            child: Text(
              loading ? "重置中.." : "重置密码",
              style: const TextStyle(fontSize: 16, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  // 申诉找回界面
  Widget _buildAppealResetView() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Color.fromRGBO(0, 0, 0, 0.06),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "请输入账号",
                style: TextStyle(fontSize: 16, color: Color(0xFF333333)),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _appealAccountController,
                decoration: InputDecoration(
                  hintText: "请输入要申诉的账号",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: const BorderSide(color: Color(0xFFEEEEEE)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 15),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2877FF),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  onPressed: loading ? null : submitForgotPassword,
                  child: Text(
                    loading ? "提交中.." : "提交申诉",
                    style: const TextStyle(fontSize: 16, color: Colors.white),
                  ),
                ),
              ),
              if (appealCode.isNotEmpty) ...[
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F8FF),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Column(
                    children: [
                      const Text("你的申诉码："),
                      const SizedBox(height: 10),
                      Text(
                        appealCode,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2877FF),
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: copyAppealCode,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF2877FF)),
                        ),
                        child: const Text("点击复制"),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          "若账户也不记得，或只记得绑定的邮箱,可发送问题至邮箱1922216262@qq.com来寻求帮助，请注意写明问题或原因以及联系方式等(最好是电话号码,其次可以是邮箱；一般账号会绑定用户昵称或姓名（即备注）或者绑定邮箱提交时一并提交，增加申诉成功率)",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: Color(0xFF999999),
            height: 1.6,
          ),
        ),
      ],
    );
  }

  // ==============================
  // 申诉查询界面
  // ==============================
  Widget _buildAppealQueryView() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "请输入申诉码",
            style: TextStyle(fontSize: 16, color: Color(0xFF333333)),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _appealCodeController,
            decoration: InputDecoration(
              hintText: "请输入6位申诉码",
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: const BorderSide(color: Color(0xFFEEEEEE)),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 15),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2877FF),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              onPressed: loading ? null : queryAppealResult,
              child: Text(
                loading ? "查询中.." : "查询密码",
                style: const TextStyle(fontSize: 16, color: Colors.white),
              ),
            ),
          ),
          if (resultPwd.isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: const Color(0xFFE8FBF0),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Column(
                children: [
                  const Text("你的密码是："),
                  const SizedBox(height: 10),
                  Text(
                    resultPwd,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2877FF),
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: copyPassword,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF2877FF)),
                    ),
                    child: const Text("点击复制密码"),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "（申诉码仅限使用一次）",
                    style: TextStyle(fontSize: 12, color: Color(0xFF999999)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
