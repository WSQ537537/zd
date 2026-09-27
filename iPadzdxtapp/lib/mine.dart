import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'config.dart';
import 'utils/toast.dart';

// 🔥 改造为可嵌入左侧面板的组件
class MinePanel extends StatefulWidget {
  final VoidCallback? onClose; // 关闭回调
  
  const MinePanel({super.key, this.onClose});

  @override
  State<MinePanel> createState() => _MinePanelState();
}

class _MinePanelState extends State<MinePanel> {
  String currentAccount = "";
  final String baseUrl = Config.baseUrl;

  bool showSetting = false;
  bool showAccount = false;
  bool showPwd = false;
  bool showDeclare = false;

  final oldPwd = TextEditingController();
  final newPwd = TextEditingController();
  final confirmPwd = TextEditingController();

  // 🔥 新增：15秒无操作自动退出
  Timer? _autoCloseTimer;
  static const int _autoCloseSeconds = 15;

  @override
  void initState() {
    super.initState();
    loadUser();
    _startAutoCloseTimer(); // 🔥 启动自动退出计时器
  }

  @override
  void dispose() {
    _autoCloseTimer?.cancel(); // 🔥 取消计时器
    oldPwd.dispose();
    newPwd.dispose();
    confirmPwd.dispose();
    super.dispose();
  }

  // 🔥 新增：启动自动退出计时器
  void _startAutoCloseTimer() {
    _autoCloseTimer?.cancel();
    _autoCloseTimer = Timer(const Duration(seconds: _autoCloseSeconds), () {
      if (mounted && widget.onClose != null) {
        debugPrint('⏰ 设置页面15秒无操作，自动退出');
        widget.onClose!();
      }
    });
  }

  // 🔥 新增：用户操作时重置计时器
  void _resetAutoCloseTimer() {
    _startAutoCloseTimer();
  }

  Future<void> loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    final user = prefs.getString("userInfo");
    if (user != null) {
      setState(() {
        currentAccount = jsonDecode(user)["account"] ?? "";
      });
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) {
      Navigator.pushReplacementNamed(context, "/login");
    }
  }

  void closeAll() {
    _resetAutoCloseTimer(); // 🔥 重置计时器
    setState(() {
      showSetting = false;
      showAccount = false;
      showPwd = false;
      showDeclare = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
        ),
      ),
      child: Stack(
        children: [
          // 主内容区域
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 顶部标题栏
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "个人中心",
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    if (widget.onClose != null)
                      GestureDetector(
                        onTap: () {
                          _resetAutoCloseTimer(); // 🔥 重置计时器
                          widget.onClose!();
                        },
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // 功能卡片列表
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      _buildMenuCard("⚙️ 设置", () {
                        _resetAutoCloseTimer(); // 🔥 重置计时器
                        setState(() => showSetting = true);
                      }),
                      const SizedBox(height: 12),
                      _buildMenuCard("🚪 退出登录", () {
                        _resetAutoCloseTimer(); // 🔥 重置计时器
                        logout();
                      }),
                    ],
                  ),
                ),
              ),
              // 底部账号信息 - 放大字体，保持居中
              Padding(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: Text(
                    "当前账号：$currentAccount",
                    style: TextStyle(
                      fontSize: 16,  // 🔥 放大字体
                      color: Colors.white.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),

          // 🔥 弹窗遮罩层（覆盖整个左侧面板）
          if (showAnyModal)
            Positioned.fill(
              child: ModalBarrier(
                color: Colors.black.withValues(alpha: 0.5),
                dismissible: false,
              ),
            ),

          // 🔥 弹窗内容（居中显示在左侧面板内）
          if (showSetting) _buildSettingModal(),
          if (showAccount) _buildAccountModal(),
          if (showPwd) _buildPwdModal(),
          if (showDeclare) _buildDeclareModal(),
        ],
      ),
    );
  }

  bool get showAnyModal => showSetting || showAccount || showPwd || showDeclare;

  Widget _buildMenuCard(String text, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              text,
              style: const TextStyle(fontSize: 16, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingModal() {
    return _buildModal(
      title: "设置",
      children: [
        // 🔥 移除账户信息功能
        // _buildMenuItem("账户信息", () {
        //   setState(() {
        //     showSetting = false;
        //     showAccount = true;
        //   });
        // }),
        _buildMenuItem("修改密码", () {
          _resetAutoCloseTimer(); // 🔥 重置计时器
          setState(() {
            showSetting = false;
            showPwd = true;
          });
        }),
        _buildMenuItem("用户声明", () {
          _resetAutoCloseTimer(); // 🔥 重置计时器
          setState(() {
            showSetting = false;
            showDeclare = true;
          });
        }),
      ],
    );
  }

  Widget _buildAccountModal() {
    return _buildModal(
      title: "账户信息",
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text("当前账号：$currentAccount"),
        ),
        _buildButton("确定", () {
          _resetAutoCloseTimer(); // 🔥 重置计时器
          closeAll();
        }),
      ],
    );
  }

  Widget _buildPwdModal() {
    return _buildModal(
      title: "修改密码",
      children: [
        _buildInput("原密码", oldPwd, onChanged: (_) => _resetAutoCloseTimer()),
        _buildInput("新密码", newPwd, onChanged: (_) => _resetAutoCloseTimer()),
        _buildInput("确认密码", confirmPwd, onChanged: (_) => _resetAutoCloseTimer()),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _buildButton("取消", () {
              _resetAutoCloseTimer(); // 🔥 重置计时器
              closeAll();
            })),
            const SizedBox(width: 10),
            Expanded(
              child: _buildButton("提交", () async {
                _resetAutoCloseTimer();
                final old = oldPwd.text.trim();
                final newP = newPwd.text.trim();
                final confirm = confirmPwd.text.trim();
                
                if (old.isEmpty || newP.isEmpty || confirm.isEmpty) {
                  ToastUtil.show(context, "请填写完整信息");
                  return;
                }
                if (newP != confirm) {
                  ToastUtil.show(context, "两次密码不一致");
                  return;
                }
                if (newP.length < 6) {
                  ToastUtil.show(context, "密码长度不能少于6位");
                  return;
                }
                
                ToastUtil.show(context, "提交中...");
                
                try {
                  final prefs = await SharedPreferences.getInstance();
                  final userInfo = prefs.getString("userInfo");
                  if (userInfo == null) return;
                  final account = jsonDecode(userInfo)["account"] ?? "";
                  
                  final res = await http.post(
                    Uri.parse("$baseUrl/api/user"),
                    headers: {"Content-Type": "application/json"},
                    body: jsonEncode({
                      "action": "updatePassword",
                      "account": account,
                      "oldPassword": old,
                      "newPassword": newP,
                    }),
                  );
                  
                  final data = jsonDecode(res.body);
                  if (data["success"] == true) {
                    if (mounted) {
                      ToastUtil.showSuccess(context, "密码修改成功");
                      closeAll();
                      oldPwd.clear();
                      newPwd.clear();
                      confirmPwd.clear();
                    }
                  } else {
                    if (mounted) {
                      ToastUtil.show(context, data["msg"] ?? "修改失败");
                    }
                  }
                } catch (e) {
                  if (mounted) {
                    ToastUtil.show(context, "网络异常，请重试");
                  }
                }
              }),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDeclareModal() {
    return _buildModal(
      title: "用户声明",
      children: [
        const Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: Text(
              """所有使用智答星途平台的用户，需仔细阅读并自愿遵守以下全部条款：

1.服务器维护提示
每日晚间23:00至次日06:00,平台将进行服务器停机维护、系统升级与数据检修,此时间段内平台可能无法正常登录、访问及使用,多项功能临时暂停。由此带来的使用不便,敬请各位用户谅解。

2.账号安全提醒
平台账号默认初始密码统一为123请所有用户首次登录后,立即前往个人设置页面修改专属密码,妥善保管账号信息，做好账号防护,避免密码泄露造成账号异常。

3.使用权限规定
本软件及相关配套资源仅限指定内部群体使用，严禁私自对外转发、分享、传播、转借、售卖软件安装包、账号权限以及平台内部相关内容,禁止私自向外扩散。

4.相关免责说明
若用户违反规定私自外传本软件及使用权限，由此引发的一切人身纠纷、财产损失、法律责任等所有后果,均由私自外传者本人全权承担。本软件开发团队及相关工作人员不承担任何连带责任与赔偿责任。

5.用户使用准则
用户使用本平台期间，需遵守相关法律法规及内部管理规范,不得利用平台开展违规、违法等不良行为,一经查实将直接封禁账号,取消使用权限。

6.规则与解释权
本平台可根据实际运营情况，适时调整维护时间、平台功能及使用规则,不再另行单独通知。本用户声明所有内容,最终解释权归智答星途开发运营团队所有。

本人已认真阅读并完全知晓以上所有条款，自愿遵守各项规定合规使用本平台。""",
              style: TextStyle(fontSize: 13, height: 1.6),
            ),
          ),
        ),
        _buildButton("我知道了", () {
          _resetAutoCloseTimer(); // 🔥 重置计时器
          closeAll();
        }),
      ],
    );
  }

  Widget _buildModal({required String title, required List<Widget> children}) {
    return Center(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.25, // 🔥 适配左侧面板宽度
        constraints: const BoxConstraints(maxWidth: 280),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 🔥 标题栏，包含关闭按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    _resetAutoCloseTimer(); // 🔥 重置计时器
                    closeAll();
                  },
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.close,
                      size: 18,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem(String text, VoidCallback onTap) {
    return ListTile(
      title: Text(text),
      onTap: onTap,
    );
  }

  Widget _buildInput(String hint, TextEditingController ctrl, {ValueChanged<String>? onChanged}) {
    return TextField(
      controller: ctrl,
      onChanged: onChanged, // 🔥 添加 onChanged 回调
      decoration: InputDecoration(
        hintText: hint,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  Widget _buildButton(String text, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 40),
      ),
      child: Text(text),
    );
  }
}

// 🔥 保留原有的 MinePage 用于兼容（如果需要独立页面跳转）
class MinePage extends StatelessWidget {
  const MinePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0F172A),
      body: MinePanel(),
    );
  }
}
