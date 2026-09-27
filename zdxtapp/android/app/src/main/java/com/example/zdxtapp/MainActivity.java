package com.example.zdxtapp;

import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Intent;
import android.database.Cursor;
import android.media.MediaScannerConnection;
import android.net.Uri;
import android.os.Bundle;
import android.os.Build;
import android.os.Environment;
import android.provider.MediaStore;
import android.provider.Settings;
import android.util.Log;
import android.content.pm.ResolveInfo;
import androidx.core.content.FileProvider;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;
import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.List;

public class MainActivity extends FlutterActivity {
    private static final String TAG = "ZdxtApp";
    private static final String CHANNEL = "com.zdxt.app/file_manager";
    private static final String NOTIFICATION_CHANNEL = "com.zdxt.app/notifications";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        // 🔥 原生层优先初始化通知渠道：确保在 Flutter 引擎启动前渠道已存在，
        // 防止部分 OEM 设备因插件初始化失败而导致渠道配置缺失
        NotificationUtils.initChannels(this);
    }

    @Override
    public void configureFlutterEngine(FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);

        // 🔥 原生通知通道：App 后台/息屏时，Dart isolate 可能被挂起，
        // 通过此通道由 Native 层直接调用 NotificationManager 显示通知
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), NOTIFICATION_CHANNEL)
            .setMethodCallHandler((call, result) -> {
                if (call.method.equals("showNative")) {
                    String title = call.argument("title");
                    String body = call.argument("body");
                    String msgId = call.argument("msgId");
                    if (title != null && body != null && msgId != null) {
                        result.success(NotificationUtils.showNotification(this, title, body, msgId));
                    } else {
                        result.error("INVALID_ARGS", "title/body/msgId 不能为空", null);
                    }
                } else if (call.method.equals("isChannelConfigured")) {
                    result.success(NotificationUtils.isChannelConfigured(this));
                } else {
                    result.notImplemented();
                }
            });

        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL)
            .setMethodCallHandler((call, result) -> {
                if (call.method.equals("openFileLocation")) {
                    String filePath = call.argument("filePath");
                    if (filePath != null && !filePath.isEmpty()) {
                        boolean success = openFileLocation(filePath);
                        result.success(success);
                    } else {
                        result.error("INVALID_PATH", "文件路径不能为空", null);
                    }
                } else if (call.method.equals("saveToMediaStore")) {
                    String filePath = call.argument("filePath");
                    String displayName = call.argument("displayName");
                    String mimeType = call.argument("mimeType");
                    Log.d(TAG, "saveToMediaStore called: path=" + filePath + ", name=" + displayName + ", mime=" + mimeType);
                    if (filePath != null && !filePath.isEmpty()) {
                        try {
                            String savedPath = saveToMediaStore(filePath, displayName, mimeType);
                            Log.d(TAG, "saveToMediaStore success: " + savedPath);
                            result.success(savedPath);
                        } catch (Exception e) {
                            Log.e(TAG, "saveToMediaStore failed: " + e.getMessage(), e);
                            result.error("SAVE_FAILED", e.getMessage(), null);
                        }
                    } else {
                        result.error("INVALID_PATH", "文件路径不能为空", null);
                    }
                } else if (call.method.equals("checkManageExternalStorage")) {
                    boolean granted = checkManageExternalStorage();
                    result.success(granted);
                } else if (call.method.equals("requestManageExternalStorage")) {
                    requestManageExternalStorage();
                    result.success(true);
                } else {
                    result.notImplemented();
                }
            });
    }

    /**
     * 检查是否有 MANAGE_EXTERNAL_STORAGE 权限（Android 11+）
     */
    private boolean checkManageExternalStorage() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            return Environment.isExternalStorageManager();
        }
        return true;
    }

    /**
     * 请求 MANAGE_EXTERNAL_STORAGE 权限（Android 11+）
     * 触发系统权限弹窗，用户授权后可直接管理 Download 目录
     */
    private void requestManageExternalStorage() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // 直接跳"所有文件访问权限"设置页（系统会弹窗让用户授权）
            openAllFilesAccessSettings();
        }
    }

    /**
     * 打开文件所在目录（核心逻辑）
     *
     * 策略（按 Android 版本 + 权限状态分流）：
     *
     * Android 11+ (API 30+)：
     *   - 未持有 MANAGE_EXTERNAL_STORAGE：弹出系统权限弹窗（授权后即可管理 Download 目录）
     *   - 已持有：构造外部存储文档 URI（content://com.android.externalstorage.documents/tree/primary%3A<路径>）
     *     直接 ACTION_VIEW + resource/folder，系统路由到文件管理器（避免"打开方式"对话框）
     *
     * Android 9~10 (API 28-29)：
     *   FileProvider + 检测有无文件管理器；有则 ACTION_VIEW，无则跳"所有文件访问权限"设置页
     *
     * Android 8 及以下：
     *   直接 ACTION_VIEW + file:// URI
     */
    private boolean openFileLocation(String filePath) {
        File file = new File(filePath);
        if (!file.exists()) {
            Log.w(TAG, "openFileLocation: 文件不存在 " + filePath);
            return false;
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            if (Environment.isExternalStorageManager()) {
                // 已授权：直接 ACTION_VIEW 目录（系统路由，不依赖 queryIntentActivities 检测）
                Log.d(TAG, "openFileLocation: 已授权，直接浏览目录");
                if (openFolderViaView(file, false)) {
                    return true;
                }
                // 浏览失败：跳"所有文件访问权限"设置页兜底
                Log.d(TAG, "openFileLocation: 浏览目录失败，跳设置页兜底");
                return openAllFilesAccessSettings();
            } else {
                // 未授权：弹系统权限弹窗
                Log.d(TAG, "openFileLocation: 未授权，触发权限弹窗");
                requestManageExternalStorage();
                return true;
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Android 10：先检测有无文件管理器（避免"打开方式"弹窗），无则跳设置页
            if (openFolderViaView(file, true)) {
                return true;
            }
            return openAllFilesAccessSettings();
        }

        // Android 9 及以下：直接 ACTION_VIEW 浏览目录
        return openFolderViaView(file, false);
    }

    /**
     * 跳转到"所有文件访问权限"设置页（MANAGE_ALL_FILES_ACCESS_PERMISSION）
     * 用户可在此页管理/查看 Download 目录下的文件
     */
    private boolean openAllFilesAccessSettings() {
        try {
            Intent intent = new Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION);
            intent.setData(Uri.parse("package:" + getPackageName()));
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(intent);
            return true;
        } catch (Exception e) {
            Log.e(TAG, "openAllFilesAccessSettings: 全文件访问权限页不可用 " + e.getMessage());
            return false;
        }
    }

    /**
     * ACTION_VIEW 浏览目录
     *
     * 策略按 Android 版本分流：
     * - Android 11+ (API 30+) 且已授权 MANAGE_EXTERNAL_STORAGE：
     *   使用 ExternalStorageProvider 文档 URI（content://com.android.externalstorage.documents/tree/primary%3A<相对路径>），
     *   直接 ACTION_VIEW + resource/folder，系统路由到文件管理器（不会弹"打开方式"）。
     * - Android 9~10 (API 28-29)：FileProvider + queryIntentActivities 检测文件管理器。
     * - Android 8 及以下：file:// URI 直接 ACTION_VIEW。
     *
     * @param checkManager 仅用于 Android 10 及以下（检测无文件管理器时返回 false 走设置页兜底）。
     *                     Android 11+ 已授权路径忽略此参数（直接发文档 URI）。
     */
    private boolean openFolderViaView(File file, boolean checkManager) {
        File directory = file.getParentFile();
        if (directory == null || !directory.exists()) {
            Log.w(TAG, "openFolderViaView: 目录不存在 " + (directory == null ? "null" : directory.getAbsolutePath()));
            return false;
        }

        // 🔥 Android 11+ 且已授权 MANAGE_EXTERNAL_STORAGE：使用外部存储文档 URI 直接浏览目录
        // 该 URI 由系统 ExternalStorageProvider 处理，不会弹"打开方式"对话框
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && Environment.isExternalStorageManager()) {
            Uri docUri = buildExternalStorageDocumentUri(directory);
            if (docUri != null) {
                try {
                    Intent intent = new Intent(Intent.ACTION_VIEW);
                    intent.setDataAndType(docUri, "resource/folder");
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                    intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
                    startActivity(intent);
                    Log.d(TAG, "openFolderViaView: 已用外部存储文档 URI 跳转文件管理器 " + directory.getAbsolutePath() + " -> " + docUri);
                    return true;
                } catch (Exception e) {
                    Log.e(TAG, "openFolderViaView: 外部存储文档 URI 跳转失败 " + e.getMessage());
                    return false;
                }
            }
            // 文档 URI 构造失败（如目录不在公共外存下）：兜底走设置页
            Log.w(TAG, "openFolderViaView: 无法构造外部存储文档 URI，跳设置页兜底 " + directory.getAbsolutePath());
            return openAllFilesAccessSettings();
        }

        // Android 10 及以下：保留旧的 FileProvider 路径
        if (checkManager) {
            try {
                Uri testUri;
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    String authority = getPackageName() + ".fileprovider";
                    testUri = FileProvider.getUriForFile(this, authority, directory);
                } else {
                    testUri = Uri.fromFile(directory);
                }
                Intent testIntent = new Intent(Intent.ACTION_VIEW);
                testIntent.setDataAndType(testUri, "resource/folder");
                List<ResolveInfo> matches =
                        getPackageManager().queryIntentActivities(testIntent, 0);
                if (matches == null || matches.isEmpty()) {
                    Log.d(TAG, "openFolderViaView: 无文件管理器可浏览目录");
                    return false;
                }
            } catch (Exception e) {
                Log.w(TAG, "openFolderViaView: 检测文件管理器失败 " + e.getMessage());
                return false;
            }
        }

        // 直接 ACTION_VIEW 浏览目录（FileProvider 或 file://）
        try {
            Uri uri;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                String authority = getPackageName() + ".fileprovider";
                uri = FileProvider.getUriForFile(this, authority, directory);
            } else {
                uri = Uri.fromFile(directory);
            }
            Intent intent = new Intent(Intent.ACTION_VIEW);
            intent.setDataAndType(uri, "resource/folder");
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            startActivity(intent);
            Log.d(TAG, "openFolderViaView: 已跳转文件管理器浏览目录 " + directory.getAbsolutePath());
            return true;
        } catch (Exception e) {
            Log.e(TAG, "openFolderViaView: 跳转失败 " + e.getMessage());
            return false;
        }
    }

    /**
     * 为 Android 11+ 已授权 MANAGE_EXTERNAL_STORAGE 的情况构造 ExternalStorageProvider 文档 URI。
     *
     * 文档 ID 形如 "<storage>:<相对路径>"，例如 "primary:Download" 对应 /storage/emulated/0/Download，
     * 最终 URI 形如 content://com.android.externalstorage.documents/tree/primary%3ADownload。
     *
     * 返回值：成功返回文档 URI；失败返回 null（调用方走设置页兜底）。
     */
    @SuppressWarnings("NewApi") // 调用方已在 SDK_INT >= R 分支中保护
    private Uri buildExternalStorageDocumentUri(File directory) {
        try {
            // 仅对公共外存下的目录构造文档 URI；其它位置返回 null 走兜底
            String externalRoot = Environment.getExternalStorageDirectory().getAbsolutePath();
            File extDir = new File(externalRoot);
            if (!directory.getAbsolutePath().startsWith(extDir.getAbsolutePath() + File.separator)
                    && !directory.getAbsolutePath().equals(extDir.getAbsolutePath())) {
                Log.d(TAG, "buildExternalStorageDocumentUri: 目录不在公共外存下 " + directory.getAbsolutePath());
                return null;
            }

            // 计算相对于外存根的路径
            String relative = directory.getAbsolutePath().substring(extDir.getAbsolutePath().length());
            if (relative.startsWith("/")) relative = relative.substring(1);
            // 外存根自身 => 文档 ID 为 "primary:"，tree 形如 content://.../tree/primary:
            if (relative.isEmpty()) relative = "";

            // 文档 ID 前缀 "primary:"，冒号在 URI 中需转义为 %3A
            String docId = "primary:" + relative;
            String encodedDocId = Uri.encode(docId);
            Uri tree = Uri.parse("content://com.android.externalstorage.documents/tree/" + encodedDocId);
            Log.d(TAG, "buildExternalStorageDocumentUri: " + directory.getAbsolutePath() + " -> " + tree);
            return tree;
        } catch (Exception e) {
            Log.w(TAG, "buildExternalStorageDocumentUri: 构造失败 " + e.getMessage());
            return null;
        }
    }

    private String saveToMediaStore(String filePath, String displayName, String mimeType) throws Exception {
        File sourceFile = new File(filePath);
        if (!sourceFile.exists()) {
            throw new Exception("源文件不存在: " + filePath);
        }
        Log.d(TAG, "源文件大小: " + sourceFile.length() + " bytes");
        ContentResolver resolver = getContentResolver();
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return saveViaMediaStore(resolver, sourceFile, displayName, mimeType);
        } else {
            return saveLegacy(resolver, sourceFile, displayName, mimeType);
        }
    }

    private String saveViaMediaStore(ContentResolver resolver, File sourceFile,
                                      String displayName, String mimeType) throws Exception {
        Log.d(TAG, "使用 MediaStore API (Android 10+), SDK=" + Build.VERSION.SDK_INT);
        Uri externalUri;
        String relativePath;
        if (mimeType.startsWith("image/")) {
            externalUri = MediaStore.Images.Media.EXTERNAL_CONTENT_URI;
            relativePath = Environment.DIRECTORY_PICTURES;
        } else if (mimeType.startsWith("video/")) {
            externalUri = MediaStore.Video.Media.EXTERNAL_CONTENT_URI;
            relativePath = Environment.DIRECTORY_MOVIES;
        } else if (mimeType.startsWith("audio/")) {
            externalUri = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI;
            relativePath = Environment.DIRECTORY_MUSIC;
        } else {
            externalUri = MediaStore.Downloads.EXTERNAL_CONTENT_URI;
            relativePath = Environment.DIRECTORY_DOWNLOADS;
        }
        Log.d(TAG, "目标 URI: " + externalUri + ", 相对路径: " + relativePath);

        String selection = MediaStore.MediaColumns.DISPLAY_NAME + " = ?";
        String[] selectionArgs = new String[]{displayName};
        Cursor cursor = null;
        try {
            cursor = resolver.query(externalUri, new String[]{MediaStore.MediaColumns._ID},
                    selection, selectionArgs, null);
            if (cursor != null && cursor.moveToFirst()) {
                long existingId = cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID));
                Uri existingUri = Uri.withAppendedPath(externalUri, String.valueOf(existingId));
                int deleted = resolver.delete(existingUri, null, null);
                Log.d(TAG, "已删除同名旧文件, deleted=" + deleted);
            }
        } finally {
            if (cursor != null) cursor.close();
        }

        Uri insertUri = null;
        try {
            ContentValues values = new ContentValues();
            values.put(MediaStore.MediaColumns.DISPLAY_NAME, displayName);
            values.put(MediaStore.MediaColumns.MIME_TYPE, mimeType);
            values.put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath);
            values.put(MediaStore.MediaColumns.IS_PENDING, 1);

            insertUri = resolver.insert(externalUri, values);
            if (insertUri == null) {
                throw new Exception("MediaStore insert 返回 null，可能是权限不足或存储空间不足");
            }
            Log.d(TAG, "MediaStore insert URI: " + insertUri);

            long totalBytes = 0;
            InputStream is = null;
            OutputStream os = null;
            try {
                is = new FileInputStream(sourceFile);
                os = resolver.openOutputStream(insertUri);
                if (os == null) {
                    resolver.delete(insertUri, null, null);
                    throw new Exception("无法打开输出流");
                }
                byte[] buffer = new byte[8192];
                int bytesRead;
                while ((bytesRead = is.read(buffer)) != -1) {
                    os.write(buffer, 0, bytesRead);
                    totalBytes += bytesRead;
                }
                os.flush();
            } finally {
                if (is != null) { try { is.close(); } catch (Exception ignored) {} }
                if (os != null) { try { os.close(); } catch (Exception ignored) {} }
            }
            Log.d(TAG, "写入完成: " + totalBytes + " bytes");

            ContentValues updateValues = new ContentValues();
            updateValues.put(MediaStore.MediaColumns.IS_PENDING, 0);
            int updated = resolver.update(insertUri, updateValues, null, null);
            Log.d(TAG, "文件已标记为可用, updated=" + updated);

            if (totalBytes != sourceFile.length()) {
                Log.w(TAG, "警告: 写入字节数(" + totalBytes + ")不等于源文件大小(" + sourceFile.length() + ")");
            } else {
                Log.d(TAG, "数据完整性验证通过: " + totalBytes + " bytes");
            }

            final boolean[] scanResult = {false};
            MediaScannerConnection.scanFile(this, new String[]{insertUri.toString()},
                    new String[]{mimeType},
                    (path, uri) -> {
                        scanResult[0] = true;
                        Log.d(TAG, "MediaScanner 扫描完成: " + path + " -> " + uri);
                    });

            int waitCount = 0;
            while (!scanResult[0] && waitCount < 30) {
                try {
                    Thread.sleep(100);
                    waitCount++;
                } catch (InterruptedException e) {
                    break;
                }
            }
            Log.d(TAG, "MediaScanner 等待完成: " + scanResult[0]);
        } catch (Exception e) {
            Log.e(TAG, "保存过程出错，清理 IS_PENDING 标记: " + e.getMessage());
            if (insertUri != null) {
                try {
                    ContentValues cleanupValues = new ContentValues();
                    cleanupValues.put(MediaStore.MediaColumns.IS_PENDING, 0);
                    resolver.update(insertUri, cleanupValues, null, null);
                    resolver.delete(insertUri, null, null);
                    Log.d(TAG, "已清理失败的 MediaStore 记录");
                } catch (Exception cleanupEx) {
                    Log.w(TAG, "清理失败记录时出错: " + cleanupEx.getMessage());
                }
            }
            throw e;
        }

        String realPath = queryRealPath(resolver, insertUri);
        if (realPath != null) return realPath;
        return Environment.getExternalStorageDirectory().getAbsolutePath() + "/" + relativePath + "/" + displayName;
    }

    private String queryRealPath(ContentResolver resolver, Uri uri) {
        Cursor cursor = null;
        try {
            cursor = resolver.query(uri, new String[]{MediaStore.MediaColumns.DATA}, null, null, null);
            if (cursor != null && cursor.moveToFirst()) {
                int columnIndex = cursor.getColumnIndex(MediaStore.MediaColumns.DATA);
                if (columnIndex >= 0) return cursor.getString(columnIndex);
            }
        } catch (Exception e) {
            Log.w(TAG, "查询真实路径失败: " + e.getMessage());
        } finally {
            if (cursor != null) cursor.close();
        }
        return null;
    }

    private String saveLegacy(ContentResolver resolver, File sourceFile,
                               String displayName, String mimeType) throws Exception {
        Log.d(TAG, "使用 Legacy 方式 (Android 9-)");
        String relativePath;
        if (mimeType.startsWith("image/")) {
            relativePath = Environment.DIRECTORY_PICTURES;
        } else if (mimeType.startsWith("video/")) {
            relativePath = Environment.DIRECTORY_MOVIES;
        } else if (mimeType.startsWith("audio/")) {
            relativePath = Environment.DIRECTORY_MUSIC;
        } else {
            relativePath = Environment.DIRECTORY_DOWNLOADS;
        }
        File publicDir = new File(Environment.getExternalStorageDirectory(), relativePath);
        if (!publicDir.exists()) {
            boolean created = publicDir.mkdirs();
            Log.d(TAG, "创建目录: " + publicDir.getAbsolutePath() + ", success=" + created);
        }
        File destFile = new File(publicDir, displayName);
        InputStream is = null;
        OutputStream os = null;
        try {
            is = new FileInputStream(sourceFile);
            os = new java.io.FileOutputStream(destFile);
            byte[] buffer = new byte[8192];
            int bytesRead;
            while ((bytesRead = is.read(buffer)) != -1) {
                os.write(buffer, 0, bytesRead);
            }
            os.flush();
        } finally {
            if (is != null) { try { is.close(); } catch (Exception ignored) {} }
            if (os != null) { try { os.close(); } catch (Exception ignored) {} }
        }
        Log.d(TAG, "文件已复制到: " + destFile.getAbsolutePath());
        MediaScannerConnection.scanFile(this,
                new String[]{destFile.getAbsolutePath()},
                new String[]{mimeType},
                (path, uri) -> Log.d(TAG, "MediaScanner 扫描完成: " + path + " -> " + uri));
        return destFile.getAbsolutePath();
    }
}
