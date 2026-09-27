# iPadzdxt - Flutter 考试应用

## 项目结构

```
lib/
├── main.dart              # 应用入口和路由配置
├── config.dart            # API 配置
├── login.dart             # 登录页面
├── exam.dart              # 考试列表页面
├── doexam.dart            # 答题页面
├── examdetail.dart        # 考试详情页面
├── aichat.dart            # AI 助手聊天页面
├── help.dart              # 帮助页面
├── config/                # 配置目录
│   └── theme_config.dart  # 主题配置
├── constants/             # 常量定义
│   └── app_constants.dart
├── models/                # 数据模型
│   ├── user_model.dart
│   ├── exam_model.dart
│   └── question_model.dart
├── routes/                # 路由配置
│   └── app_routes.dart
├── services/              # 服务层
│   ├── api_service.dart
│   └── auth_service.dart
├── utils/                 # 工具类
│   ├── helpers.dart       # 通用辅助函数
│   ├── toast.dart         # Toast 提示
│   └── math_renderer.dart # 数学公式渲染
├── screens/               # 新架构屏幕组件
│   ├── login_screen.dart
│   ├── exam_screen.dart
│   ├── exam_detail_screen.dart
│   ├── aichat_screen.dart
│   └── help_screen.dart
└── widgets/               # 可复用组件
```

## 开发环境要求

- Flutter SDK >= 3.11.5
- Dart SDK >= 3.11.5

## 安装依赖

```bash
flutter pub get
```

## 运行应用

```bash
flutter run
```

## 构建应用

```bash
flutter build apk      # Android
flutter build ios      # iOS
```
