import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 🔥 通知删除广播工具
/// 由 main.dart 调用 setGlobalWebSocket 传入全局连接，
/// notice.dart 调用 broadcastNoticeDeleted 发送广播。
/// 此文件作为中间层，避免 main.dart ↔ notice.dart 循环引用。

WebSocket? _ws;

/// 由 main.dart 在初始化时注册全局 WebSocket 连接
void setGlobalWebSocket(WebSocket? ws) {
  _ws = ws;
}

/// 管理员删除通知时广播给所有客户端（清除离线队列 + 通知在线用户）
void broadcastNoticeDeleted(String noticeId) {
  if (_ws != null && _ws!.readyState == WebSocket.open) {
    _ws!.add(jsonEncode({
      "action": "notice_deleted",
      "id": noticeId,
    }));
    debugPrint("📢 广播通知已删除: $noticeId");
  } else {
    debugPrint("⚠️ WebSocket 未连接，跳过广播删除通知: $noticeId");
  }
}
