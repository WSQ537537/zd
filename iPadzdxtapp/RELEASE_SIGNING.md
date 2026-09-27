# iPadzdxtapp Android Release 签名配置说明

## 已创建文件

| 文件 | 位置 | 用途 |
|------|------|------|
| `android/release.keystore` | `android/` 目录 | Release 签名密钥库（RSA 2048，有效期 10000 天） |
| `android/key.properties` | `android/` 目录 | 签名配置（alias / 密码 / storeFile） |
| `android/app/build.gradle.kts` | 已修改 | 加载 key.properties 并配置 release signingConfig |

## 签名参数

- **别名**: `ipadzdxt`
- **密钥算法**: RSA 2048
- **签名算法**: SHA384withRSA
- **有效期**: 10000 天（约 27 年）
- **证书 DN**: `CN=ZhiDaXingTu, OU=Dev, O=ZDXT, L=Beijing, ST=Beijing, C=CN`
- **密码**: `iPad2025ZDXT`（store 与 key 同密码，见 `key.properties`）

## 如何构建

```powershell
cd d:\zdxt\iPadzdxtapp
flutter build apk --release --target-platform android-arm64
# 输出: build\app\outputs\flutter-apk\app-release.apk
# 已复制为: ipad-zdxt-release.apk
```

## 注意事项

1. **备份密钥库**：`android/release.keystore` 是应用签名的唯一凭证，丢失后无法更新已发布版本。建议：
   - 将 `android/release.keystore` + `android/key.properties` 放入密码管理或安全存储
   - 不要提交到 git（已在 `.gitignore` 中，确认 `android/key.properties` 已被忽略）
2. **密码管理**：生产环境建议改用环境变量或 CI/Secrets 管理密码，避免明文写入 `key.properties`
3. **上架前**：可用 `apksigner verify --print-certs ipad-zdxt-release.apk` 验证签名
