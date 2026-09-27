package com.example.zdxtapp;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.pm.ServiceInfo;
import android.media.AudioAttributes;
import android.media.RingtoneManager;
import android.net.Uri;
import android.os.Build;
import android.os.IBinder;
import android.os.PowerManager;
import android.provider.Settings;
import androidx.core.app.NotificationCompat;
import androidx.core.app.NotificationManagerCompat;
import io.flutter.plugin.common.EventChannel;

import java.util.HashSet;
import java.util.Set;
import java.util.Timer;
import java.util.TimerTask;

public class KeepAliveService extends Service {
    private static final String KEEP_ALIVE_CHANNEL_ID = "keep_alive";
    private static final String NOTIFICATION_CHANNEL_ID = "zdxt_notifications";
    private static final int NOTIFICATION_ID = 1;
    public static final String PING_BROADCAST_ACTION = "com.zdxt.app.ACTION_NATIVE_PING";

    // 🔥 静态实例引用，供静态方法访问 Context
    private static KeepAliveService instance;

    private PowerManager.WakeLock wakeLock;
    private Timer nativePingTimer;

    // 🔥 通知ID自增计数器，防止同一毫秒内多条通知 ID 碰撞被系统静默丢弃
    private static int notificationIdCounter = 0;

    // 🔥 原生 WebSocket 客户端（独立于 Dart isolate 运行，解决 Android 16 后台通知失效）
    private static NativeWebSocketClient nativeWsClient;
    // 🔥 EventSink：连接状态变更时推送给 Dart 侧
    private static EventChannel.EventSink nativeWsStateSink;

    @Override
    public void onCreate() {
        super.onCreate();
        instance = this;
        createChannels();
        acquireWakeLock();
        // 🔥 启动 Native 层周期 ping（不依赖 Dart isolate），每 15s 发送广播
        startNativePeriodicPing();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        // 🔥 每次启动都校验渠道（服务被系统重启时确保渠道配置正确）
        createChannels();
        Notification notification = buildKeepAliveNotification();
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE);
        } else {
            startForeground(NOTIFICATION_ID, notification);
        }
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        instance = null;
        stopNativePeriodicPing();
        releaseWakeLock();
        stopNativeWs();
        stopForeground(true);
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    // ==================== Native 层周期 ping ====================
    private void startNativePeriodicPing() {
        stopNativePeriodicPing();
        nativePingTimer = new Timer("ZdxtNativePing", true);
        nativePingTimer.scheduleAtFixedRate(new TimerTask() {
            @Override
            public void run() {
                try {
                    Intent pingIntent = new Intent(PING_BROADCAST_ACTION);
                    pingIntent.putExtra("timestamp", System.currentTimeMillis());
                    sendBroadcast(pingIntent);
                    android.util.Log.d("ZdxtNotify", "🏓 Native ping 广播已发送");
                } catch (Exception e) {
                    android.util.Log.e("ZdxtNotify", "❌ Native ping 广播发送失败: " + e.getMessage());
                }
            }
        }, 15000, 15000); // 15秒间隔
        android.util.Log.d("ZdxtNotify", "🔒 Native 周期 ping 已启动（15s 间隔）");
    }

    private void stopNativePeriodicPing() {
        if (nativePingTimer != null) {
            nativePingTimer.cancel();
            nativePingTimer = null;
            android.util.Log.d("ZdxtNotify", "🛑 Native 周期 ping 已停止");
        }
    }

    // ==================== 通知通道 ====================
    private void createChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationManager nm = getSystemService(NotificationManager.class);

            // ===== 保活通道 =====
            NotificationChannel existingKeep = nm.getNotificationChannel(KEEP_ALIVE_CHANNEL_ID);
            if (existingKeep != null) {
                boolean needsRecreate = false;
                if (existingKeep.getImportance() < NotificationManager.IMPORTANCE_HIGH) needsRecreate = true;
                if (existingKeep.getLockscreenVisibility() != Notification.VISIBILITY_PUBLIC) needsRecreate = true;
                // 🔥 保活通道不震动不发声，不需要检查震动/灯光
                if (needsRecreate) {
                    nm.deleteNotificationChannel(KEEP_ALIVE_CHANNEL_ID);
                    android.util.Log.w("ZdxtNotify", "🗑️ 保活渠道设置异常，已删除重建");
                }
            }

            NotificationChannel keepChannel = new NotificationChannel(
                    KEEP_ALIVE_CHANNEL_ID,
                    "后台保活",
                    NotificationManager.IMPORTANCE_HIGH
            );
            keepChannel.setDescription("保持应用在后台运行");
            keepChannel.setShowBadge(false);
            // 🔥 保活通知不震动、不发声，仅在状态栏显示服务在运行
            keepChannel.enableVibration(false);
            keepChannel.setLockscreenVisibility(Notification.VISIBILITY_PUBLIC);
            keepChannel.setSound(null, null);
            keepChannel.enableLights(false);
            nm.createNotificationChannel(keepChannel);

            // ===== 消息通知通道 =====
            // 渠道校验：Android 8.0+ 渠道创建后不可变，若旧版本以低重要性创建，需删除重建
            NotificationChannel existingMsg = nm.getNotificationChannel(NOTIFICATION_CHANNEL_ID);
            if (existingMsg != null) {
                android.util.Log.i("ZdxtNotify", "📊 当前消息渠道: importance=" + existingMsg.getImportance()
                        + " visibility=" + existingMsg.getLockscreenVisibility()
                        + " vibrate=" + existingMsg.shouldVibrate()
                        + " bypassDnd=" + existingMsg.canBypassDnd()
                        + " lights=" + existingMsg.shouldShowLights());
                boolean needsRecreate = false;
                if (existingMsg.getImportance() < NotificationManager.IMPORTANCE_HIGH) needsRecreate = true;
                if (existingMsg.getLockscreenVisibility() != Notification.VISIBILITY_PUBLIC) needsRecreate = true;
                if (!existingMsg.shouldVibrate()) needsRecreate = true;
                if (!existingMsg.canBypassDnd()) needsRecreate = true;
                if (!existingMsg.shouldShowLights()) needsRecreate = true;
                if (needsRecreate) {
                    nm.deleteNotificationChannel(NOTIFICATION_CHANNEL_ID);
                    android.util.Log.w("ZdxtNotify", "🗑️ 消息渠道设置异常(importance=" + existingMsg.getImportance()
                            + ")，已删除重建");
                }
            }

            NotificationChannel msgChannel = new NotificationChannel(
                    NOTIFICATION_CHANNEL_ID,
                    "智答星途通知",
                    NotificationManager.IMPORTANCE_MAX
            );
            msgChannel.setDescription("考试通知、试卷提醒等");
            msgChannel.enableVibration(true);
            msgChannel.setVibrationPattern(new long[]{0, 500, 200, 500});
            msgChannel.setLockscreenVisibility(Notification.VISIBILITY_PUBLIC);
            msgChannel.setBypassDnd(true);
            msgChannel.setShowBadge(true);
            msgChannel.enableLights(true);
            msgChannel.setLightColor(0xFF00AAFF);
            Uri soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION);
            AudioAttributes audioAttrs = new AudioAttributes.Builder()
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .build();
            msgChannel.setSound(soundUri, audioAttrs);
            nm.createNotificationChannel(msgChannel);
        }
    }

    private Notification buildKeepAliveNotification() {
        return buildKeepAliveNotification("正在保持连接...");
    }

    private Notification buildKeepAliveNotification(String statusText) {
        return new NotificationCompat.Builder(this, KEEP_ALIVE_CHANNEL_ID)
                .setContentTitle("智答星途")
                .setContentText(statusText)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setOngoing(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_SERVICE)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setOnlyAlertOnce(true)
                .setContentIntent(null)
                .build();
    }

    /**
     * 🔥 根据当前连接状态更新保活通知文本
     */
    public static void refreshKeepAliveNotification() {
        if (nativeWsClient == null) return;
        try {
            KeepAliveService service = KeepAliveService.instance;
            if (service == null) return;
            String statusText = nativeWsClient.getConnectionStateDetail();
            Notification notif = service.buildKeepAliveNotification(statusText);
            android.app.NotificationManager nm =
                    service.getSystemService(android.app.NotificationManager.class);
            if (nm != null) {
                nm.notify(NOTIFICATION_ID, notif);
                android.util.Log.d("ZdxtNotify", "🔔 保活通知已刷新: " + statusText);
            }
        } catch (Exception e) {
            android.util.Log.e("ZdxtNotify", "刷新保活通知失败", e);
        }
    }

    private void acquireWakeLock() {
        PowerManager pm = (PowerManager) getSystemService(POWER_SERVICE);
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "ZdxtApp:KeepAlive");
        wakeLock.setReferenceCounted(false);
        wakeLock.acquire();
        android.util.Log.d("ZdxtNotify", "🔒 WakeLock 已获取（永久，随服务生命周期释放）");
    }

    private void releaseWakeLock() {
        if (wakeLock != null && wakeLock.isHeld()) {
            wakeLock.release();
            wakeLock = null;
        }
    }

    /**
     * 立即显示系统通知（Native 层，不依赖 Dart isolate）
     * 使用毫秒时间戳作为通知 ID，彻底避免同一毫秒内多次通知 ID 碰撞
     * 🔥 启用全屏通知：息屏/锁屏时强制弹出唤醒屏幕
     */
    public static void showNativeNotification(android.content.Context ctx,
                                               String title, String body, String msgId) {
        try {
            NotificationManager nm = ctx.getSystemService(NotificationManager.class);
            if (nm == null) return;

            // 🔥 使用毫秒时间戳+自增计数器，保证 ID 全局唯一，避免小米/华为等品牌静默丢弃重复 ID 通知
            int notifId = (int) (System.currentTimeMillis() % 0x3FFFFFFF) + ++notificationIdCounter;

            // 🔥 创建全屏点击意图：点击通知后直接打开 App（用于全屏唤醒场景）
            Intent notificationIntent = new Intent(ctx, MainActivity.class);
            notificationIntent.setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_CLEAR_TOP);
            PendingIntent pendingIntent = PendingIntent.getActivity(
                    ctx,
                    notifId,
                    notificationIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
            );

            // 🔥 构建通知（CATEGORY_CALL + setFullScreenIntent 使息屏时强制弹出全屏通知）
            NotificationCompat.Builder builder = new NotificationCompat.Builder(ctx, NOTIFICATION_CHANNEL_ID)
                    .setSmallIcon(R.mipmap.ic_launcher)
                    .setContentTitle(title)
                    .setContentText(body)
                    .setPriority(NotificationCompat.PRIORITY_MAX)
                    .setCategory(NotificationCompat.CATEGORY_CALL)
                    .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                    .setAutoCancel(true)
                    .setVibrate(new long[]{0, 500, 200, 500})
                    .setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION))
                    .setOnlyAlertOnce(false)
                    .setGroup("zdxt_messages")
                    .setGroupSummary(false)
                    .setContentIntent(pendingIntent)
                    // 🔥 启用全屏通知：息屏/锁屏时强制拉起 Activity 唤醒屏幕
                    .setFullScreenIntent(pendingIntent, true);

            Notification notification = builder.build();
            nm.notify(notifId, notification);
            android.util.Log.d("ZdxtNotify", "🔔 Native 通知已发送: id=" + notifId + " title=" + title);
        } catch (Exception e) {
            android.util.Log.e("ZdxtNotify", "❌ Native 通知发送失败: " + e.getMessage(), e);
        }
    }

    // ==================== 原生 WebSocket 管理 ====================

    /**
     * 设置 Native WS 连接状态 EventSink（由 MainActivity 注入）
     */
    public static void setNativeWsStateSink(EventChannel.EventSink sink) {
        nativeWsStateSink = sink;
        android.util.Log.d("ZdxtNotify", "📡 EventSink 已注册");
    }

    /**
     * 启动原生 WebSocket（App 切后台时调用）
     * 独立于 Dart isolate，直接在 Native 层接收消息并显示通知
     */
    public static void startNativeWs(android.content.Context ctx, String wsUrl, String account, int role) {
        if (nativeWsClient != null) {
            nativeWsClient.stop();
        }
        nativeWsClient = new NativeWebSocketClient(ctx, wsUrl, account, role);
        // 🔥 监听连接状态变更，实时推送给 Dart 侧 + 刷新保活通知
        nativeWsClient.setOnConnectionStateChangedListener((state, detail) -> {
            android.util.Log.d("ZdxtNotify", "🔗 Native WS 状态变更: " + state + " - " + detail);
            if (nativeWsStateSink != null) {
                try {
                    nativeWsStateSink.success(state.name() + ":" + detail);
                } catch (Exception e) {
                    android.util.Log.e("ZdxtNotify", "EventSink 发送失败", e);
                }
            }
            // 🔥 同时刷新保活通知的文本内容
            refreshKeepAliveNotification();
        });
        nativeWsClient.start();
        android.util.Log.i("ZdxtNotify", "🚀 原生 WebSocket 已启动: account=" + account + " url=" + wsUrl);
    }

    /**
     * 停止原生 WebSocket（App 回前台时调用）
     */
    public static void stopNativeWs() {
        if (nativeWsClient != null) {
            nativeWsClient.stop();
            nativeWsClient = null;
            android.util.Log.i("ZdxtNotify", "🛑 原生 WebSocket 已停止");
        }
    }

    /**
     * 获取原生 WS 已展示的消息 ID（供 Dart 侧合并去重）
     */
    public static Set<String> getNativeShownIds() {
        if (nativeWsClient != null) {
            return nativeWsClient.getAndClearShownIds();
        }
        return new HashSet<>();
    }

    /**
     * 检查原生 WS 是否正在运行
     */
    public static boolean isNativeWsRunning() {
        return nativeWsClient != null && nativeWsClient.isRunning();
    }

    // ==================== 连接状态查询 ====================

    /**
     * 获取原生 WS 当前连接状态（供 Dart 侧 UI 实时更新）
     */
    public static String getConnectionState() {
        if (nativeWsClient == null) return "DISCONNECTED";
        return nativeWsClient.getConnectionState().name();
    }

    /**
     * 获取连接状态详情描述
     */
    public static String getConnectionStateDetail() {
        if (nativeWsClient == null) return "";
        return nativeWsClient.getConnectionState().name();
    }
}
