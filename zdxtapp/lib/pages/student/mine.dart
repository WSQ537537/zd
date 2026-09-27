import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:zdxtapp/config.dart';
import 'package:zdxtapp/utils/toast.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../widgets/user_agreement.dart'; // ✅ 用户声明：精确清理用户键

class MinePage extends StatefulWidget {
  const MinePage({super.key});

  @override
  State<MinePage> createState() => _MinePageState();
}

class _MinePageState extends State<MinePage> {
  String currentAccount = "";
  String currentPassword = "";
  String currentEmail = "";
  bool emailLoaded = false;
  bool showPassword = false;
  final String baseUrl = Config.baseUrl;

  bool showSetting = false;
  bool showAccount = false;
  bool showPwd = false;
  bool showDeclare = false;
  bool showSign = false;
  bool showCodePanel = false;
  bool showScanner = false;
  bool _isScanning = false;
  int signTab = 0; // 0=现场签到, 1=记录查询
  List<dynamic> signHistory = [];
  bool signHistoryLoading = false;
  // 签到统计（按科目）
  Map<String, int> signTotalBySubject = {};
  Map<String, int> signPresentBySubject = {};
  Map<String, int> signAbsentBySubject = {};
  // 按科目分组的签到数据（key 顺序保证：语文→数学→英语→其他）
  Map<String, List<dynamic>> signBySubject = {};
  // 当前选中的科目标签
  static const List<String> _subjectTabs = ['语文', '数学', '英语', '其他'];
  String selectedSubject = '语文';
  // 考试登录相关状态
  bool showExamLoginScanner = false;
  bool showExamConfirm = false;
  String scannedQrkey = "";

  final oldPwd = TextEditingController();
  final newPwd = TextEditingController();
  final confirmPwd = TextEditingController();
  final codeCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    loadUser();
  }

  @override
  void dispose() {
    oldPwd.dispose();
    newPwd.dispose();
    confirmPwd.dispose();
    codeCtrl.dispose();
    super.dispose();
  }

  Future<void> loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    final user = prefs.getString("userInfo");
    if (user != null) {
      dynamic parsed;
      try {
        parsed = jsonDecode(user);
      } catch (_) {
        parsed = null;
      }
      if (parsed is Map) {
        setState(() {
          currentAccount = (parsed["account"] ?? "").toString();
          // 安全红线：已不再持久化明文密码，UI 展示"已加密"占位
          currentPassword = "";
        });
      }
    }
  }

  Future<void> _changePassword() async {
    final old = oldPwd.text.trim();
    final new1 = newPwd.text.trim();
    final new2 = confirmPwd.text.trim();
    if (old.isEmpty || new1.isEmpty) {
      _showToast("请填写原密码和新密码");
      return;
    }
    if (new1.length < 6) {
      _showToast("新密码长度不能少于6位");
      return;
    }
    if (new1 != new2) {
      _showToast("两次输入的新密码不一致");
      return;
    }
    if (currentAccount.isEmpty) {
      _showToast("账号信息缺失，请重新登录");
      return;
    }
    try {
      final data = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/user'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
        "action": "updatePassword",
        "account": currentAccount,
        "oldPassword": old,
        "newPassword": new1,
      }),
      )).body);
      if (mounted) {
        if (data["success"] == true) {
          oldPwd.clear();
          newPwd.clear();
          confirmPwd.clear();
          closeAll();
          _showToast("密码修改成功，请重新登录");
          await logout();
        } else {
          _showToast(data["msg"] ?? "修改失败");
        }
      }
    } catch (_) {
      if (mounted) _showToast("网络异常，请重试");
    }
  }

  Future<void> _refreshEmailBind() async {
    if (currentAccount.isEmpty) return;
    setState(() {
      emailLoaded = false;
    });

    try {
      final data = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/user'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
        "action": "checkEmailBind",
        "account": currentAccount,
      }),
      )).body);
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
      final data = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/user'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
        "action": "unbindEmail",
        "account": currentAccount,
      }),
      )).body);
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

  void _showToast(String msg) {
    ToastUtil.show(context, msg);
  }

  Future<void> logout() async {
    // 🔥 精确清理用户会话 key（userInfo 等），保留声明一次性标记 agreement_ever_shown
    await UserAgreementWidget.removeUserKeys();
    if (mounted) {
      Navigator.pushReplacementNamed(context, "/login");
    }
  }

  // 扫码签到
  void startScan() {
    _isScanning = false;
    setState(() {
      showSign = false;
      showScanner = true;
    });
  }

  // 处理扫码结果 ——?已修复：——?UniApp 完全一——?
  Future<void> handleScanResult(String code) async {
    setState(() => showScanner = false);

    if (code.isEmpty) return;
    if (currentAccount.isEmpty) {
      ToastUtil.show(context, "请先登录");
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final data = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/sign'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
        "action": "scan",
        "account": currentAccount,
        "qrcode": code,
      }),
      )).body);

      if (mounted) {
        Navigator.pop(context);
        ToastUtil.show(context, data["message"] ?? "签到失败");
        if (data["success"] == true) {
          Future.delayed(const Duration(milliseconds: 1500), () {
            closeAll();
          });
        } else {
          // 签到失败，允许重新扫码
          _isScanning = false;
          setState(() => showScanner = true);
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ToastUtil.showError(context, "网络异常，请重试");
        _isScanning = false;
        setState(() => showScanner = true);
      }
    }
  }

  // ======================= 新增：考试登录扫码 =======================
  void startExamLoginScan() {
    if (currentAccount.isEmpty) {
      ToastUtil.show(context, "请先登录");
      return;
    }
    setState(() {
      showExamLoginScanner = true;
    });
  }

  // 处理考试登录扫码结果
  void handleExamLoginScanResult(String code) {
    setState(() {
      showExamLoginScanner = false;
      scannedQrkey = code;
      showExamConfirm = true;
    });
  }

  // 确认绑定考试登录
  Future<void> confirmExamLogin() async {
    if (scannedQrkey.isEmpty || currentAccount.isEmpty) {
      ToastUtil.showError(context, "参数错误");
      setState(() => showExamConfirm = false);
      return;
    }

    setState(() => showExamConfirm = false);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final data = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/user'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
        "action": "qrcodebind",
        "qrkey": scannedQrkey,
        "account": currentAccount,
      }),
      )).body);

      if (mounted) {
        Navigator.pop(context);
        ToastUtil.show(context, data["msg"] ?? "绑定失败");
        if (data["success"] == true) {
          Future.delayed(const Duration(milliseconds: 1500), () {
            closeAll();
          });
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ToastUtil.showError(context, "网络异常，请重试");
      }
    }
  }

  // ======================= 修复：口令签到（完全对接后端）=======================
  Future<void> doCodeSign() async {
    String code = codeCtrl.text.trim();
    if (code.isEmpty) {
      ToastUtil.show(context, "请输入口令");
      return;
    }
    if (currentAccount.isEmpty) {
      ToastUtil.show(context, "请先登录");
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final data = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/sign'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
        "action": "code", // 与UniApp一致
        "account": currentAccount,
        "code": code,
      }),
      )).body);

      if (mounted) {
        Navigator.pop(context);
        ToastUtil.show(context, data["message"] ?? "签到失败");
        if (data["success"] == true) {
          Future.delayed(const Duration(milliseconds: 1500), () {
            closeAll();
          });
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ToastUtil.showError(context, "网络异常，请重试");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final cardSize = (screenWidth - 80 - 24) / 3; // 左右各20padding + 2个间距12

    // 工具区功能
    final toolItems = [
      {'icon': Icons.edit_note_outlined, 'label': '签到', 'onTap': () => setState(() => showSign = true)},
      {'icon': Icons.phone_iphone_outlined, 'label': '考试登录', 'onTap': startExamLoginScan},
    ];

    // 常规区功能
    final normalItems = [
      {'icon': Icons.settings_outlined, 'label': '设置', 'onTap': () => setState(() => showSetting = true)},
      {'icon': Icons.update_outlined, 'label': '检查更新', 'onTap': () => Navigator.pushNamed(context, "/update")},
      {'icon': Icons.language_outlined, 'label': '官网', 'onTap': _openWebsite},
      {'icon': Icons.logout_outlined, 'label': '退出登录', 'onTap': logout},
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 50),
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 10),
                // 工具区域
                _buildSection(
                  label: "工具",
                  items: toolItems,
                  cardSize: cardSize,
                ),
                const SizedBox(height: 24),
                // 常规区域
                _buildSection(
                  label: "常规",
                  items: normalItems,
                  cardSize: cardSize,
                ),
              ],
            ),
          ),

          if (showAnyModal || showScanner || showExamLoginScanner || showExamConfirm)
            ModalBarrier(color: Colors.black54, dismissible: !showScanner && !showExamLoginScanner, onDismiss: closeAll),

          if (showSetting) _buildSettingModal(),
          if (showAccount) _buildAccountModal(),
          if (showPwd) _buildPwdModal(),
          if (showDeclare) _buildDeclareModal(),
          if (showSign) _buildSignModal(),
          if (showScanner) _buildScannerModal(),
          if (showExamLoginScanner) _buildExamLoginScannerModal(),
          if (showExamConfirm) _buildExamConfirmModal(),
        ],
      ),
    );
  }

  bool get showAnyModal => showSetting || showAccount || showPwd || showDeclare || showSign;

  void closeAll() {
    if (showScanner || showExamLoginScanner) {
      setState(() {
        showScanner = false;
        showExamLoginScanner = false;
      });
      return;
    }
    setState(() {
      showSetting = false;
      showAccount = false;
      showPwd = false;
      showDeclare = false;
      showSign = false;
      showCodePanel = false;
      showScanner = false;
      showExamLoginScanner = false;
      showExamConfirm = false;
      signTab = 0;
      scannedQrkey = "";
    });
  }

  // 🔥 新增：打开官网
  void _openWebsite() async {
    final url = Uri.parse('https://wsq537537.github.io/zd/index');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ToastUtil.show(context, "无法打开官网");
      }
    }
  }

  // 构建分区（透明边框 + 左上角浮标文字 + 卡片网格）
  Widget _buildSection({required String label, required List<Map<String, dynamic>> items, required double cardSize}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black.withValues(alpha: 0.25), width: 1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 浮标标签
          Positioned(
            top: -10,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              color: Colors.transparent,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.black.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          // 卡片网格
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.start,
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
        ],
      ),
    );
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

  Widget _buildSettingModal() {
    return _modal(
      title: "设置",
      children: [
        _item("账户信息", () {
          setState(() {
            showSetting = false;
            showAccount = true;
          });
          _refreshEmailBind();
        }),
        _item("修改密码", () {
          setState(() {
            showSetting = false;
            showPwd = true;
          });
        }),
        _item("用户声明", () {
          setState(() {
            showSetting = false;
            showDeclare = true;
          });
        }),
      ],
    );
  }

  Widget _buildAccountModal() {
    return _modal(
      title: "账户信息",
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("账号：$currentAccount", style: const TextStyle(fontSize: 16, color: Colors.black87)),
              const SizedBox(height: 6),
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
            ],
          ),
        ),
        const SizedBox(height: 12),
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
    );
  }

  Widget _buildPwdModal() {
    return _modal(
      title: "修改密码",
      children: [
        _pwdInput("原密码", oldPwd),
        _pwdInput("新密码", newPwd),
        _pwdInput("确认密码", confirmPwd),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _btn("取消", closeAll)),
            const SizedBox(width: 10),
            Expanded(child: _btn("提交", () => _changePassword())),
          ],
        ),
      ],
    );
  }

  Widget _buildDeclareModal() {
    return Center(
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
    );
  }

  /// 加载签到记录 —— 显示所有任务，按科目分组，标注本人出勤/缺勤状态
  Future<void> loadSignHistory() async {
    setState(() => signHistoryLoading = true);
    try {
      final data = await jsonDecode((await http.post(
        Uri.parse('$baseUrl/api/sign'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"action": "history"}),
      )).body);
      if (data["success"] == true) {
        final allItems = data["data"] as List;
        final subjectOrder = ['语文', '数学', '英语', '其他'];
        final grouped = <String, List<dynamic>>{};
        for (final item in allItems) {
          final subject = (item["subject"] as String?)?.trim() ?? "其他";
          final signedAccounts = List<String>.from(item["signedAccounts"] ?? []);
          final isSigned = signedAccounts.contains(currentAccount);
          grouped.putIfAbsent(subject, () => []).add({...item, "_signed": isSigned});
        }
        // 按预定顺序重建 Map，确保语文始终在首位
        final orderedGrouped = <String, List<dynamic>>{};
        for (final s in subjectOrder) {
          if (grouped.containsKey(s)) orderedGrouped[s] = grouped[s]!;
        }
        for (final entry in grouped.entries) {
          if (!subjectOrder.contains(entry.key)) orderedGrouped[entry.key] = entry.value;
        }
        // 预计算每个科目的统计数据
        final totalBySubj = <String, int>{};
        final presentBySubj = <String, int>{};
        final absentBySubj = <String, int>{};
        for (final subject in orderedGrouped.keys) {
          final items = orderedGrouped[subject]!;
          totalBySubj[subject] = items.length;
          presentBySubj[subject] = items.where((it) => it["_signed"] == true).length;
          absentBySubj[subject] = items.where((it) => it["_signed"] != true).length;
        }
        setState(() {
          signHistory = allItems;
          signBySubject = orderedGrouped;
          signTotalBySubject = totalBySubj;
          signPresentBySubject = presentBySubj;
          signAbsentBySubject = absentBySubj;
          selectedSubject = orderedGrouped.containsKey('语文') ? '语文' : orderedGrouped.keys.first;
        });
      }
    } catch (e) {
      debugPrint("Load sign history error: $e");
    } finally {
      setState(() => signHistoryLoading = false);
    }
  }

  Widget _buildSignModal() {
    return Center(
      child: Container(
        width: 320,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("签到", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                GestureDetector(
                  onTap: closeAll,
                  child: const Icon(Icons.close, size: 20, color: Colors.grey),
                ),
              ],
            ),
            const Divider(height: 16),
            // 二级Tab
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => signTab = 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: signTab == 0 ? const Color(0xff1890ff) : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Text(
                        "现场签到",
                        style: TextStyle(
                          color: signTab == 0 ? const Color(0xff1890ff) : Colors.black54,
                          fontWeight: signTab == 0 ? FontWeight.bold : FontWeight.normal,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() => signTab = 1);
                      loadSignHistory();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: signTab == 1 ? const Color(0xff1890ff) : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Text(
                        "记录查询",
                        style: TextStyle(
                          color: signTab == 1 ? const Color(0xff1890ff) : Colors.black54,
                          fontWeight: signTab == 1 ? FontWeight.bold : FontWeight.normal,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 现场签到内容
            if (signTab == 0)
              Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: _btn("扫码签到", startScan)),
                      const SizedBox(width: 10),
                      Expanded(child: _btn("口令签到", () {
                        setState(() => showCodePanel = true);
                      })),
                    ],
                  ),
                  if (showCodePanel)
                    Column(
                      children: [
                        const SizedBox(height: 10),
                        _input("输入4位口令", codeCtrl),
                        const SizedBox(height: 10),
                        _btn("确认签到", () => doCodeSign()),
                      ],
                    ),
                  const SizedBox(height: 10),
                  _btn("关闭", closeAll),
                ],
              ),
            // 记录查询内容
            if (signTab == 1)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.55,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 固定科目标签（语文/数学/英语/其他）
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      height: 32,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        shrinkWrap: true,
                        itemCount: _subjectTabs.length,
                        itemBuilder: (_, i) {
                          final subject = _subjectTabs[i];
                          final isSelected = selectedSubject == subject;
                          return GestureDetector(
                            onTap: () => setState(() => selectedSubject = subject),
                            child: Container(
                              margin: EdgeInsets.symmetric(horizontal: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xff1890ff) : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                subject,
                                style: TextStyle(
                                  color: isSelected ? Colors.white : Colors.grey.shade700,
                                  fontSize: 12,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    // 统计栏（按选中科目显示）
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _statItem("总次数", "${signTotalBySubject[selectedSubject] ?? 0}", Colors.blue),
                          _statItem("出勤", "${signPresentBySubject[selectedSubject] ?? 0}", Colors.green),
                          _statItem("缺勤", "${signAbsentBySubject[selectedSubject] ?? 0}", Colors.orange),
                        ],
                      ),
                    ),
                    Expanded(
                      child: signHistoryLoading
                          ? const Center(child: CircularProgressIndicator())
                          : signBySubject.isEmpty
                              ? const Center(child: Text("暂无签到任务", style: TextStyle(color: Colors.grey)))
                              : ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: signBySubject[selectedSubject]?.length ?? 0,
                                  itemBuilder: (_, index) {
                                    final item = signBySubject[selectedSubject]![index];
                                    final isSigned = item["_signed"] == true;
                                    final fmtTime = item["formatTime"] ?? "未知";
                                    final title = item["title"]?.toString().isNotEmpty == true ? item["title"] : "";
                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE)))),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 20, height: 20,
                                            decoration: BoxDecoration(
                                              color: isSigned ? Colors.green : Colors.grey.shade300,
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(color: isSigned ? Colors.green : Colors.grey.shade400),
                                            ),
                                            child: isSigned ? const Icon(Icons.check, size: 12, color: Colors.white) : null,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(title.isNotEmpty ? title : "课堂签到", style: const TextStyle(fontSize: 13, color: Colors.black87)),
                                                Text(fmtTime, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                              ],
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: isSigned ? Colors.green.shade100 : Colors.orange.shade100,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              isSigned ? "已签到" : "缺勤",
                                              style: TextStyle(fontSize: 11, color: isSigned ? Colors.green.shade800 : Colors.orange.shade800, fontWeight: FontWeight.w600),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                    ),
                    const SizedBox(height: 10),
                    _btn("关闭", closeAll),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _statItem(String label, String value, Color color) {
    return Column(children: [
      Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
      Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
    ]);
  }

  Widget _modal({required String title, required List<Widget> children}) {
    return Center(
      child: Container(
        width: 320,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Divider(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _item(String text, VoidCallback onTap) {
    return ListTile(title: Text(text), onTap: onTap);
  }

  Widget _input(String hint, TextEditingController ctrl) {
    return TextField(
      controller: ctrl,
      decoration: InputDecoration(hintText: hint),
    );
  }

  Widget _pwdInput(String hint, TextEditingController ctrl) {
    return TextField(
      controller: ctrl,
      obscureText: !showPassword,
      decoration: InputDecoration(
        hintText: hint,
        suffixIcon: IconButton(
          icon: Icon(showPassword ? Icons.visibility_off : Icons.visibility, size: 20),
          onPressed: () => setState(() => showPassword = !showPassword),
        ),
      ),
    );
  }

  Widget _btn(String text, VoidCallback onTap) {
    return ElevatedButton(onPressed: onTap, child: Text(text));
  }

  Widget _buildScannerModal() {
    return Center(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "扫码签到",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => setState(() => showScanner = false),
                  ),
                ],
              ),
            ),
            Expanded(
              child: MobileScanner(
                onDetect: (BarcodeCapture capture) {
                  if (_isScanning) return;
                  final List<Barcode> barcodes = capture.barcodes;
                  if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
                    _isScanning = true;
                    final String code = barcodes.first.rawValue!;
                    handleScanResult(code);
                  }
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              child: const Text(
                "将二维码放入框内，即可自动扫描",
                style: TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 新增：考试登录扫码弹窗
  Widget _buildExamLoginScannerModal() {
    return Center(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "考试登录",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => setState(() => showExamLoginScanner = false),
                  ),
                ],
              ),
            ),
            Expanded(
              child: MobileScanner(
                onDetect: (BarcodeCapture capture) {
                  final List<Barcode> barcodes = capture.barcodes;
                  if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
                    final String code = barcodes.first.rawValue!;
                    handleExamLoginScanResult(code);
                  }
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              child: const Text(
                "扫描平板考试系统二维码进行登录授权",
                style: TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 新增：考试登录确认弹窗
  Widget _buildExamConfirmModal() {
    return Center(
      child: Container(
        width: 320,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "考试登录确认",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Divider(height: 20),
            const Text(
              "确定登录平板考试系统？",
              style: TextStyle(fontSize: 14, color: Colors.black87),
            ),
            const SizedBox(height: 10),
            Text(
              "当前账号：$currentAccount",
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => setState(() {
                      showExamConfirm = false;
                      scannedQrkey = "";
                    }),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text("取消"),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: confirmExamLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xff1890ff),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text("确认"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
