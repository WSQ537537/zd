package com.example.zdxtapp;

import android.content.Context;
import android.content.SharedPreferences;
import android.util.Log;

import org.json.JSONObject;

import java.util.HashSet;
import java.util.Iterator;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.TimeUnit;

import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;
import okhttp3.WebSocket;
import okhttp3.WebSocketListener;

public class NativeWebSocketClient {
    private static final String TAG = "ZdxtNativeWS";
    private static final String PREFS_NAME = "native_ws_dedup";
    private static final String SHOWN_IDS_KEY = "shown_msg_ids";
    private static final String DELETED_IDS_KEY = "deleted_msg_ids";
    private static final int MAX_DEDUP_IDS = 300;
    private static final int HEARTBEAT_INTERVAL_SEC = 20;

    // 🔥 连接状态枚举
    public enum ConnectionState { DISCONNECTED, CONNECTING, CONNECTED, FAILED }

    private final Context context;
    private final String wsUrl;
    private final String account;
    private final int role;

    private OkHttpClient client;
    private WebSocket webSocket;
    private volatile boolean isRunning = false;
    private volatile boolean isStopped = false;
    private int reconnectAttempts = 0;
    // 🔥 实时连接状态
    private volatile ConnectionState connectionState = ConnectionState.DISCONNECTED;
    // 🔥 连接状态详情（用于显示）
    private volatile String connectionStateDetail = "";
    // 🔥 是否已向服务端发送过 register（即完成握手）
    private volatile boolean registered = false;

    private final ScheduledExecutorService scheduler;
    private ScheduledFuture<?> heartbeatFuture;
    private ScheduledFuture<?> reconnectFuture;

    private final Set<String> shownMsgIds = ConcurrentHashMap.newKeySet();
    private final Set<String> deletedMsgIds = ConcurrentHashMap.newKeySet();
    // 🔥 连接状态变更回调（供 KeepAliveService 转发给 Dart）
    private OnConnectionStateChangedListener stateChangeListener;

    public interface OnConnectionStateChangedListener {
        void onStateChanged(ConnectionState state, String detail);
    }

    public void setOnConnectionStateChangedListener(OnConnectionStateChangedListener listener) {
        this.stateChangeListener = listener;
    }

    public ConnectionState getConnectionState() {
        return connectionState;
    }

    public String getConnectionStateDetail() {
        return connectionStateDetail;
    }

    public NativeWebSocketClient(Context context, String wsUrl, String account, int role) {
        this.context = context.getApplicationContext();
        this.wsUrl = wsUrl;
        this.account = account;
        this.role = role;
        this.scheduler = Executors.newSingleThreadScheduledExecutor(r -> {
            Thread t = new Thread(r, "ZdxtNativeWS-Thread");
            t.setDaemon(true);
            return t;
        });
        loadDedupIds();
    }

    public synchronized void start() {
        if (isRunning) {
            Log.d(TAG, "Native WS already running, skip");
            return;
        }
        isRunning = true;
        isStopped = false;
        reconnectAttempts = 0;
        registered = false;
        setConnectionState(ConnectionState.CONNECTING, "正在连接...");
        connect();
    }

    public synchronized void stop() {
        isRunning = false;
        isStopped = true;
        registered = false;
        setConnectionState(ConnectionState.DISCONNECTED, "已停止");
        stopHeartbeat();
        cancelReconnect();
        if (webSocket != null) {
            try {
                webSocket.close(1000, "App foreground");
            } catch (Exception e) {
                Log.e(TAG, "Error closing native WS", e);
            }
            webSocket = null;
        }
        Log.d(TAG, "Native WS stopped");
    }

    public boolean isRunning() {
        return isRunning;
    }

    private void connect() {
        if (!isRunning || isStopped) return;

        try {
            if (client == null) {
                client = new OkHttpClient.Builder()
                        .pingInterval(15, TimeUnit.SECONDS)
                        .readTimeout(0, TimeUnit.MILLISECONDS)
                        .connectTimeout(10, TimeUnit.SECONDS)
                        .build();
            }

            Request request = new Request.Builder().url(wsUrl).build();
            Log.i(TAG, "Connecting native WS: " + wsUrl + " account=" + account);

            webSocket = client.newWebSocket(request, new WebSocketListener() {
                @Override
                public void onOpen(WebSocket ws, Response response) {
                    Log.i(TAG, "Native WS connected");
                    reconnectAttempts = 0;
                    registered = false;
                    setConnectionState(ConnectionState.CONNECTED, "已连接");
                    registerAccount(ws);
                    startHeartbeat(ws);
                }

                @Override
                public void onMessage(WebSocket ws, String text) {
                    handleMessage(text, ws);
                }

                @Override
                public void onClosing(WebSocket ws, int code, String reason) {
                    ws.close(1000, null);
                }

                @Override
                public void onClosed(WebSocket ws, int code, String reason) {
                    Log.i(TAG, "Native WS closed: code=" + code + " reason=" + reason);
                    onDisconnected(code);
                }

                @Override
                public void onFailure(WebSocket ws, Throwable t, Response response) {
                    Log.e(TAG, "Native WS failure: " + t.getMessage(), t);
                    onDisconnected(-1);
                }
            });
        } catch (Exception e) {
            Log.e(TAG, "Connect failed", e);
            onDisconnected(-1);
        }
    }

    private void registerAccount(WebSocket ws) {
        try {
            JSONObject register = new JSONObject();
            register.put("action", "register");
            register.put("account", account);
            register.put("type", role);
            ws.send(register.toString());
            registered = true;
            Log.d(TAG, "Registered: " + register);
        } catch (Exception e) {
            Log.e(TAG, "Register failed", e);
        }
    }

    private void handleMessage(String text, WebSocket ws) {
        if (isStopped) return;
        try {
            JSONObject msg = new JSONObject(text);

            // Server heartbeat ping
            String type = msg.optString("type", "");
            if ("ping".equals(type)) {
                JSONObject pong = new JSONObject();
                pong.put("type", "pong");
                ws.send(pong.toString());
                return;
            }

            // Skip connection success
            if ("system".equals(type) && "连接成功".equals(msg.optString("msg", ""))) {
                return;
            }

            String msgId = msg.optString("id", msg.optString("_id", ""));
            if (msgId.isEmpty()) return;
            // 🔥 服务端重试消息 _id 带 _retry 后缀，提取原始 ID 用于去重
            if (msgId.endsWith("_retry")) {
                msgId = msgId.substring(0, msgId.length() - "_retry".length());
            }

            // Handle notice deletion
            String action = msg.optString("action", "");
            if ("notice_deleted".equals(action)) {
                String deletedId = msg.optString("id", "");
                if (!deletedId.isEmpty()) {
                    shownMsgIds.remove(deletedId);
                    addDeletedId(deletedId);
                }
                return;
            }

            // Skip deleted messages
            if (deletedMsgIds.contains(msgId)) {
                sendAck(ws, msgId);
                return;
            }

            // Dedup
            if (shownMsgIds.contains(msgId)) {
                sendAck(ws, msgId);
                return;
            }

            String title = msg.optString("title", "通知");
            String content = msg.optString("content", "您有新的通知");

            // Send ACK immediately
            sendAck(ws, msgId);

            // Record shown ID
            addShownId(msgId);

            // Show notification directly (no Dart isolate needed)
            KeepAliveService.showNativeNotification(context, title, content, msgId);
            Log.d(TAG, "Notification shown: " + title + " (msgId=" + msgId + ")");

        } catch (Exception e) {
            Log.e(TAG, "Message handling failed: " + e.getMessage(), e);
        }
    }

    private void sendAck(WebSocket ws, String msgId) {
        try {
            JSONObject ack = new JSONObject();
            ack.put("action", "ack");
            ack.put("msgId", msgId);
            ws.send(ack.toString());
        } catch (Exception e) {
            Log.e(TAG, "ACK failed", e);
        }
    }

    private void startHeartbeat(WebSocket ws) {
        stopHeartbeat();
        heartbeatFuture = scheduler.scheduleAtFixedRate(() -> {
            try {
                if (ws != null) {
                    JSONObject ping = new JSONObject();
                    ping.put("type", "ping");
                    ws.send(ping.toString());
                }
            } catch (Exception e) {
                Log.e(TAG, "Heartbeat failed", e);
            }
        }, HEARTBEAT_INTERVAL_SEC, HEARTBEAT_INTERVAL_SEC, TimeUnit.SECONDS);
    }

    private void stopHeartbeat() {
        if (heartbeatFuture != null) {
            heartbeatFuture.cancel(false);
            heartbeatFuture = null;
        }
    }

    private void cancelReconnect() {
        if (reconnectFuture != null) {
            reconnectFuture.cancel(false);
            reconnectFuture = null;
        }
    }

    private void onDisconnected(int closeCode) {
        stopHeartbeat();
        webSocket = null;
        registered = false;

        if (!isRunning || isStopped) {
            Log.d(TAG, "Not running, skip reconnect");
            return;
        }

        // Close code 1000 = normal closure (server closed because another connection
        // registered with same account, i.e., app came to foreground). Don't reconnect.
        if (closeCode == 1000) {
            Log.d(TAG, "Server closed with 1000 (likely app foreground), not reconnecting");
            isRunning = false;
            setConnectionState(ConnectionState.DISCONNECTED, "已断开（返回前台）");
            return;
        }

        setConnectionState(ConnectionState.CONNECTING,
                "连接断开，" + ((reconnectAttempts + 1) * 3) + "秒后重试...");

        int delay;
        if (reconnectAttempts == 0) {
            delay = 3000;
        } else if (reconnectAttempts < 5) {
            delay = 1000 * (1 << reconnectAttempts);
        } else if (reconnectAttempts < 10) {
            delay = 30000;
        } else {
            delay = 60000;
        }

        Log.d(TAG, "Reconnecting in " + delay + "ms (attempt " + (reconnectAttempts + 1) + ")");

        reconnectFuture = scheduler.schedule(() -> {
            if (isRunning && !isStopped) {
                reconnectAttempts++;
                connect();
            }
        }, delay, TimeUnit.MILLISECONDS);
    }

    private void loadDedupIds() {
        try {
            SharedPreferences sp = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
            Set<String> shown = sp.getStringSet(SHOWN_IDS_KEY, new HashSet<>());
            shownMsgIds.addAll(shown);
            Set<String> deleted = sp.getStringSet(DELETED_IDS_KEY, new HashSet<>());
            deletedMsgIds.addAll(deleted);
            Log.d(TAG, "Loaded dedup: shown=" + shownMsgIds.size() + " deleted=" + deletedMsgIds.size());
        } catch (Exception e) {
            Log.e(TAG, "Load dedup failed", e);
        }
    }

    private void addShownId(String msgId) {
        if (shownMsgIds.size() >= MAX_DEDUP_IDS) {
            Iterator<String> it = shownMsgIds.iterator();
            if (it.hasNext()) { it.next(); it.remove(); }
        }
        shownMsgIds.add(msgId);
        saveDedupIds();
    }

    private void addDeletedId(String msgId) {
        if (deletedMsgIds.size() >= MAX_DEDUP_IDS) {
            Iterator<String> it = deletedMsgIds.iterator();
            if (it.hasNext()) { it.next(); it.remove(); }
        }
        deletedMsgIds.add(msgId);
        saveDedupIds();
    }

    private void saveDedupIds() {
        try {
            SharedPreferences sp = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
            sp.edit()
                    .putStringSet(SHOWN_IDS_KEY, new HashSet<>(shownMsgIds))
                    .putStringSet(DELETED_IDS_KEY, new HashSet<>(deletedMsgIds))
                    .apply();
            Log.d(TAG, "Saved dedup: shown=" + shownMsgIds.size() + " deleted=" + deletedMsgIds.size());
        } catch (Exception e) {
            Log.e(TAG, "Save dedup failed", e);
        }
    }

    /**
     * Returns all shown message IDs and clears the internal set.
     * Called when app comes to foreground so Dart side can merge them.
     */
    public Set<String> getAndClearShownIds() {
        Set<String> ids = new HashSet<>(shownMsgIds);
        // Don't clear shownMsgIds - keep for native-side dedup across reconnections
        // Dart side will merge these into its own dedup set
        return ids;
    }

    // 🔥 更新连接状态并触发回调
    private void setConnectionState(ConnectionState state, String detail) {
        ConnectionState prev = this.connectionState;
        this.connectionState = state;
        this.connectionStateDetail = detail;
        Log.d(TAG, "🔗 连接状态: " + state + " (" + detail + ")");
        if (stateChangeListener != null) {
            try {
                stateChangeListener.onStateChanged(state, detail);
            } catch (Exception e) {
                Log.e(TAG, "状态回调失败", e);
            }
        }
    }
}
