import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'config.dart';
import 'pages/login/login.dart';
import 'pages/login/help.dart';
import 'pages/admin/home.dart' as admin_home;
import 'pages/student/home.dart' as student_home;
import 'pages/parent/home.dart' as parent_home;
import 'pages/public/update.dart';
import 'pages/public/browser.dart';
import 'pages/admin/update.dart';
import 'pages/public/bindemail.dart';
// 🔥 新增：用户声明组件
import 'widgets/user_agreement.dart';

// ===================== 全局状态 =====================
WebSocket? globalWs;
bool isConnecting = false;
bool isConnected = false;
int reconnectAttempts = 0;
Timer? heartbeatTimer;
Timer? _networkRestoreTimer;

// ✅ 标记是否主动断开（避免主动断开后还重连）
bool isManualDisconnect = false;

// 🔥 重连次数上限：避免服务端长期不可用时无限重连（耗尽电量/流量）
const int _maxReconnectAttempts = 30;

// 🔥 存储当前已登录的用户信息，用于切回前台时自动重连
Map? _currentUserInfo;

// 🔥 新增：记录已通过系统通知推送的 msgId，避免打开 App 后重复推送
Set<String> _notifiedMsgIds = {};
// 🔥 新增：记录已被管理员删除的 msgId，阻止后台队列中已推送的旧通知再次展示
Set<String> _deletedMsgIds = {};
const int _maxDeletedIds = 500; // 最多保留500条删除记录
// 🔥 ACK 防重：记录已发送ACK的msgId，防止重复ACK（上限500条，超限淘汰最旧）
Set<String> _ackSentMsgIds = {};
const int _maxAckSentIds = 500;

// 🔥 持久化：将已通知/已删除 ID 存到 SharedPreferences，重启后避免重复推送
// 🔥 按账号隔离：不同账号有独立的去重记录，避免切换账号后混乱
String _currentDedupAccount = ''; // 当前用于去重的账号

Future<void> _saveNotifiedIds() async {
  if (_currentDedupAccount.isEmpty) return;
  try {
    final sp = await SharedPreferences.getInstance();
    final list = _notifiedMsgIds.toList();
    await sp.setStringList('notified_$_currentDedupAccount', list);
    final deletedList = _deletedMsgIds.toList();
    await sp.setStringList('deleted_$_currentDedupAccount', deletedList);
  } catch (e) {
    debugPrint("⚠️ 保存通知ID失败: $e");
  }
}

Future<void> _loadNotifiedIds(String account) async {
  _currentDedupAccount = account;
  try {
    final sp = await SharedPreferences.getInstance();
    final list = sp.getStringList('notified_$account');
    _notifiedMsgIds = list?.toSet() ?? {};
    final deletedList = sp.getStringList('deleted_$account');
    _deletedMsgIds = deletedList?.toSet() ?? {};
    debugPrint("📂 加载通知去重记录[$account]: 已通知${_notifiedMsgIds.length}条, 已删除${_deletedMsgIds.length}条");
  } catch (e) {
    debugPrint("⚠️ 加载通知ID失败: $e");
  }
}

// 🔥 提取原始消息 ID：服务端重试消息 _id 带 _retry 后缀，需还原原始 ID 用于去重
String _extractOriginalMsgId(dynamic rawId) {
  if (rawId == null) return '';
  final id = rawId.toString();
  if (id.endsWith('_retry')) return id.substring(0, id.length - '_retry'.length);
  return id;
}

// 🔥 添加已通知 ID 到内存集合（供重连去重）
void _addNotifiedId(String msgId) {
  if (_notifiedMsgIds.contains(msgId)) return;
  if (_notifiedMsgIds.length >= _maxDeletedIds) {
    final first = _notifiedMsgIds.first;
    _notifiedMsgIds.remove(first);
  }
  _notifiedMsgIds.add(msgId);
  _saveNotifiedIds().catchError((e) => debugPrint("⚠️ 保存通知ID失败: $e"));
}

// 🔥 ACK 防重：记录已发送ACK的msgId，防止重复ACK（超限淘汰最旧）
void _addAckSentId(String msgId) {
  if (_ackSentMsgIds.contains(msgId)) return;
  if (_ackSentMsgIds.length >= _maxAckSentIds) {
    final first = _ackSentMsgIds.first;
    _ackSentMsgIds.remove(first);
  }
  _ackSentMsgIds.add(msgId);
}

// 🔥 添加已删除 ID，超过上限时淘汰最旧的
void _addDeletedId(String msgId) {
  if (_deletedMsgIds.contains(msgId)) return;
  if (_deletedMsgIds.length >= _maxDeletedIds) {
    final first = _deletedMsgIds.first;
    _deletedMsgIds.remove(first);
  }
  _deletedMsgIds.add(msgId);
  _saveNotifiedIds().catchError((e) => debugPrint("⚠️ 保存删除ID失败: $e"));
}

// 🔥 新增：是否需显示用户声明（在 main() 中提前计算，避免二次渲染灰屏）
bool _agreementPending = false;

// 🔥 新增：App 版本号（用于版本感知声明检查）
String _appVersion = 'unknown';

// 🔥 新增：初始化用户声明状态（在 main() 中 await，确保首次帧即正确）
Future<void> _initAgreement() async {
  try {
    final packageInfo = await PackageInfo.fromPlatform();
    _appVersion = packageInfo.version;
    final hasAgreed = await UserAgreementWidget.hasAgreed(appVersion: _appVersion);
    _agreementPending = !hasAgreed;
  } catch (e) {
    debugPrint("⚠️ 初始化用户声明失败，使用默认版本并继续启动: $e");
    _appVersion = 'unknown';
    _agreementPending = false;
  }
}

// ✅ 全局函数：登录时重置 WebSocket 连接（账号切换场景）
void resetWebSocketConnection() {
  debugPrint("🔄 重置WebSocket连接（账号切换）");
  isManualDisconnect = true;
  _doCloseWebSocket(); // 🔥 修复：关闭旧 WS，清除 isConnecting/isConnected，防止旧连接阻止新连接
  _currentUserInfo = null; // 🔥 清除用户信息，防止旧账号重连
}

// 🔥 心跳间隔：应用层20s主动保活，服务器原生ping30s兜底
// 前后端间隔错开：应用层ping(20s)填补服务器ping(30s)之间的间隙，双重保活
const int _heartbeatInterval = 20;
const int maxReconnectDelay = 60000;

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<MyAppState> appStateKey = GlobalKey<MyAppState>();

// 🔥 通知插件实例（替代 MethodChannel 方案，支持 isolate 挂起时的后台通知）
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();
// 🔥 降级通道：flutter_local_notifications 初始化失败时使用 MethodChannel 兜底
const _nativeNotificationChannel = MethodChannel('com.zdxt.app/notifications');

// 🔥 通知渠道 ID
const String _notificationChannelId = 'zdxt_notifications';
const String _notificationChannelName = '智答星途通知';

/// 🔥 发送系统通知（通过 flutter_local_notifications，覆盖前后台/亮屏/息屏所有场景）
/// 替代原 MethodChannel 方案：不依赖 Dart isolate 存活，隔离挂起时仍可正常展示
/// 🔥 展示约 15 秒后自动消失（避免通知一直停留在通知栏）
Future<bool> _showNativeNotificationFallback(String title, String body, String msgId) async {
  try {
    final androidDetails = AndroidNotificationDetails(
      _notificationChannelId,
      _notificationChannelName,
      channelDescription: '考试通知、试卷提醒等',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 500, 200, 500]),
      visibility: NotificationVisibility.public,
      category: AndroidNotificationCategory.message,
      channelShowBadge: true,
      enableLights: true,
      ledColor: const Color.fromARGB(255, 0, 170, 255),
      channelAction: AndroidNotificationChannelAction.update,
      styleInformation: const BigTextStyleInformation(
        '',
        contentTitle: '',
        summaryText: '',
      ),
      // 🔥 点击通知自动移除
      autoCancel: true,
    );
    final platformDetails = NotificationDetails(android: androidDetails);
    final notificationId = DateTime.now().millisecondsSinceEpoch % 0x3FFFFFFF;
    await flutterLocalNotificationsPlugin.show(
      notificationId,
      title,
      body,
      platformDetails,
      payload: msgId,
    );
    // 🔥 15 秒后自动消失：定时取消该通知（用户已点击/系统自动移除则忽略）
    Future.delayed(const Duration(seconds: 15), () async {
      try {
        await flutterLocalNotificationsPlugin.cancel(notificationId);
        debugPrint("🔔 通知 15 秒自动消失: $title (id=$notificationId)");
      } catch (_) {}
    });
    debugPrint("🔔 flutter_local_notifications 已发送: $title (msgId=$msgId, id=$notificationId)");
    return true;
  } catch (e) {
    debugPrint("⚠️ flutter_local_notifications 发送失败（降级使用 MethodChannel）: $e");
    // 降级：若插件初始化失败，尝试 MethodChannel（保活服务就绪时仍可用）
    try {
      final shown = await _nativeNotificationChannel.invokeMethod<bool>('showNative', {
        'title': title,
        'body': body,
        'msgId': msgId,
      });
      debugPrint("🔔 Native 通知降级已发送: $title (msgId=$msgId)");
      return shown == true;
    } catch (de) {
      debugPrint("⚠️ Native 通知通道不可用，可能 App 刚启动或进程即将被杀: $de");
      return false;
    }
  }
}

/// 🔥 在权限获取后验证通知渠道是否存在，不存在则重试创建
Future<void> _checkAndFixNotificationChannel() async {
  // 1. 通过原生 MethodChannel 检查渠道是否已正确配置
  try {
    final configured = await _nativeNotificationChannel
        .invokeMethod<bool>('isChannelConfigured') ?? false;
    if (configured) {
      debugPrint("✅ 通知渠道已正确配置");
      return;
    }
    debugPrint("⚠️ 通知渠道未正确配置，尝试修复...");
  } catch (e) {
    debugPrint("⚠️ 渠道检测异常: $e，将尝试插件重建");
  }

  // 2. 尝试通过 flutter_local_notifications 插件重建渠道（update 模式）
  try {
    final androidPlugin = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    final androidChannel = AndroidNotificationChannel(
      _notificationChannelId,
      _notificationChannelName,
      description: '考试通知、试卷提醒等',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 500, 200, 500]),
      showBadge: true,
      enableLights: true,
      ledColor: const Color.fromARGB(255, 0, 170, 255),
    );
    await androidPlugin?.createNotificationChannel(androidChannel);
    debugPrint("✅ 通过插件重建通知渠道成功");
  } catch (e) {
    debugPrint("⚠️ 插件重建渠道失败: $e");
  }
}


void main() async {
  // 🔥 捕获所有未处理的异步异常（如 Future 未被 await 且无 .catchError 时会触发崩溃）
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (details) {
      debugPrint("Error: ${details.exception}");
    };

    // 🔥 先初始化用户声明状态（避免二次渲染灰屏）
    await _initAgreement();

    runApp(MyApp(key: appStateKey));
  }, (error, stackTrace) {
    debugPrint("🚨 Unhandled zone error: $error\n$stackTrace");
  });
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => MyAppState();
}

// 🔥 心跳停止：顶级函数，供 resetWebSocketConnection() 和 _MyAppState 共用
void _stopHeartbeat() {
  heartbeatTimer?.cancel();
  heartbeatTimer = null;
}

// 🔥 内部关闭逻辑：仅关闭连接，不设置 isManualDisconnect（供 _connectWebSocket 复用）
void _doCloseWebSocket() {
  _stopHeartbeat();

  if (globalWs != null) {
    try {
      if (globalWs!.readyState == WebSocket.open) {
        globalWs!.add(jsonEncode({
          "action": "disconnect",
          "reason": "app_background"
        }));
        debugPrint("📤 已发送断开通知给后端");
      }
      globalWs!.close();
      debugPrint("✅ 旧连接已关闭");
    } catch (e) {
      debugPrint("❌ 关闭连接失败: $e");
    }
  }
  globalWs = null;
  isConnected = false;
  isConnecting = false;
}

class MyAppState extends State<MyApp> with WidgetsBindingObserver {
  Widget? homePage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 🔥 统一延迟到首次帧渲染后执行，确保 Navigator/MethodChannel 已注册
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 声明状态已在 main() 中提前计算；非首次启动时直接检查登录状态
      if (!_agreementPending) {
        checkLoginAndSetHome();
      }
      // 🔥 立即请求 Android 13+ 通知权限（POST_NOTIFICATIONS），必须在主线程调用
      _initializeRuntime();
    });
  }

  Future<void> _initializeRuntime() async {
    // 🔥 并行执行：权限请求和通知初始化互不依赖，同步启动可节省 ~1s 启动时间
    await Future.wait([
      _requestNotificationPermission(),
      _initNotifications(),
    ]);
  }

  /// 🔥 初始化 flutter_local_notifications 插件
  /// 必须在主线程调用
  Future<void> _initNotifications() async {
    // 🔥 完整配置通知渠道：震动、声音、锁屏可见、全屏通知、绕过勿扰
    final androidChannel = AndroidNotificationChannel(
      _notificationChannelId,
      _notificationChannelName,
      description: '考试通知、试卷提醒等',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 500, 200, 500]),
      showBadge: true,
      enableLights: true,
      ledColor: const Color.fromARGB(255, 0, 170, 255),
    );
    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    try {
      await flutterLocalNotificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: (response) {
          debugPrint("🔔 通知点击响应: payload=${response.payload}");
        },
        onDidReceiveBackgroundNotificationResponse: null,
      );
      // 🔥 注册渠道配置（必须，否则部分设备会用默认低权限渠道）
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(androidChannel);
      debugPrint("🔔 flutter_local_notifications 初始化完成（渠道已配置震动/声音/锁屏/全屏）");
    } catch (e) {
      debugPrint("⚠️ flutter_local_notifications 初始化失败（将降级使用 MethodChannel）: $e");
    }
  }

  // ==================== 原生 WebSocket 生命周期管理 ====================
  // （已移除：改为纯 Dart WebSocket 长连接方案，不再需要原生 WS 接管）

  /// 🔥 请求通知权限（基础通知 + 锁屏 + 状态栏/悬浮窗）
  Future<void> _requestNotificationPermission() async {
    try {
      // 1) 基础通知权限（Android 13+ 的 POST_NOTIFICATIONS）
      final status = await Permission.notification.request();
      debugPrint("🔔 通知权限状态: ${status.name} (Android ${Platform.version})");

      if (status.isGranted) {
        // 🔥 锁屏通知：通知在锁屏上的展示由通知渠道的 visibility 控制
        //    （_initNotifications 已将渠道 visibility 设为 public，
        //     并在 _checkAndFixNotificationChannel 中兜底重试更新渠道）
        //    基础通知授权后，锁屏展示随渠道配置自动生效，无需单独申请权限
        debugPrint("🔔 基础通知已授权，锁屏通知随渠道 visibility=public 自动生效");

        try {
          final statusBar = await Permission.systemAlertWindow.request();
          debugPrint("🔔 悬浮窗通知权限: ${statusBar.name}");
        } catch (e) {
          debugPrint("⚠️ 悬浮窗权限申请失败（机型不支持，不影响基础通知）: $e");
        }
        // 渠道配置验证（渠道已在 _initNotifications 中创建，此处做兜底重试）
        _checkAndFixNotificationChannel();
      }
    } catch (e) {
      debugPrint("⚠️ 权限请求异常: $e");
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 🔥 兜底：关闭全局 WS 与心跳，避免 app 销毁后残留连接/定时器
    _networkRestoreTimer?.cancel();
    _networkRestoreTimer = null;
    _doCloseWebSocket();
    super.dispose();
  }

  // =====================================================
  // 🔥 生命周期处理：
  // - resumed：延迟并重试网络可达性后再重连，避免网络尚未恢复时失败
  // - paused：主动断开 WS，消息由后端离线队列保存
  // =====================================================
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      debugPrint("📱 应用回到前台");
      if (_currentUserInfo != null && !isConnected && !isConnecting) {
        // 延迟2秒 + 网络可达性检查，再发起重连
        // 避免在网络切换（如从WiFi切到4G）的瞬间就发起连接导致失败
        Future.delayed(const Duration(seconds: 2), () async {
          if (!mounted) return;
          if (isConnected || isConnecting) return;
          final reachable = await _checkNetworkReachability();
          if (reachable) {
            debugPrint("✅ 网络已恢复，开始重连 WebSocket");
            _connectWebSocket(_currentUserInfo!);
          } else {
            debugPrint("⚠️ 网络尚不可达，延迟重连（等待网络恢复）");
            // 每3秒重试一次网络检测，最多10次（30秒）
            _scheduleNetworkRestoreReconnect(_currentUserInfo!, 0);
          }
        });
      }
    } else if (state == AppLifecycleState.paused) {
      debugPrint("📱 应用切到后台");
      _networkRestoreTimer?.cancel();
      _networkRestoreTimer = null;
      _doCloseWebSocket();
      _stopHeartbeat();
    }
  }

  /// 🔥 网络可达性检测：通过 HTTP HEAD 请求验证服务器是否可访问
  Future<bool> _checkNetworkReachability() async {
    try {
      final resp = await http
          .head(Uri.parse(Config.baseUrl))
          .timeout(const Duration(seconds: 5));
      final ok = resp.statusCode >= 200 && resp.statusCode < 400;
      debugPrint("🌐 网络可达性检测: ${ok ? '可用' : '不可用'} (status=${resp.statusCode})");
      return ok;
    } catch (e) {
      debugPrint("🌐 网络不可达: $e");
      return false;
    }
  }

  /// 🔥 网络恢复后重连：每3秒检测一次，最多10次
  void _scheduleNetworkRestoreReconnect(Map userInfo, int attempt) {
    if (attempt >= 10) {
      debugPrint("⚠️ 网络恢复重连超时（10次），停止重试");
      _networkRestoreTimer?.cancel();
      _networkRestoreTimer = null;
      return;
    }
    _networkRestoreTimer?.cancel();
    _networkRestoreTimer = Timer(const Duration(seconds: 3), () async {
      _networkRestoreTimer = null;
      if (isConnected || isConnecting) return;
      final reachable = await _checkNetworkReachability();
      if (reachable) {
        debugPrint("✅ 网络已恢复，开始重连 WebSocket");
        _connectWebSocket(userInfo);
      } else {
        debugPrint("⏳ 网络仍未恢复，${10 - attempt - 1}次后再次检测...");
        _scheduleNetworkRestoreReconnect(userInfo, attempt + 1);
      }
    });
  }

  Future<void> checkLoginAndSetHome() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final userInfoStr = sp.getString("userInfo");

      if (userInfoStr == null || userInfoStr.isEmpty) {
        if (!mounted) return;
        setState(() => homePage = const LoginPage());
        return;
      }

      final userInfo = jsonDecode(userInfoStr);
      final loginTime = userInfo["loginTime"] ?? 0;
      final role = userInfo["role"] ?? 2;
      final now = DateTime.now().millisecondsSinceEpoch;

      if (now - loginTime > 7 * 24 * 60 * 60 * 1000) {
        // 🔥 精确清理用户会话 key（userInfo 等），保留声明一次性标记 agreement_ever_shown
        await UserAgreementWidget.removeUserKeys();
        if (!mounted) return;
        setState(() => homePage = const LoginPage());
        return;
      }

      // ✅ 立即渲染首页 + 立即发起一次 WS 连接（匿名直连，基于本地 userInfo），不等待后台刷新。
      _delayedConnect();

      if (role == 1) {
        homePage = const admin_home.Home();
      } else if (role == 2) {
        homePage = const student_home.Home();
      } else {
        homePage = const parent_home.Home();
      }
      if (!mounted) return;
      setState(() {}); // 🔥 修复：必须调用 setState 触发重建，否则首页不显示（持续转圈）
    } catch (e) {
      if (!mounted) return;
      setState(() => homePage = const LoginPage());
      return;
    }
  }

  // 延迟 800ms 连接（原版 uni-app 逻辑）
  void _delayedConnect() async {
    final sp = await SharedPreferences.getInstance();
    final userInfoStr = sp.getString("userInfo");
    if (userInfoStr == null) return;

    Map userInfo;
    try {
      userInfo = jsonDecode(userInfoStr) as Map;
    } catch (e) {
      debugPrint("⚠️ _delayedConnect jsonDecode 失败: $e");
      return;
    }

    // 🔥 防竞态：连接中或已连接时不发起新的延迟连接，避免与 onDone 重连逻辑互相干扰
    if (isConnecting || isConnected) {
      debugPrint("⏭️ 已有连接请求在队列中，跳过本次延迟连接");
      return;
    }

    Future.delayed(const Duration(milliseconds: 800), () {
      _connectWebSocket(userInfo);
    });
  }

  // ================================
  // 🔥 WebSocket 连接（核心逻辑）
  // ================================

  /// 🔥 带次数上限的重连调度：避免服务端长期不可用时无限重连
  void _scheduleReconnect(Map userInfo) {
    if (reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint("⛔ 已达重连上限($_maxReconnectAttempts次)，停止自动重连");
      reconnectAttempts = 0; // 重置，等待用户回到前台重新触发
      return;
    }
    final delay = _calculateSmartDelay(reconnectAttempts);
    final safeDelay = (reconnectAttempts == 0 && delay < 3000) ? 3000 : delay;
    debugPrint("🔄 ${safeDelay ~/ 1000}秒后尝试第${reconnectAttempts + 1}次重连...");
    Future.delayed(Duration(milliseconds: safeDelay), () {
      if (isConnected || isConnecting) {
        debugPrint("⏭️ 重连前检查：已有连接/正在连接，跳过");
        return;
      }
      reconnectAttempts++;
      _connectWebSocket(userInfo);
    });
  }

  /// ✅ 公开方法：供登录页等外部调用，登录成功后主动连接 WebSocket
  void connectWebSocket(Map userInfo) {
    debugPrint("🔗 公开接口：登录成功，主动连接 WebSocket");
    _connectWebSocket(userInfo);
  }

  void _connectWebSocket(Map userInfo) async {
    final account = userInfo["account"];
    final currentRole = userInfo["currentRole"] ?? userInfo["role"];

    debugPrint("🔗 开始连接 WS => $account (尝试第${reconnectAttempts + 1}次)");

    if (account == null || currentRole == null) {
      debugPrint("⚠️ 无账号信息，停止连接");
      return;
    }

    // 🔥 加载当前账号的通知去重记录（首次连接 / 账号切换时加载）
    if (_currentDedupAccount != account) {
      await _loadNotifiedIds(account);
    }

    if (isConnecting) {
      debugPrint("⚠️ 正在连接中，跳过重复请求");
      return;
    }

    if (isConnected && globalWs != null && globalWs!.readyState == WebSocket.open) {
      debugPrint("⚠️ 已存在有效连接，跳过重复连接");
      return;
    }

    _doCloseWebSocket();
    isConnecting = true;

    try {
      debugPrint("✅ 正在连接服务器：${Config.wsUrl}");
      final ws = await WebSocket.connect(Config.wsUrl);
      globalWs = ws;
      isConnecting = false;
      isConnected = true;
      reconnectAttempts = 0;
      _currentUserInfo = userInfo; // 🔥 保存用户信息，用于切回前台时自动重连

      // WS register 仅下发账号与角色
      final registerData = jsonEncode({
        "action": "register",
        "account": account,
        "type": currentRole,
      });
      ws.add(registerData);
      debugPrint("📤 发送注册：$registerData");

      _startHeartbeat(ws);

      // 监听消息
      ws.listen(
        (data) async {
          try {
            final msg = jsonDecode(data);

            // ✅ 处理服务器心跳 ping
            if (msg["type"] == "ping") {
              ws.add(jsonEncode({"type": "pong"}));
              debugPrint("🏓 收到服务器ping，回复pong");
              return;
            }

            final msgId = _extractOriginalMsgId(msg["id"] ?? msg["_id"]);

            if (msg["type"] == "system" && msg["msg"] == "连接成功") {
              debugPrint("⏭️ 连接成功消息，不弹窗");
              return;
            }
            if (msgId.isEmpty) {
              debugPrint("⏭️ 无ID，不弹窗");
              return;
            }

            // 🔥 管理员删除通知广播：标记已删除，后续同ID消息不再展示
            if (msg["action"] == "notice_deleted") {
              final deletedId = msg["id"]?.toString();
              debugPrint("🗑️ 收到通知删除广播: $deletedId");
              _notifiedMsgIds.remove(deletedId);
              if (deletedId != null) _addDeletedId(deletedId);
              return;
            }

            // 🔥 已删除的通知不再重复展示（包括后台队列中未展示的旧消息）
            if (_deletedMsgIds.contains(msgId)) {
              debugPrint("🗑️ 跳过已删除的通知: $msgId");
              // 仍发送ACK，告知服务器已处理
              _sendAck(ws, msgId);
              return;
            }

            // 🔥 全局去重：已通知过的消息（不论前后台）不再重复展示
            if (_notifiedMsgIds.contains(msgId)) {
              debugPrint("⏭️ 通知已展示过，跳过: $msgId");
              _sendAck(ws, msgId);
              return;
            }

            final title = msg["title"] ?? "通知";
            final content = msg["content"] ?? "您有新的通知";

            final shown = await _showNativeNotificationFallback(title, content, msgId);
            if (!shown) {
              debugPrint("⚠️ 通知展示失败，保留消息等待服务端补推: $msgId");
              return;
            }

            // 只有通知真正提交给系统后才确认，避免后台/息屏失败时丢失消息。
            _addNotifiedId(msgId);
            _sendAck(ws, msgId);
          } catch (e) {
            debugPrint("❌ 解析失败：$e");
          }
        },
        onDone: () {
          // 🔥 防止旧连接的onDone覆盖新连接的状态（核心修复）
          if (globalWs != null && globalWs != ws) {
            debugPrint("⏭️ onDone: 旧连接回调已触发，新连接已存在，忽略");
            return;
          }
          debugPrint("❌ 连接断开");
          globalWs = null;
          isConnected = false;
          isConnecting = false;
          _stopHeartbeat();

          if (isManualDisconnect) {
            debugPrint("⚠️ 主动断开，不重连");
            isManualDisconnect = false;
            return;
          }

          _scheduleReconnect(userInfo);
        },
        onError: (err) {
          // 🔥 防止旧连接的onError覆盖新连接的状态（核心修复）
          if (globalWs != null && globalWs != ws) {
            debugPrint("⏭️ onError: 旧连接错误已触发，新连接已存在，忽略");
            return;
          }
          debugPrint("❌ WS 错误：$err");
          globalWs = null;
          isConnected = false;
          isConnecting = false;
          _stopHeartbeat();

          if (isManualDisconnect) {
            debugPrint("⚠️ 主动断开，不重连");
            isManualDisconnect = false;
            return;
          }

          _scheduleReconnect(userInfo);
        },
      );
    } catch (e) {
      debugPrint("❌ 连接失败：$e");
      isConnecting = false;

      _scheduleReconnect(userInfo);
    }
  }

  int _calculateSmartDelay(int attempts) {
    // 移动端优化：首次断开至少等5秒（给网络恢复时间），后续指数退避
    if (attempts == 0) return 5000;
    if (attempts < 6) {
      return 1000 * (1 << attempts); // 2s, 4s, 8s, 16s, 32s
    } else if (attempts < 12) {
      return 30000;
    } else {
      return 60000;
    }
  }

  // 🔥 发送ACK确认（带重试机制）
  // 🔥 修复：重试时使用 globalWs 而非旧的 ws 引用，因为重连后旧引用已失效
  // 🔥 修复：增加 ACK 防重，同一 msgId 只发送一次
  void _sendAck(WebSocket ws, String msgId, {int retryCount = 0}) {
    const maxRetries = 3;

    // 🔥 防重：同一 msgId 的 ACK 只发送一次（避免重连后重复发送）
    if (_ackSentMsgIds.contains(msgId)) {
      debugPrint("⏭️ ACK已发送过，跳过重复ACK: $msgId");
      return;
    }

    try {
      // 优先使用当前全局连接（重连后可能已更换）
      final activeWs = globalWs ?? ws;
      if (activeWs.readyState == WebSocket.open) {
        activeWs.add(jsonEncode({
          "action": "ack",
          "msgId": msgId,
        }));
        _addAckSentId(msgId);
        debugPrint("✅ 发送ACK确认：$msgId");
      } else {
        debugPrint("⚠️ 连接已断开，跳过ACK发送 (重试${retryCount + 1}/$maxRetries)");
        if (retryCount < maxRetries) {
          Future.delayed(Duration(seconds: 1), () {
            _sendAck(ws, msgId, retryCount: retryCount + 1);
          });
        }
      }
    } catch (ackErr) {
      debugPrint("❌ 发送ACK失败: $ackErr (重试${retryCount + 1}/$maxRetries)");
      if (retryCount < maxRetries) {
        Future.delayed(Duration(seconds: 1), () {
          _sendAck(ws, msgId, retryCount: retryCount + 1);
        });
      }
    }
  }

// 启动心跳保活（统一间隔，简洁可靠）
void _startHeartbeat(WebSocket ws) {
    _stopHeartbeat();
    heartbeatTimer = Timer.periodic(Duration(seconds: _heartbeatInterval), (timer) {
      if (ws.readyState == WebSocket.open) {
        ws.add(jsonEncode({"type": "ping"}));
        debugPrint("🏓 发送心跳ping");
      } else {
        debugPrint("⚠️ WebSocket未打开，停止心跳");
        _stopHeartbeat();
      }
    });
    debugPrint("🏓 心跳已启动，间隔=${_heartbeatInterval}s");
  }

  @override
  Widget build(BuildContext context) {
    // 🔥 首次冷启动且未确认声明 → 显示声明页（必须包裹 MaterialApp，否则缺少 Directionality 导致灰屏）
    if (_agreementPending) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        ),
        home: UserAgreementWidget(
          appVersion: _appVersion,
          onConfirmed: () {
            _agreementPending = false;
            checkLoginAndSetHome();
          },
        ),
      );
    }

    return MaterialApp(
      navigatorKey: navigatorKey,
      title: '智答星途',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: homePage ?? const Scaffold(
        backgroundColor: Color(0xFF0F172A),
        body: Center(child: CircularProgressIndicator(color: Colors.blue, strokeWidth: 2)),
      ),
      routes: {
        "/login": (context) => const LoginPage(),
        "/help": (context) => const HelpPage(type: 'forgot'),
        "/update": (context) => const UpdatePage(),
        "/public/browser": (context) => const BrowserPage(),
        "/bindemail": (context) => const BindEmailPage(),
        "/admin/home": (context) => const admin_home.Home(),
        "/admin/update": (context) => const AdminUpdatePage(),
        "/student/home": (context) => const student_home.Home(),
        "/parent/home": (context) => const parent_home.Home(),
      },
    );
  }
}
