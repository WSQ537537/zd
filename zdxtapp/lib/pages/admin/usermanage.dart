import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:zdxtapp/config.dart';

import 'package:zdxtapp/utils/toast.dart';
import 'package:zdxtapp/utils/ui_helpers.dart'; // 🔥 全局UI辅助工具

class UserManagePage extends StatefulWidget {
  const UserManagePage({super.key});

  @override
  State<UserManagePage> createState() => _UserManagePageState();
}

class _UserManagePageState extends State<UserManagePage> {
  final String baseUrl = "${Config.baseUrl}/api/user";

  // 标签页
  String activeTab = "create";

  // 创建用户表单
  final TextEditingController _accountCtrl = TextEditingController();
  final TextEditingController _pwdCtrl = TextEditingController();
  final TextEditingController _remarkCtrl = TextEditingController();
  final TextEditingController _bindStuCtrl = TextEditingController();

  // 角色
  List roleList = [
    {"id": 1, "name": "管理员"},
    {"id": 2, "name": "学生"},
    {"id": 3, "name": "家长"},
  ];
  int roleIndex = 1;

  bool loading = false;
  List userList = [];
  bool isFromReset = false;

  // 编辑用户
  bool showEdit = false;
  final TextEditingController _editNewAccountCtrl = TextEditingController();
  final TextEditingController _editRemarkCtrl = TextEditingController();
  final TextEditingController _editPwdCtrl = TextEditingController();
  bool editShowPwd = false;
  late Map editForm;
  List boundStudents = [];
  final TextEditingController _addStuCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    getUserList();
  }

  // 获取用户列表
  Future<void> getUserList() async {
    setState(() => loading = true);
    try {
      final Map<String, dynamic> data = await jsonDecode((await http.post(
        Uri.parse(baseUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"action": "getUserList"}),
      )).body);
      if (data["success"] == true) {
        final List list = List.from(data["data"] ?? []);
        list.sort((a, b) {
          bool aPending = a["appealStatus"] == "pending";
          bool bPending = b["appealStatus"] == "pending";
          if (aPending == bPending) return 0;
          return aPending ? -1 : 1;
        });
        setState(() {
          userList = list;
        });
      }
    } catch (e) {
      //
    } finally {
      setState(() => loading = false);
    }
  }

  // 创建用户
  Future<void> createUser() async {
    String account = _accountCtrl.text.trim();
    String pwd = _pwdCtrl.text.trim();
    if (account.isEmpty || pwd.isEmpty) {
      ToastUtil.show(context, "账号/密码不能为空");
      return;
    }

    List bound = [];
    if (roleList[roleIndex]["id"] == 3 && _bindStuCtrl.text.isNotEmpty) {
      bound = _bindStuCtrl.text.split(",").map((e) => e.trim()).toList();
    }

    setState(() => loading = true);
    try {
      final Map<String, dynamic> data = await jsonDecode((await http.post(
        Uri.parse(baseUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "action": "createUser",
          "account": account,
          "password": pwd,
          "type": roleList[roleIndex]["id"],
          "remark": _remarkCtrl.text.trim(),
          "boundStudents": bound,
        }),
      )).body);
      if (data["success"] == true) {
        if (mounted) {
          ToastUtil.show(context, "创建成功");
        }
        _accountCtrl.clear();
        _pwdCtrl.clear();
        _remarkCtrl.clear();
        _bindStuCtrl.clear();
        setState(() => roleIndex = 1);
        getUserList();
      } else {
        if (mounted) {
          ToastUtil.show(context, data["msg"] ?? "创建失败");
        }
      }
    } catch (e) {
      //
    } finally {
      setState(() => loading = false);
    }
  }

  // 删除用户（前端防御：默认 admin 账号不可删除）
  Future<void> deleteUser(String account, int index) async {
    if (account.trim() == "admin") {
      if (mounted) ToastUtil.show(context, "默认 admin 账号不可删除");
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("确认删除 $account"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final res = jsonDecode((await http.post(
        Uri.parse(baseUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"action": "deleteUser", "account": account}),
      )).body);
                if (res["success"] != true) {
                  if (mounted) {
                    ToastUtil.show(
                        context, res["msg"] ?? res["message"] ?? "删除失败");
                  }
                  return;
                }
                setState(() => userList.removeAt(index));
                if (mounted) {
                  ToastUtil.show(context, "删除成功");
                }
              } catch (e) {
                if (mounted) ToastUtil.show(context, "删除失败，请重试");
              }
            },
            child: const Text("确认", style: TextStyle(color: UIHelpers.errorColor)),
          ),
        ],
      ),
    );
  }

  // 打开编辑
  void openEdit(Map user, {bool fromReset = false}) {
    setState(() {
      editForm = Map.from(user);
      _editNewAccountCtrl.clear();
      _editRemarkCtrl.clear();
      _editPwdCtrl.clear();
      editShowPwd = false;
      boundStudents = List.from(user["boundStudents"] ?? []);
      isFromReset = fromReset;
      showEdit = true;
    });
  }

  // 提交编辑
  Future<void> submitEdit() async {
    if (isFromReset && _editPwdCtrl.text.trim().isEmpty) {
      ToastUtil.show(context, "密码不能为空");
      return;
    }

    setState(() => loading = true);
    try {
      if (isFromReset) {
        await jsonDecode((await http.post(
        Uri.parse(baseUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
            "action": "adminResetPassword",
            "account": editForm["account"],
            "newPassword": _editPwdCtrl.text.trim(),
          }),
      )).body);
      } else {
        await jsonDecode((await http.post(
        Uri.parse(baseUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
            "action": "updateUser",
            "account": editForm["account"],
            "newAccount": _editNewAccountCtrl.text.trim().isEmpty ? editForm["account"] : _editNewAccountCtrl.text.trim(),
            "remark": _editRemarkCtrl.text.trim(),
            "newPassword": _editPwdCtrl.text.trim(),
            "boundStudents": boundStudents,
          }),
      )).body);
      }
      setState(() => showEdit = false);
      getUserList();
      if (mounted) {
        ToastUtil.show(context, "保存成功");
      }
    } catch (e) {
      // 忽略错误
    } finally {
      setState(() => loading = false);
    }
  }

  // 生成随机密码
  void randomPwd() {
    String pwd = DateTime.now().millisecondsSinceEpoch.toRadixString(36).substring(2, 8);
    setState(() => _editPwdCtrl.text = pwd);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UIHelpers.bgColorLight,
      body: Stack(
        children: [
          // 🔥 渐变背景
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xff667eea), Color(0xff764ba2)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Column(
            children: [
              // 🔥 顶部栏
              Container(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 12,
                  left: 16,
                  right: 16,
                  bottom: 12,
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.arrow_back_ios, size: 14, color: Colors.white),
                            SizedBox(width: 4),
                            Text('返回', style: TextStyle(color: Colors.white, fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                    const Expanded(
                      child: Center(
                        child: Text('用户管理', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 60),
                  ],
                ),
              ),

              // 🔥 左右分栏模式卡片
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildModeCard(
                        title: '创建用户',
                        subtitle: '新增账号',
                        icon: Icons.person_add,
                        isActive: activeTab == "create",
                        onTap: () => setState(() => activeTab = "create"),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildModeCard(
                        title: '用户列表',
                        subtitle: '管理查看',
                        icon: Icons.people,
                        isActive: activeTab == "list",
                        onTap: () => setState(() => activeTab = "list"),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 内容区域
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(UIHelpers.radiusXLarge),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(UIHelpers.radiusXLarge),
                    child: activeTab == "create" ? buildCreate() : buildList(),
                  ),
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),

          if (showEdit) buildEditModal(),
        ],
      ),
    );
  }

  // 🔥 左右分栏模式卡片
  Widget _buildModeCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isActive
                ? [
                    Colors.white.withValues(alpha: 0.95),
                    Colors.white.withValues(alpha: 0.85),
                  ]
                : [
                    Colors.white.withValues(alpha: 0.2),
                    Colors.white.withValues(alpha: 0.1),
                  ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(UIHelpers.radiusXLarge),
          border: Border.all(
            color: isActive ? Colors.transparent : Colors.white.withValues(alpha: 0.3),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: isActive
                  ? Colors.black.withValues(alpha: 0.15)
                  : Colors.black.withValues(alpha: 0.05),
              blurRadius: isActive ? 15 : 8,
              offset: Offset(0, isActive ? 6 : 3),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 32,
              color: isActive ? UIHelpers.primaryColor : Colors.white.withValues(alpha: 0.9),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                color: isActive ? UIHelpers.primaryColor : Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                color: isActive ? Colors.grey.shade600 : Colors.white.withValues(alpha: 0.8),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 创建用户界面
  Widget buildCreate() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 🔥 标题
          Row(
            children: [
              Icon(Icons.person_add, color: UIHelpers.primaryColor, size: 28),
              const SizedBox(width: 10),
              const Text(
                "创建新用户",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xff333333)),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 🔥 账号
          _buildInputField(
            label: '账号',
            hint: '请输入账号',
            controller: _accountCtrl,
            icon: Icons.account_circle,
          ),
          const SizedBox(height: 16),

          // 🔥 密码
          _buildInputField(
            label: '密码',
            hint: '请输入密码',
            controller: _pwdCtrl,
            icon: Icons.lock,
            obscureText: true,
          ),
          const SizedBox(height: 20),

          // 🔥 角色选择
          const Text(
            "角色类型",
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xff666666)),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: List.generate(roleList.length, (index) {
              bool isSelected = roleIndex == index;
              return GestureDetector(
                onTap: () => setState(() => roleIndex = index),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: isSelected
                        ? LinearGradient(
                            colors: [UIHelpers.primaryColor, UIHelpers.primaryColor.withValues(alpha: 0.8)],
                          )
                        : null,
                    color: isSelected ? null : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(UIHelpers.radiusMedium),
                    border: Border.all(
                      color: isSelected ? Colors.transparent : Colors.grey.shade300,
                      width: 1.5,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: UIHelpers.primaryColor.withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    roleList[index]["name"],
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.black87,
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }),
          ),

          // 🔥 绑定学生（仅家长）
          if (roleList[roleIndex]["id"] == 3) ...[
            const SizedBox(height: 20),
            _buildInputField(
              label: '绑定学生',
              hint: '多个学生用逗号分隔',
              controller: _bindStuCtrl,
              icon: Icons.school,
            ),
          ],

          const SizedBox(height: 16),

          // 🔥 备注
          _buildInputField(
            label: '备注',
            hint: '选填',
            controller: _remarkCtrl,
            icon: Icons.note,
          ),

          const SizedBox(height: 28),

          // 🔥 提交按钮
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: UIHelpers.primaryColor,
                foregroundColor: Colors.white,
                elevation: 4,
                shadowColor: UIHelpers.primaryColor.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(UIHelpers.radiusMedium),
                ),
              ),
              onPressed: loading ? null : createUser,
              child: loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle, size: 20),
                        SizedBox(width: 8),
                        Text("创建用户", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // 🔥 通用输入框组件
  Widget _buildInputField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required IconData icon,
    bool obscureText = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xff666666)),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscureText,
          style: const TextStyle(color: Color(0xff333333)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400),
            prefixIcon: Icon(icon, color: UIHelpers.primaryColor, size: 20),
            filled: true,
            fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(UIHelpers.radiusMedium),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(UIHelpers.radiusMedium),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(UIHelpers.radiusMedium),
              borderSide: const BorderSide(color: UIHelpers.primaryColor, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ],
    );
  }

  // 用户列表
  Widget buildList() {
    if (loading && userList.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text("加载中...", style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }
    if (userList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text("暂无用户", style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: userList.length,
      itemBuilder: (context, index) {
        var u = userList[index];
        String roleName = roleList.firstWhere((r) => r["id"] == u["type"], orElse: () => {"name": "未知"})["name"];
        bool isAppealPending = u["appealStatus"] == "pending";

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: isAppealPending ? const Color(0xFFFFF1F2) : Colors.white,
            borderRadius: BorderRadius.circular(UIHelpers.radiusMedium),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 🔥 头部：账号 + 角色标签
                Row(
                  children: [
                    Icon(
                      _getRoleIcon(u["type"]),
                      size: 24,
                      color: UIHelpers.primaryColor,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        u["account"] ?? "",
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xff333333),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getRoleColor(u["type"]).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        roleName,
                        style: TextStyle(
                          color: _getRoleColor(u["type"]),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 🔥 信息行
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoItem(
                        icon: Icons.info_outline,
                        label: '申诉状态',
                        value: isAppealPending ? '待处理' : '正常',
                        valueColor: isAppealPending ? UIHelpers.errorColor : UIHelpers.successColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildInfoItem(
                        icon: Icons.note_outlined,
                        label: '备注',
                        value: u["remark"] ?? '-',
                        valueColor: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 🔥 操作按钮
                Row(
                  children: [
                    Expanded(
                      child: _buildActionButton(
                        text: isAppealPending ? '重置' : '编辑',
                        icon: isAppealPending ? Icons.lock_reset : Icons.edit,
                        color: isAppealPending ? UIHelpers.warningColor : UIHelpers.primaryColor,
                        onTap: () => openEdit(u, fromReset: isAppealPending),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: u["account"]?.toString().trim() == "admin"
                          ? _buildActionButton(
                              text: '删除',
                              icon: Icons.lock,
                              color: Colors.grey.shade400,
                              onTap: () => ToastUtil.show(context, "默认 admin 账号不可删除"),
                            )
                          : _buildActionButton(
                              text: '删除',
                              icon: Icons.delete,
                              color: UIHelpers.errorColor,
                              onTap: () => deleteUser(u["account"], index),
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // 🔥 信息项组件
  Widget _buildInfoItem({
    required IconData icon,
    required String label,
    required String value,
    required Color valueColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade500),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: valueColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // 🔥 操作按钮组件
  Widget _buildActionButton({
    required String text,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(UIHelpers.radiusSmall),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🔥 获取角色图标
  IconData _getRoleIcon(int type) {
    switch (type) {
      case 1:
        return Icons.admin_panel_settings;
      case 2:
        return Icons.school;
      case 3:
        return Icons.family_restroom;
      default:
        return Icons.person;
    }
  }

  // 🔥 获取角色颜色
  Color _getRoleColor(int type) {
    switch (type) {
      case 1:
        return const Color(0xffff7a2f);
      case 2:
        return const Color(0xff1890ff);
      case 3:
        return const Color(0xff52c41a);
      default:
        return Colors.grey;
    }
  }

  // 编辑弹窗
  Widget buildEditModal() {
    return Stack(
      children: [
        ModalBarrier(color: Colors.black54, dismissible: true, onDismiss: () => setState(() => showEdit = false)),
        Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(UIHelpers.radiusXLarge),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 🔥 标题
                  Row(
                    children: [
                      Icon(Icons.edit, color: UIHelpers.primaryColor, size: 28),
                      const SizedBox(width: 10),
                      const Text(
                        "编辑用户",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // 🔥 原账号
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(UIHelpers.radiusSmall),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.account_circle, size: 18, color: Colors.grey),
                        const SizedBox(width: 8),
                        Text(
                          "原账号：${editForm["account"]}",
                          style: const TextStyle(fontSize: 14, color: Color(0xff666666)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 🔥 新账号
                  _buildInputField(
                    label: '新账号',
                    hint: '不修改留空',
                    controller: _editNewAccountCtrl,
                    icon: Icons.person_outline,
                  ),
                  const SizedBox(height: 16),

                  // 🔥 备注
                  _buildInputField(
                    label: '备注',
                    hint: '选填',
                    controller: _editRemarkCtrl,
                    icon: Icons.note_outlined,
                  ),
                  const SizedBox(height: 16),

                  // 🔥 新密码
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '新密码',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xff666666)),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _editPwdCtrl,
                        obscureText: !editShowPwd,
                        style: const TextStyle(color: Color(0xff333333)),
                        decoration: InputDecoration(
                          hintText: '不修改留空',
                          hintStyle: TextStyle(color: Colors.grey.shade400),
                          prefixIcon: Icon(Icons.lock_outline, color: UIHelpers.primaryColor),
                          suffixIcon: IconButton(
                            onPressed: () => setState(() => editShowPwd = !editShowPwd),
                            icon: Icon(editShowPwd ? Icons.visibility : Icons.visibility_off, color: Colors.grey),
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(UIHelpers.radiusMedium),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(UIHelpers.radiusMedium),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(UIHelpers.radiusMedium),
                            borderSide: const BorderSide(color: UIHelpers.primaryColor, width: 2),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: randomPwd,
                    child: Row(
                      children: [
                        Icon(Icons.casino, size: 16, color: UIHelpers.primaryColor),
                        const SizedBox(width: 4),
                        Text(
                          '生成随机密码',
                          style: TextStyle(color: UIHelpers.primaryColor, fontSize: 13),
                        ),
                      ],
                    ),
                  ),

                  // 🔥 绑定学生（仅家长）
                  if (editForm["type"] == 3) ...[
                    const SizedBox(height: 20),
                    const Text(
                      '绑定学生',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xff666666)),
                    ),
                    const SizedBox(height: 12),
                    ...List.generate(boundStudents.length, (i) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(UIHelpers.radiusSmall),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.school, size: 16, color: UIHelpers.primaryColor),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                boundStudents[i],
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                            GestureDetector(
                              onTap: () => setState(() => boundStudents.removeAt(i)),
                              child: Icon(Icons.close, size: 18, color: UIHelpers.errorColor),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _addStuCtrl,
                            style: const TextStyle(color: Color(0xff333333)),
                            decoration: InputDecoration(
                              hintText: '添加学生',
                              hintStyle: TextStyle(color: Colors.grey.shade400),
                              prefixIcon: Icon(Icons.add, color: UIHelpers.primaryColor, size: 20),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(UIHelpers.radiusMedium),
                                borderSide: BorderSide(color: Colors.grey.shade300),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(UIHelpers.radiusMedium),
                                borderSide: BorderSide(color: Colors.grey.shade300),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(UIHelpers.radiusMedium),
                                borderSide: const BorderSide(color: UIHelpers.primaryColor, width: 2),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            if (_addStuCtrl.text.isNotEmpty) {
                              setState(() {
                                boundStudents.add(_addStuCtrl.text.trim());
                                _addStuCtrl.clear();
                              });
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: UIHelpers.primaryColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(UIHelpers.radiusMedium),
                            ),
                            child: Icon(Icons.add, color: UIHelpers.primaryColor),
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 24),

                  // 🔥 按钮
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => showEdit = false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(UIHelpers.radiusMedium),
                            ),
                            child: const Center(
                              child: Text(
                                "取消",
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: submitEdit,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [UIHelpers.primaryColor, UIHelpers.primaryColor.withValues(alpha: 0.8)],
                              ),
                              borderRadius: BorderRadius.circular(UIHelpers.radiusMedium),
                              boxShadow: [
                                BoxShadow(
                                  color: UIHelpers.primaryColor.withValues(alpha: 0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Text(
                                "保存",
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
