<div align="center">

<img src="docs/icon.png" width="120" height="120" alt="Silas RP" />

<h3>An AI roleplay client for your phone</h3>

<p>Character cards · World book · Status bar · Multi-model · Offline by default · No account</p>

<p><em>Built for the way I actually play</em></p>

<p>
  <img alt="License" src="https://img.shields.io/badge/License-GPLv3-blue.svg" />
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-3.22+-02569B?logo=flutter&amp;logoColor=white" />
  <img alt="Android" src="https://img.shields.io/badge/Android-6.0+-3DDC84?logo=android&amp;logoColor=white" />
  <img alt="Network" src="https://img.shields.io/badge/Network-Only%20your%20API-orange" />
  <img alt="Account" src="https://img.shields.io/badge/Account-None-brightgreen" />
</p>

<p>
  <a href="README.md">中文</a> ·
  <a href="#features">Features</a> ·
  <a href="#install">Install</a> ·
  <a href="#build">Build</a> ·
  <a href="#license">License</a> ·
  <a href="#support">Support</a> ·
  <a href="#disclaimer">Disclaimer</a>
</p>

</div>

---

Silas RP is a **personal project**: no team, no KPIs, not commercial. The reason is concrete — I wanted to play character cards on my phone and never found a client that felt right, so I wrote one.

> ⚠️ Provided **AS IS**, with **no warranty**. There is an adult-content switch (off by default); decide for yourself whether that suits your use.

## Features

|  |  |
|:--|:--|
| 🎴 **Character cards** | Imports Tavern V1/V2/V3 (PNG or JSON), and cards exported by Huanmeng. Basic mode gets you chatting after a few fields; advanced mode edits the raw persona text. Exported PNGs embed the card data, so other clients can read them back. |
| 📖 **World book** | Constant and keyword entries. Keywords are substring matches, scanned across the last 8 messages, your input **and the status bar values** — so state IDs like `P3` or `X2` work as keywords. YAML leftovers are stripped before injection, and entries driven by state IDs are moved to the end of the prompt so they outrank generic style rules. |
| 🧩 **Status bar** | JSON or `key: value` blocks; the memory string (`P3-C1-S1-T3-X2`) advances with the story. The panel stays put instead of silently vanishing, and a tap anywhere in the message area collapses it. |
| 🎛 **Per-card generation settings** | Perspective, temperature, context limit and reply cap are stored per card. Long-press a cover in the library to adjust them; they travel with the card when exported. |
| 🔀 **Switch models mid-chat** | Configure several OpenAI-compatible endpoints (local models included). Tap the button left of the input box to switch; every reply shows which model produced it. |
| 🔍 **View reasoning** | For models returning `reasoning_content` (DeepSeek-R1, GLM-Z1, Qwen3 …) you can read what it was thinking. Stored in its own column — **never fed back into context**. |
| 🧾 **Pricing & usage** | Set a price per model name (wildcards like `deepseek-*` work); the stats page turns tokens into money. |
| 🏷 **Session management** | Multiple sessions per card, with tags (e.g. "keep"), select-all / invert, and batch delete. Any session exports to Markdown or JSON. |
| 🔤 **Typography** | LXGW WenKai throughout, subset to the CJK basic block so rare characters don't fall back to the system font. |

> 🔒 **Offline by default.** The only network traffic is the model API you configure yourself — nothing else. No account, no telemetry: cards, chats and reasoning stay on your device.

## Install

Grab the latest `Silas-RP-*-arm64-v8a.apk` from [**Releases**](https://github.com/lampe9703/silas-rp/releases/latest) — that covers most phones from the last few years and is the smaller download; pick `universal` if you are unsure.

On first launch, open **Settings → API Config** and fill in your endpoint, key and model name.

## Build

Requires Flutter SDK ≥ 3.22 (Dart ≥ 3.4), Android SDK and JDK 17.

```bash
git clone https://github.com/lampe9703/silas-rp.git
cd silas-rp
flutter pub get

# universal
flutter build apk --release

# arm64 only (smaller)
flutter build apk --release --target-platform android-arm64
```

Output lands in `build/app/outputs/flutter-apk/`.

Stack: Flutter + Riverpod (state) · SQLite (local database with schema migrations) · Dio (streaming requests) · file_picker (import/export).

## License

[GNU General Public License v3.0](LICENSE) · Copyright (C) 2025 lampe9703

In short: use, modify and redistribute freely; if you distribute a modified version, the whole derivative must be released under GPL-3.0 as well.

## Third-party

The bundled font is a subset of [LXGW WenKai](https://github.com/lxgw/LxgwWenKai) v1.530 Regular by [LXGW](https://github.com/lxgw), licensed under the SIL Open Font License 1.1.

- Keeps the CJK basic block (U+4E00–U+9FFF, 20,992 glyphs) plus common symbol ranges; 24.7 MB → 12.2 MB
- LXGW WenKai declares a Reserved Font Name. Subsetting counts as a modified version, so as required by the OFL the internal font name was changed to `Silas WenKai`; glyphs are untouched
- Full license text: [assets/licenses/OFL-LXGWWenKai.txt](assets/licenses/OFL-LXGWWenKai.txt)

## Disclaimer

For learning and personal use only. You supply your own API key and bear the resulting cost and responsibility.

The app ships no character cards, world books or story content; imported cards belong to their authors — do not use them commercially. The adult-content switch is a writing-scope option only; make sure your region and use case allow it.

---

## 💛 Support

If this app made a dull night slightly better:

- ⭐ star it on [GitHub](https://github.com/lampe9703/silas-rp)
- ☕ buy me a coffee on [Afdian](https://afdian.com/a/lampe9703)
- 📣 Please help me promote this within your circle of friends—forward it to those who are also looking for a mobile role-playing client.

The last one helps the most: one more person finding it is worth more than a coffee.

---

Made with ⌨️ by lampe
