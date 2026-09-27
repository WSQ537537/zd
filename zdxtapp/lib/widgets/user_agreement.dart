import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

/// 用户声明组件
/// 功能：必须计时满10秒 + 滑动到底部，「我知道了」按钮方可点击
/// 通过 SharedPreferences 记录是否已完成，实现首次只显示一次
class UserAgreementWidget extends StatefulWidget {
  /// 确认后的回调（跳转到登录页或主页）
  final VoidCallback? onConfirmed;

  /// 是否强制重新显示（用于「我的-设置」中再次查看）
  final bool forceShow;

  /// 🔥 App 版本号（用于版本感知，版本变化后重新显示声明）
  final String appVersion;

  const UserAgreementWidget({
    super.key,
    this.onConfirmed,
    this.forceShow = false,
    this.appVersion = 'unknown',
  });

  // 🔥 静态常量前缀，版本号作为 key 后缀
  static const String _baseKeyPrefix = 'agreement_done_';

  /// 一次性展示标记：只要写入过该 key 为 true，无论 App 如何升级/重装都不再弹声明
  /// （只在第一次安装时弹一次；后续更新不再重弹）
  static const String _everShownKey = 'agreement_ever_shown';

  /// 🔥 一次性展示标记 key（供 hasAgreed / removeUserKeys 使用）
  static String get everShownKey => _everShownKey;

  /// 用户会话相关 key 清单：退出登录/清理缓存时逐个 remove，
  /// 绝不清理应用级标记 agreement_ever_shown（业界最佳实践：selective remove，never clear）
  static const List<String> _userSessionKeys = [
    'userInfo',
    'paperListCache',
    'paperListCacheTime',
    'ai_chat_list',
    'download_history',
  ];

  /// 🔥 精确清理用户会话 key（退出登录/清理缓存时调用）。
  /// 保留 agreement_ever_shown 与 nav_background 等应用级标记，避免误删导致"声明乱弹"。
  static Future<void> removeUserKeys() async {
    final prefs = await SharedPreferences.getInstance();
    // 1. 固定的用户会话 key
    for (final key in _userSessionKeys) {
      await prefs.remove(key);
    }
    // 2. 动态 version key：agreement_done_{ver}（旧数据兜底键），逐一 remove
    final allKeys = prefs.getKeys();
    for (final key in allKeys) {
      if (key.startsWith(_baseKeyPrefix)) {
        await prefs.remove(key);
      }
    }
    // 3. 防御性兜底：无论上述清理如何，强制确保 ever_shown 标记为 true，
    //    保证"声明已弹过"状态永不被任何清理路径重置
    await prefs.setBool(_everShownKey, true);
  }

  /// 静态方法：判断是否已读过声明（非首次启动时调用）
  /// 逻辑：
  /// - 一次性安装：读取 agreement_ever_shown，若为 true 即视为"已弹过"，不再弹（即使版本升级）
  /// - 旧数据兜底：任意 agreement_done_* 键为 true 也视为"已弹过"，避免老用户升级后重复弹窗
  static Future<bool> hasAgreed({String appVersion = 'unknown'}) async {
    final prefs = await SharedPreferences.getInstance();
    // 一次性展示标记：true 即不再弹（版本升级也跳过）
    if (prefs.getBool(_everShownKey) == true) return true;
    // 旧数据兜底：老版本只写过 agreement_done_{ver} 的 bool 键
    final allKeys = prefs.getKeys();
    for (final k in allKeys) {
      if (k.startsWith(_baseKeyPrefix) && prefs.getBool(k) == true) {
        // 自愈：发现旧兜底键为已读 → 立即把一次性标记持久化，
        // 防止弱网/并发导致 ever_shown 漏写后下次重启又弹
        try {
          await prefs.setBool(_everShownKey, true);
        } catch (_) {}
        return true;
      }
    }
    // 从未显示过声明（真正首次安装）
    return false;
  }

  /// 静态方法：标记当前版本已读过声明
  static Future<void> markAgreed({String appVersion = 'unknown'}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_everShownKey, true);
    await prefs.setBool('$_baseKeyPrefix$appVersion', true);
  }

  /// 静态方法：强制重置指定版本的声明状态
  static Future<void> reset({String appVersion = 'unknown'}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_baseKeyPrefix$appVersion', false);
  }

  @override
  State<UserAgreementWidget> createState() => _UserAgreementWidgetState();
}

class _UserAgreementWidgetState extends State<UserAgreementWidget> {
  final ScrollController _scrollController = ScrollController();
  int _elapsedSeconds = 0;
  bool _isAtBottom = false;
  bool _canConfirm = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _startTimer();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_elapsedSeconds < 10) {
          _elapsedSeconds++;
          if (_elapsedSeconds >= 10 && _isAtBottom) {
            _canConfirm = true;
          }
        }
      });
    });
  }

  void _onScroll() {
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    final atBottom = currentScroll >= (maxScroll - 10); // 10px 容差

    if (atBottom != _isAtBottom) {
      setState(() {
        _isAtBottom = atBottom;
        if (_isAtBottom && _elapsedSeconds >= 10) {
          _canConfirm = true;
        }
      });
    }
  }

  Future<void> _onConfirm() async {
    // 同时写入 version key 和 stored_version（供 hasAgreed 比较）
    await UserAgreementWidget.markAgreed(appVersion: widget.appVersion);
    widget.onConfirmed?.call();
  }

  Widget _buildContent() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            "用户声明",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Divider(height: 20),

          // 滚动内容区
          Container(
            height: 260,
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              child: Text(
                """为规范智答星途平台（以下简称"本平台"）使用秩序，保障管理员、学生、家长全体用户的合法权益，明确平台与用户双方的权利及义务，所有用户在登录、使用平台服务前，需认真阅读并自愿遵守本声明。用户登录、操作及使用本平台服务，即视为已完整知晓、认可并自愿遵守本声明全部条款。

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
                                                                        ---智答星途官方""",
                style: const TextStyle(fontSize: 12, height: 1.7, color: Colors.black87),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 进度提示
          Row(
            children: [
              Icon(
                _isAtBottom ? Icons.check_circle : Icons.arrow_downward,
                size: 16,
                color: _isAtBottom ? Colors.green : Colors.grey,
              ),
              const SizedBox(width: 6),
              Text(
                _isAtBottom ? '已滑动到底部 ✓' : '请滑动到最底部',
                style: TextStyle(
                  fontSize: 12,
                  color: _isAtBottom ? Colors.green : Colors.grey,
                ),
              ),
              const SizedBox(width: 16),
              Icon(
                _elapsedSeconds >= 10 ? Icons.check_circle : Icons.timer,
                size: 16,
                color: _elapsedSeconds >= 10 ? Colors.green : Colors.grey,
              ),
              const SizedBox(width: 6),
              Text(
                _elapsedSeconds >= 10 ? '计时完成 ✓' : '等待中 ${10 - _elapsedSeconds}秒',
                style: TextStyle(
                  fontSize: 12,
                  color: _elapsedSeconds >= 10 ? Colors.green : Colors.grey,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 确认按钮
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _canConfirm ? _onConfirm : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _canConfirm ? const Color(0xff1890ff) : Colors.grey.shade400,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                "我知道了",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Stack(
        children: [
          // 背景装饰
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0F172A), Color(0xFF1E293B), Color(0xFF2D3A4E)],
              ),
            ),
          ),
          Center(
            child: Container(
              width: 340,
              constraints: const BoxConstraints(maxHeight: 600),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: _buildContent(),
            ),
          ),
        ],
      ),
    );
  }
}
