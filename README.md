<div align="center">

<img src="docs/icon.png" width="120" height="120" alt="Silas RP" />

<h3>一个手机上的 AI 角色扮演客户端</h3>

<p>导入角色卡 · 世界书 · 状态栏 · 多模型 · 默认不联网 · 无账号</p>

<p><em>做自己想用的那个客户端</em></p>

<p>
  <img alt="License" src="https://img.shields.io/badge/License-GPLv3-blue.svg" />
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-3.22+-02569B?logo=flutter&amp;logoColor=white" />
  <img alt="Android" src="https://img.shields.io/badge/Android-6.0+-3DDC84?logo=android&amp;logoColor=white" />
  <img alt="Network" src="https://img.shields.io/badge/Network-Only%20your%20API-orange" />
  <img alt="Account" src="https://img.shields.io/badge/Account-None-brightgreen" />
</p>

<p>
  <a href="README.en.md">English</a> ·
  <a href="#-功能">功能</a> ·
  <a href="#-安装">安装</a> ·
  <a href="#-构建">构建</a> ·
  <a href="#-许可">许可</a> ·
  <a href="#-支持作者">支持作者</a> ·
  <a href="#-免责声明">免责声明</a>
</p>

</div>

---

Silas RP 是个**个人项目**：没有团队、没有 KPI，也不商业化。做它的原因很具体——想在手机上玩角色扮演，但一直没找到一个顺手的客户端，于是自己写一个。

> ⚠️ 本软件按 **AS IS** 提供，**无任何担保**。内置成人向开关（默认关闭），请自行判断是否适合使用。

## ✨ 功能

|  |  |
|:--|:--|
| 🎴 **角色卡** | 导入酒馆 V1/V2/V3（PNG 或 JSON）基础模式填几个字段就能开聊，高级模式直接改人设原文。导出 PNG 时把角色数据写进图里，别的客户端也读得出来。 |
| 📖 **世界书** | 常驻与关键词两种触发。关键词是子串匹配，扫描范围含最近 8 条对话、本轮输入**和状态栏的值**——把 `P3`、`X2` 这类状态编号当关键词也能命中。注入前清洗 YAML 残留，由状态编号触发的条目单独成段放到提示词末尾。 |
| 🧩 **状态栏** | 支持 JSON 与「键：值」两种格式，记忆体随剧情推进。面板常驻不会莫名消失，点消息区任意位置就能收起。 |
| 🎛 **生成参数** | 叙述视角、温度、上下文上限、单次回复上限，一张卡一套。卡库长按封面即可调整，参数随卡一起导出。 |
| 🔀 **模型切换** | 可配多个 OpenAI 兼容 API（含本地模型）。会话里点输入框左边的按钮就能换，气泡上标着每条回复用的是哪个模型，换没换一眼看得出。 |
| 🔍 **思考过程** | 支持 `reasoning_content` 的模型（DeepSeek-R1、GLM-Z1、Qwen3 等）能看到这一轮它怎么想的。思考单独存一列，**不进上下文**，不会污染后面的对话。 |
| 🧾 **单价与用量** | 按模型名设单价（支持 `deepseek-*` 这类通配符），统计页把 token 换算成金额。 |
| 🏷 **会话管理** | 多会话并存，可打标签（比如「保留」）、全选反选、批量删除；单条会话能导出 Markdown 或 JSON。 |
| 🔤 **字体** | 全局霞鹜文楷，子集到 CJK 基本区，生僻字和人名不会掉回系统字体。 |

> 🔒 **默认不联网。** 唯一的联网行为就是你自己配置的模型 API，除此之外没有任何请求。没有账号、没有遥测——角色卡、聊天记录、思考过程全部只留在本机。

## 📥 安装

去 [**Releases**](https://github.com/lampe9703/silas-rp/releases/latest) 下载最新的 `Silas-RP-*-arm64-v8a.apk`（近几年的手机基本都是 arm64，体积更小），直接安装；不确定就下 `universal` 通用包。

首次打开后在「设置 → API 配置」里填入你的接口地址、密钥和模型名，就可以开始聊了。

## 🛠 构建

需要 Flutter SDK ≥ 3.22（Dart ≥ 3.4）、Android SDK、JDK 17。

```bash
git clone https://github.com/lampe9703/silas-rp.git
cd silas-rp
flutter pub get

# 通用包
flutter build apk --release

# 只出 arm64（体积更小）
flutter build apk --release --target-platform android-arm64
```

产物在 `build/app/outputs/flutter-apk/`。

技术栈：Flutter + Riverpod（状态）· SQLite（本地库，含版本迁移）· Dio（流式请求）· file_picker（导入导出）。

## 📜 许可

[GNU General Public License v3.0](LICENSE) · Copyright (C) 2025 lampe9703

简言之：自由使用、修改、分发皆可；一旦把修改版对外分发，整个衍生作品必须同样以 GPL-3.0 开源。

## 📄 第三方资源

内置字体为 [霞鹜文楷 LXGW WenKai](https://github.com/lxgw/LxgwWenKai) v1.530 Regular 的子集，作者 [LXGW](https://github.com/lxgw)，基于 SIL Open Font License 1.1 授权。

- 保留 CJK 基本区（U+4E00–U+9FFF，20992 字）与常用符号区间字形，24.7 MB → 12.2 MB
- 霞鹜文楷声明了保留字体名（Reserved Font Name），子集化属于修改版本，按 OFL 要求已将内部字体名改为 `Silas WenKai`，字形未作任何改动
- 许可全文见 [assets/licenses/OFL-LXGWWenKai.txt](assets/licenses/OFL-LXGWWenKai.txt)

## 🚫 免责声明

本项目仅供学习和个人使用。用户自行配置 API Key 并承担相应费用与责任。

软件不内置任何角色卡、世界书或剧情内容；导入的卡片版权归原作者，请勿用于商业用途。内置的成人向开关仅作为写作尺度选项，使用者需自行确保所在地区与使用场景合规。

---

## 💛 支持作者

如果这个软件在某个无聊的夜晚给了你一点点慰藉：

- ⭐ 在 [GitHub](https://github.com/lampe9703/silas-rp) 点一颗星
- ☕ 在 [爱发电](https://afdian.com/a/lampe9703) 请我喝杯咖啡
- 📣 在你的朋友圈子里帮我宣传一下——把它转给那个同样在找手机端角色扮演客户端的人

三条里最管用的其实是最后一条：一个人因此找到它，比一杯咖啡值钱得多。

---

Made with ⌨️ by lampe
