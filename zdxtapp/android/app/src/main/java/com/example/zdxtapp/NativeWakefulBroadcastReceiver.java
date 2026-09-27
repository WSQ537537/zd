package com.example.zdxtapp;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.util.Log;

/**
 * 开机/崩溃后自动重启保活服务
 * 系统广播 android.intent.action.BOOT_COMPLETED 触发时自动启动 KeepAliveService
 * 解决设备重启或系统清理进程后，保活服务无法自动恢复的问题
 */
public class NativeWakefulBroadcastReceiver extends BroadcastReceiver {
    private static final String TAG = "ZdxtNotify";

    @Override
    public void onReceive(Context context, Intent intent) {
        String action = intent.getAction();
        Log.d(TAG, "📡 收到广播: " + action);

        if (action == null) return;

        // 开机完成 → 启动保活服务
        if (android.content.Intent.ACTION_BOOT_COMPLETED.equals(action)) {
            Log.d(TAG, "🔄 开机广播 → 启动 KeepAliveService");
            startKeepAliveService(context);
        }
        // Flutter 层 ping 广播 → Native 层仅做日志记录（Dart isolate 由 KeepAliveService 维持心跳）
        else if (KeepAliveService.PING_BROADCAST_ACTION.equals(action)) {
            Log.d(TAG, "🏓 Native ping 广播收到（Dart 侧已有独立心跳，无需转发）");
        }
        // App 主动请求重启保活服务（用于崩溃后恢复）
        else if ("com.zdxt.app.ACTION_RESTART_KEEPALIVE".equals(action)) {
            Log.d(TAG, "🔄 重启保活服务请求 → 启动 KeepAliveService");
            startKeepAliveService(context);
        }
    }

    private void startKeepAliveService(Context context) {
        try {
            Intent serviceIntent = new Intent(context, KeepAliveService.class);
            serviceIntent.setAction("com.zdxt.app.ACTION_START_KEEPALIVE");
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent);
            } else {
                context.startService(serviceIntent);
            }
            Log.d(TAG, "✅ KeepAliveService 已启动");
        } catch (Exception e) {
            Log.e(TAG, "❌ 启动 KeepAliveService 失败: " + e.getMessage(), e);
        }
    }
}
