# Silas RP — AI 角色扮演

一个基于 Flutter 的安卓端 AI 角色扮演应用。支持自定义角色卡片、多轮对话、流式回复，以及从 Silas 卡库（.sai 格式）导入角色。

## 功能

- **角色扮演**：创建或导入角色卡片，与 AI 进行沉浸式对话
- **自定义角色**：支持编辑角色名称、人设、对话风格、开场白等
- **卡库导入**：从 Silas 卡库下载 .sai 格式角色卡片并一键导入
- **多模型支持**：可配置 OpenAI 兼容的 API（包括本地模型）
- **数据管理**：导入 / 导出全部数据，支持在不同设备间迁移
- **开源免费**：代码完全开源，无广告、无付费墙

## 截图

> TODO: 添加应用截图

## 入驻平台

本项目已入驻 [爱发电](https://afdian.com/a/lampe9703)。

## 下载

- [GitHub Releases](https://github.com/lampe9703/silas-rp/releases) — 最新 APK
- [爱发电](https://afdian.com/a/lampe9703) — 如果这个项目对你有帮助，欢迎请我喝杯咖啡

## 构建

### 环境要求

- Flutter SDK ≥ 3.16
- Android SDK
- JDK 17

### 构建步骤

```bash
# 克隆仓库
git clone https://github.com/lampe9703/silas-rp.git
cd silas-rp

# 安装依赖
flutter pub get

# 构建 Release APK
flutter build apk --release

# 构建分架构 APK（体积更小）
flutter build apk --release --split-per-abi
```

构建产物位于 `build/app/outputs/flutter-apk/`。

## 技术栈

- **Flutter** — 跨平台 UI 框架
- **Riverpod** — 状态管理
- **Hive** — 本地数据持久化
- **Dio** — 网络请求
- **url_launcher** — 外部链接跳转

## 项目结构

```
lib/
├── core/              # 核心工具、常量、主题
├── data/              # 数据模型、本地存储
├── features/
│   ├── card_library/  # 卡库浏览与下载
│   ├── chat/          # 对话界面与逻辑
│   ├── editor/        # 角色编辑器
│   ├── settings/      # 设置页、关于、数据管理
│   └── character_list/# 角色列表
└── main.dart
```

## 许可证

[GNU General Public License v3.0](LICENSE)

Copyright (C) 2025 lampe9703

## 支持作者

如果这个 App 陪你度过了一些无聊的夜晚：

- ⭐ 在 GitHub 上给个 Star
- ☕ [爱发电](https://afdian.com/a/lampe9703) 请我喝杯咖啡

## 免责声明

本项目仅供学习和个人使用。用户自行配置 API Key 并承担相应责任。
