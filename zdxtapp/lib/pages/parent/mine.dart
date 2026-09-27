import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:zdxtapp/config.dart';
import 'package:zdxtapp/utils/toast.dart';

import 'package:url_launcher/url_launcher.dart';
import '../../widgets/user_agreement.dart'; // ✅ 用户声明：精确清理用户键

class MinePage extends StatefulWidget {
  const MinePage({super.key});

  @override
  State<MinePage> createState() => _MinePageState();
}

class _MinePageState extends State<MinePage> {
  final String baseUrl = Config.baseUrl;
  String currentAccount = "";
  String currentPassword = "";
  String currentEmail = "";
  bool emailLoaded = false;
  bool showPassword = false;

  // 弹窗显示控制
  bool showSetting = false;
  bool showAccount = false;
  bool showBindStudent = false;
  bool showChangePwd = false;
  bool showDeclare = false;

  // 绑定学生
  List boundStudents = [];
  TextEditingController stuAccountCtrl = TextEditingController();
  TextEditingController stuPwdCtrl = TextEditingController();
  bool showStuPwd = false;

  // 修改密码
  TextEditingController oldPwdCtrl = TextEditingController();
  TextEditingController newPwdCtrl = TextEditingController();
  TextEditingController confirmPwdCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final userInfo = prefs.getString("userInfo");
    if (userInfo != null) {
      final parsed = jsonDecode(userInfo);
      setState(() {
        currentAccount = parsed["account"] ?? "";
        // 安全红线：已不再持久化明文密码，UI 展示"已加密"占位
        currentPassword = "";
      });
    }
  }

  Future<void> _refreshEmailBind() async {
    if (currentAccount.isEmpty) return;
    setState(() {
      emailLoaded = false;
    });

    try {
      final res = await jsonDecode((await http.post(
        Uri.parse("$baseUrl/api/user"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "action": "checkEmailBind",
          "account": currentAccount,
        }),
      )).body);
      final data = res;
      if (mounted && data["success"] == true) {
        setState(() {
          currentEmail = data["email"] ?? "";
          emailLoaded = true;
        });
      } else if (mounted) {
        setState(() {
          currentEmail = "";
          emailLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          currentEmail = "";
          emailLoaded = true;
        });
      }
    }
  }

  Future<void> _confirmUnbindEmail() async {
    if (!emailLoaded) {
      _showToast("请稍候再试");
      return;
    }
    if (currentEmail.isEmpty) {
      _showToast("当前未绑定邮箱");
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("确认解绑邮箱"),
          content: Text("确定要解绑当前邮箱 $currentEmail 吗？"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("取消")),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("解绑")),
          ],
        );
      },
    );

    if (confirm != true) return;

    try {
      final res = await jsonDecode((await http.post(
        Uri.parse("$baseUrl/api/user"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "action": "unbindEmail",
          "account": currentAccount,
        }),
      )).body);
      final data = res;
      if (data["success"] == true) {
        _showToast("邮箱解绑成功");
        setState(() {
          currentEmail = "";
        });
      } else {
        _showToast(data["msg"] ?? "解绑失败");
      }
    } catch (_) {
      _showToast("网络异常，请重试");
    }
  }

  // 关闭所有弹窗
  void closeAll() {
    setState(() {
      showSetting = false;
      showAccount = false;
      showBindStudent = false;
      showChangePwd = false;
      showDeclare = false;
    });
  }

  // 获取已绑定学生
  Future<void> getBoundStudents() async {
    final prefs = await SharedPreferences.getInstance();
    final userInfoStr = prefs.getString("userInfo");
    if (userInfoStr == null) return;
    final userInfo = jsonDecode(userInfoStr);
    final parentAccount = userInfo["account"] ?? "";

    final res = await jsonDecode((await http.post(
        Uri.parse("$baseUrl/api/user"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
        "action": "getParentBoundStudents",
        "parentAccount": parentAccount,
      }),
      )).body);

    final data = res;
    if (data["success"] == true) {
      setState(() {
        boundStudents = data["data"] ?? [];
      });
    }
  }

  // 绑定学生
  Future<void> bindStudent() async {
    final prefs = await SharedPreferences.getInstance();
    final userInfoStr = prefs.getString("userInfo");
    if (userInfoStr == null) return;
    final parentAccount = jsonDecode(userInfoStr)["account"] ?? "";
    final stuAcc = stuAccountCtrl.text.trim();
    final stuPwd = stuPwdCtrl.text.trim();

    if (stuAcc.isEmpty || stuPwd.isEmpty) {
      _showToast("请填写学生账号密码");
      return;
    }

    final res = await jsonDecode((await http.post(
        Uri.parse("$baseUrl/api/user"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
        "action": "parentBindStudent",
        "parentAccount": parentAccount,
        "studentAccount": stuAcc,
        "studentPassword": stuPwd,
      }),
      )).body);

    final data = res;
    if (data["success"] == true) {
      _showToast("绑定成功");
      stuAccountCtrl.clear();
      stuPwdCtrl.clear();
      getBoundStudents();
    } else {
      _showToast(data["msg"] ?? "绑定失败");
    }
  }

  // 解绑学生
  Future<void> unbindStudent(String stuAcc) async {
    final prefs = await SharedPreferences.getInstance();
    final userInfoStr = prefs.getString("userInfo");
    if (userInfoStr == null) return;
    final parentAccount = jsonDecode(userInfoStr)["account"] ?? "";

    final res = await jsonDecode((await http.post(
        Uri.parse("$baseUrl/api/user"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
        "action": "parentUnbindStudent",
        "parentAccount": parentAccount,
        "studentAccount": stuAcc,
      }),
      )).body);

    final data = res;
    if (data["success"] == true) {
      _showToast("解绑成功");
      getBoundStudents();
    } else {
      _showToast(data["msg"] ?? "解绑失败");
    }
  }

  // 修改密码
  Future<void> changePwd() async {
    final oldPwd = oldPwdCtrl.text.trim();
    final newPwd = newPwdCtrl.text.trim();
    final confirmPwd = confirmPwdCtrl.text.trim();

    if (oldPwd.isEmpty || newPwd.isEmpty || confirmPwd.isEmpty) {
      _showToast("请填写完整");
      return;
    }
    if (newPwd != confirmPwd) {
      _showToast("两次密码不一致");
      return;
    }

    final res = await jsonDecode((await http.post(
        Uri.parse("$baseUrl/api/user"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
        "action": "updatePassword",
        "account": currentAccount,
        "oldPassword": oldPwd,
        "newPassword": newPwd,
      }),
      )).body);

    final data = res;
    if (data["success"] == true) {
      _showToast("修改成功，请重新登录");
      closeAll();
      Future.delayed(const Duration(seconds: 1), logout);
    } else {
      _showToast(data["msg"] ?? "修改失败");
    }
  }

  // 退出登录
  Future<void> logout() async {
    // 🔥 精确清理用户会话 key（userInfo 等），保留声明一次性标记 agreement_ever_shown
    await UserAgreementWidget.removeUserKeys();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, "/login", (route) => false);
    }
  }

  void _showToast(String msg) {
    ToastUtil.show(context, msg);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final cardSize = (screenWidth - 80 - 24) / 3; // 左右各20padding + 2个间距12

    // 功能卡片
    final items = [
      {'icon': Icons.settings_outlined, 'label': '设置', 'onTap': () => setState(() => showSetting = true)},
      {'icon': Icons.update_outlined, 'label': '检查更新', 'onTap': () => Navigator.pushNamed(context, "/update")},
      {'icon': Icons.language_outlined, 'label': '官网', 'onTap': _openWebsite},
      {'icon': Icons.logout_outlined, 'label': '退出登录', 'onTap': logout},
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // 主界面：整体居中
          Center(
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: items.map((item) {
                    return _buildCard(
                      icon: item['icon'] as IconData,
                      label: item['label'] as String,
                      onTap: item['onTap'] as VoidCallback,
                      size: cardSize,
                    );
                  }).toList(),
                ),
              ),
            ),
          ),

          // 遮罩
          if (showSetting || showAccount || showBindStudent || showChangePwd || showDeclare)
            ModalBarrier(
              color: Colors.black54,
              dismissible: true,
              onDismiss: closeAll,
            ),

          // 设置弹窗
          _buildModal(showSetting,
            title: "设置",
            content: Column(
              children: [
                _buildModalItem("账户信息", () {
                  setState(() {
                    showSetting = false;
                    showAccount = true;
                  });
                  _refreshEmailBind();
                }),
                _buildModalItem("绑定学生", () {
                  setState(() {
                    showSetting = false;
                    showBindStudent = true;
                  });
                  getBoundStudents();
                }),
                _buildModalItem("修改密码", () {
                  setState(() {
                    showSetting = false;
                    showChangePwd = true;
                  });
                }),
                _buildModalItem("用户声明", () {
                  setState(() {
                    showSetting = false;
                    showDeclare = true;
                  });
                }),
              ],
            ),
          ),

          // 账户信息
          _buildModal(showAccount,
            title: "账户信息",
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("账号：$currentAccount", style: const TextStyle(fontSize: 16, color: Colors.black87)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        "密码：${showPassword ? (currentPassword.isNotEmpty ? currentPassword : '已加密') : '******'}",
                        style: const TextStyle(fontSize: 16, color: Colors.black87),
                      ),
                    ),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: Icon(showPassword ? Icons.visibility_off : Icons.visibility, color: const Color(0xFF2877FF)),
                      onPressed: () => setState(() => showPassword = !showPassword),
                      splashRadius: 20,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  "邮箱：${!emailLoaded ? '加载中...' : (currentEmail.isEmpty ? '未绑定' : currentEmail)}",
                  style: const TextStyle(fontSize: 16, color: Colors.black87),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: currentEmail.isNotEmpty ? const Color(0xFFD32F2F) : const Color(0xFF2877FF),
                        ),
                        onPressed: currentEmail.isNotEmpty ? _confirmUnbindEmail : () => Navigator.pushReplacementNamed(context, "/bindemail"),
                        child: Text(currentEmail.isNotEmpty ? "解绑邮箱" : "绑定邮箱"),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: closeAll,
                        child: const Text("确定"),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 绑定学生
          _buildModal(showBindStudent,
            title: "绑定学生",
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("已绑定学生", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
                  const SizedBox(height: 10),
                  boundStudents.isEmpty
                      ? const Text("暂无绑定学生", style: TextStyle(color: Colors.black54))
                      : Column(
                          children: boundStudents.map((stu) {
                            return ListTile(
                              title: Text("账号：${stu["account"]}", style: const TextStyle(color: Colors.black87)),
                              subtitle: Text("备注：${stu["remark"] != null && (stu["remark"] as String).isNotEmpty ? stu["remark"] : "无"}", style: const TextStyle(color: Colors.black54)),
                              trailing: TextButton(
                                child: const Text("解绑", style: TextStyle(color: Colors.red)),
                                onPressed: () => unbindStudent(stu["account"]),
                              ),
                            );
                          }).toList(),
                        ),
                  const Divider(height: 30),
                  const Text("添加新绑定", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: stuAccountCtrl,
                    decoration: const InputDecoration(labelText: "学生账号"),
                  ),
                  TextField(
                    controller: stuPwdCtrl,
                    obscureText: !showStuPwd,
                    decoration: InputDecoration(
                      labelText: "学生密码",
                      suffixIcon: IconButton(
                        icon: Icon(showStuPwd ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => showStuPwd = !showStuPwd),
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () {
                            setState(() => showBindStudent = false);
                            stuAccountCtrl.clear();
                            stuPwdCtrl.clear();
                          },
                          child: const Text("取消"),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: bindStudent,
                          child: const Text("确定绑定"),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // 修改密码
          _buildModal(showChangePwd,
            title: "修改密码",
            content: Column(
              children: [
                TextField(controller: oldPwdCtrl, obscureText: true, decoration: const InputDecoration(labelText: "原密码")),
                TextField(controller: newPwdCtrl, obscureText: true, decoration: const InputDecoration(labelText: "新密码")),
                TextField(controller: confirmPwdCtrl, obscureText: true, decoration: const InputDecoration(labelText: "确认新密码")),
                const SizedBox(height: 15),
                Row(
                  children: [
                    Expanded(child: TextButton(onPressed: closeAll, child: const Text("取消"))),
                    Expanded(child: ElevatedButton(onPressed: changePwd, child: const Text("确认修改"))),
                  ],
                ),
              ],
            ),
          ),

          // 用户声明
          if (showDeclare)
            Center(
              child: Container(
                width: 320,
                // 🔥 核心修复：设置固定最大高度，避免弹窗过高
                constraints: const BoxConstraints(
                  maxHeight: 500, // 最大高度500px
                ),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "用户声明",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const Divider(height: 20),
                    // 🔥 核心修复：使用 Expanded + SingleChildScrollView 实现内容滚动
                    Expanded(
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            """
    为规范智答星途平台（以下简称“本平台”）使用秩序，保障管理员、学生、家长全体用户的合法权益，明确平台与用户双方的权利及义务，所有用户在登录、使用平台服务前，需认真阅读并自愿遵守本声明。用户登录、操作及使用本平台服务，即视为已完整知晓、认可并自愿遵守本声明全部条款。
一、平台服务说明与维护规则
1. 本平台是面向教育场景的移动端综合服务平台，分管理员、学生、家长三类角色，权限与功能独立区分，可满足教学管理、自主学习、家校监护全流程数字化需求，核心涵盖考试管理、视频学习、AI助手、课堂签到、学情统计、消息通知、意见反馈等服务。
2. 平台支持三端角色切换登录，各角色对应专属使用权限，AI助手、账号管理、版本更新、VaultBox资源宝库等功能为全用户通用服务。
3. 平台每日23:00至次日06:00进行服务器停机维护、系统升级与数据检修，该时段平台可能无法登录、访问，所有功能临时暂停，由此产生的使用不便，敬请用户谅解。
二、账号安全规范
1. 所有用户需合法合规使用个人账号，妥善保管账号、密码及绑定邮箱，对账号下所有操作承担全部责任。平台初始统一密码为123，用户首次登录后，必须立即前往个人中心修改专属密码，做好账号安全防护，严防密码泄露、账号异常。
2. 用户可自主完成邮箱绑定、密码修改、密码找回与申诉查询等操作，严禁转借、共享、售卖账号，严禁冒用他人账号登录、窃取数据、违规操作。因账号保管不当、违规共享引发的一切问题，由用户自行承担责任。
3. 家长用户仅可合规绑定、监护直系学生账号，严禁恶意绑定、解绑他人账号、窃取无关学情数据。管理员用户需合规开展运维工作，不得滥用权限篡改、删除用户数据或发布违规内容。
三、使用权限与行为准则
1. 本平台软件及配套资源仅限指定内部群体使用，所有用户严禁私自对外转发、分享、售卖、转借平台安装包、账号权限及内部资料，禁止一切私自外传扩散行为。
2. 用户使用平台需遵守国家法律法规及内部管理规范，诚信参与考试、签到、学习等各项操作，严禁作弊、代考、虚假签到、刷取时长等违规行为。
3. 用户使用AI助手、反馈留言等功能时，不得生成、发布、传播违法违规、低俗侵权、违背公序良俗的内容，禁止利用AI功能作弊、抄袭、恶意创作，禁止恶意提交无效反馈干扰平台运维。
4. 用户不得恶意攻击、入侵、破解平台系统，不得爬取、窃取平台资源与用户隐私数据。一经查实存在违规违法使用行为，平台将直接封禁账号、取消全部使用权限。
5. 若用户私自外传平台软件、账号权限及内部资源，由此引发的一切财产损失、人身纠纷、法律责任均由当事人自行承担，平台及运营团队不承担任何连带责任。
四、知识产权与隐私保护
1. 本平台所有程序、界面、题库、课程、资源等知识产权均归平台所有，受相关法律法规保护。用户仅可用于内部非商业性的学习、教学、监护使用，严禁私自转载、篡改、商用、售卖平台各类资源。
2. 管理员上传的试卷、视频、通知等内容需合法合规、拥有授权，因用户上传内容引发的知识产权纠纷，由用户自行承担全部责任。
3. 平台依法保护用户账号、个人信息、学情数据等隐私信息，仅用于教学与服务用途，非经法定要求不向第三方泄露。管理员、家长用户需合规查看、严格保密学生学情数据，严禁外泄商用。
五、服务变更、免责与解释权
1. 平台可根据运营优化、系统升级及政策调整等需求，适时调整维护时间、平台功能、服务内容与使用规则，无需对用户单独另行通知，调整内容将通过平台公示后生效。
2. 因网络故障、系统维护升级、不可抗力等非平台主观因素导致服务中断、数据临时异常的，平台不承担相关损失；因用户自身违规操作、账号保管不当、私自外传资源权限等自身原因引发的问题与损失，由用户自行承担全部责任。
3. 平台对用户一切违规行为，有权视情节采取警告、限制功能、暂停或封禁账号、清除违规内容等处置措施。
4. 本声明所有条款的最终解释权归智答星途开发运营团队所有。
六、附则
1. 本声明为平台服务有效组成部分，所有用户使用平台服务即视为认可并自愿遵守全部条款。
2. 用户若对平台服务及本声明条款存在疑问，可通过平台意见反馈渠道咨询反馈。
本人已认真阅读、充分理解并完全知晓以上所有条款，自愿遵守各项规定，合规使用本平台。
                                                                   ---智答星途官方
""",
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.6,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: closeAll,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xff1890ff),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text("我知道了"),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // 3D 卡片样式
  // 🔥 新增：打开官网
  void _openWebsite() async {
    final url = Uri.parse('https://wsq537537.github.io/zd/index');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      _showToast("无法打开官网");
    }
  }

  // 方形磨砂卡片
  Widget _buildCard({required IconData icon, required String label, required VoidCallback onTap, required double size}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28, color: const Color(0xFF2B7DFF)),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF333333)),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // 弹窗封装
  Widget _buildModal(bool show, {String? title, Widget? content, bool showConfirm = false}) {
    if (!show) return const SizedBox();
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 25),
        padding: const EdgeInsets.all(20),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height - MediaQuery.of(context).padding.top - MediaQuery.of(context).padding.bottom - 80,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (title != null) ...[
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 15),
              ],
              if (content != null) ...[content],
              if (showConfirm) ...[
                const SizedBox(height: 15),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(onPressed: closeAll, child: const Text("确定")),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // 菜单项
  Widget _buildModalItem(String text, VoidCallback onTap) {
    return ListTile(
      title: Text(text, textAlign: TextAlign.center),
      onTap: onTap,
    );
  }
}
