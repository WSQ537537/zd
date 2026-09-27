package com.example.zdxtapp;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.media.AudioAttributes;
import android.media.RingtoneManager;
import android.net.Uri;
import android.os.Build;

import androidx.core.app.NotificationCompat;

/**
 * 通知工具类：负责通知渠道创建和系统通知发送。
 * 不依赖任何 Service 或前台服务，可在任意 Context 下调用。
 */
public class NotificationUtils {

    private static final String CHANNEL_ID = "zdxt_notifications";
    private static final int NOTIFICATION_ID = 1;

    // 通知 ID 自增计数器，防止同一毫秒内多次通知被系统合并丢弃
    private static int notificationIdCounter = 0;

    /**
     * 初始化通知渠道（App 启动时调用一次即可）。
     * 渠道创建后不可修改，首次创建决定所有属性。
     */
    public static void initChannels(Context context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return;
        NotificationManager nm = context.getSystemService(NotificationManager.class);
        if (nm == null) return;

        NotificationChannel existing = nm.getNotificationChannel(CHANNEL_ID);
        if (existing != null) {
            boolean needsRecreate = false;
            if (existing.getImportance() < NotificationManager.IMPORTANCE_HIGH) needsRecreate = true;
            if (existing.getLockscreenVisibility() != Notification.VISIBILITY_PUBLIC) needsRecreate = true;
            if (!existing.shouldVibrate()) needsRecreate = true;
            if (!existing.canBypassDnd()) needsRecreate = true;
            if (!existing.shouldShowLights()) needsRecreate = true;
            if (needsRecreate) {
                nm.deleteNotificationChannel(CHANNEL_ID);
            }
        }

        NotificationChannel channel = new NotificationChannel(
                CHANNEL_ID,
                "智答星途通知",
                NotificationManager.IMPORTANCE_MAX
        );
        channel.setDescription("考试通知、试卷提醒等");
        channel.enableVibration(true);
        channel.setVibrationPattern(new long[]{0, 500, 200, 500});
        channel.setLockscreenVisibility(Notification.VISIBILITY_PUBLIC);
        channel.setBypassDnd(true);
        channel.setShowBadge(true);
        channel.enableLights(true);
        channel.setLightColor(0xFF00AAFF);
        Uri soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION);
        AudioAttributes audioAttrs = new AudioAttributes.Builder()
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                .build();
        channel.setSound(soundUri, audioAttrs);
        nm.createNotificationChannel(channel);
    }

    /**
     * 验证通知渠道是否已正确配置（重要性 HIGH/MAX + 锁屏可见 + 可震动 + 可绕过免打扰）。
     * 用于启动时自检，若渠道缺失或配置降级则返回 false。
     */
    public static boolean isChannelConfigured(Context context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return true;
        NotificationManager nm = context.getSystemService(NotificationManager.class);
        if (nm == null) return false;
        NotificationChannel channel = nm.getNotificationChannel(CHANNEL_ID);
        if (channel == null) return false;
        return channel.getImportance() >= NotificationManager.IMPORTANCE_HIGH
                && channel.getLockscreenVisibility() == Notification.VISIBILITY_PUBLIC
                && channel.shouldVibrate()
                && channel.canBypassDnd();
    }

    /**
     * 发送系统通知（Native 层，不依赖 Dart isolate）。
     * 用于 flutter_local_notifications 初始化失败时的降级方案。
     */
    public static boolean showNotification(Context ctx, String title, String body, String msgId) {
        try {
            NotificationManager nm = ctx.getSystemService(NotificationManager.class);
            if (nm == null) return false;

            int notifId = (int) (System.currentTimeMillis() % 0x3FFFFFFF) + ++notificationIdCounter;

            Intent notificationIntent = new Intent(ctx, MainActivity.class);
            notificationIntent.setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_CLEAR_TOP);
            PendingIntent pendingIntent = PendingIntent.getActivity(
                    ctx, notifId, notificationIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
            );

            Notification notification = new NotificationCompat.Builder(ctx, CHANNEL_ID)
                    .setSmallIcon(R.mipmap.ic_launcher)
                    .setContentTitle(title)
                    .setContentText(body)
                    .setPriority(NotificationCompat.PRIORITY_MAX)
                    .setCategory(NotificationCompat.CATEGORY_MESSAGE)
                    .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                    .setAutoCancel(true)
                    .setVibrate(new long[]{0, 500, 200, 500})
                    .setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION))
                    .setContentIntent(pendingIntent)
                    .setFullScreenIntent(pendingIntent, true)
                    .build();

            nm.notify(notifId, notification);
            android.util.Log.d("ZdxtNotify", "🔔 Native 通知已发送: " + title);
            return true;
        } catch (Exception e) {
            android.util.Log.e("ZdxtNotify", "❌ Native 通知发送失败: " + e.getMessage(), e);
            return false;
        }
    }
}
