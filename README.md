# ReadBox

> 面向个人 macOS 用户的 **Local-First AI 剪藏阅读与知识沉淀工作台**（纯原生 Swift + SwiftUI 开发）。

ReadBox 参考了 Cubox Mac 端的极简阅读美学，去掉了商业化云端依赖与账号体系，专注于个人阅读与知识内化闭环：**微信公众号/网页剪藏 → 沉浸阅读与多色高亮 → 侧边栏 AI 问答（支持 DeepSeek 等自定义模型） → 单栏所见即所得 Markdown 笔记 → 知识库沉淀与 iCloud Drive / 本地明文存储**。

---

## 核心特性

- **微信公众号 & 网页剪藏**
  - 针对微信公众号（`mp.weixin.qq.com`）专项提取正文，并自动将防盗链图片下载至本地 `assets/` 目录，永久离线可读、不怕原文删除或裂图。
  - 支持通用网页正文提纯、离线快照与离屏 `WKWebView` 动态页兜底。
  - 内置剪贴板链接自动监测横幅、macOS 菜单栏常驻快捷收藏助手（`MenuBarExtra`）、`⌘N` 批量添加以及 `readbox://save?url=...` URL Scheme。
- **沉浸式阅读与 5 色划词高亮**
  - 顶部「文章 / 原网页 / 快照」三态分段切换。
  - 自定义阅读主题（跟随系统 / 纯净白 / 护眼纸 / 暗夜黑）、字体、字号、行距与页宽。
  - 选中文本弹出 5 色高亮悬浮工具条，支持一键高亮、引用到侧边笔记、复制或发送给 AI 解读。
- **类 Chrome 侧边栏 AI 助手（BYOK 自定义服务商）**
  - 支持单篇快读解读（摘要、核心观点、关键问题与标签建议）、阅读伴随多轮流式问答、全库检索问答。
  - **AI 知识沉淀引擎**：选中多篇文章或收藏夹，让 AI 跨文章阅读归纳，生成带引用出处的结构化 Markdown 知识文档并自动归档。
  - 内置 **DeepSeek**（原生支持 `deepseek-reasoner` 思考过程折叠展示）、OpenAI、Anthropic Claude、Ollama 本地模型及任意 OpenAI 兼容中转服务；API Key 加密保存在 macOS Keychain。
- **单栏所见即所得（WYSIWYG）Markdown 编辑器**
  - Typora 风格实时行内渲染，拒绝左右分栏源码/预览割裂感。
  - 支持 `#` 标题、`**加粗**`、`*斜体*`、`> 引用`、`- [ ]` 可勾选待办、代码块与 `/` 斜杠快捷菜单，底层保存 100% 标准 Markdown。
- **Local-First 明文存储与 iCloud Drive 同步**
  - 所有知识沉淀文档与收藏均以透明 `.md`（含 YAML Frontmatter）存放在磁盘，默认支持托管至 **iCloud Drive** 自动同步，也可随时切换或导出至任意本地文件夹。
  - 内置系统 `SQLite3` FTS5 实现毫秒级中文/英文全文检索（`⌘K` Spotlight 浮窗）。
- **内置原生 Stdio MCP Server（接入外部 AI Agent）**
  - 无需 Node/Python，通过 `/Applications/ReadBox.app/Contents/MacOS/ReadBox --mcp --token <密钥>` 即可把 ReadBox 接入 Claude Code、Cursor、Antigravity 等外部 Agent。
  - 支持外部 Agent 进行 URL/Markdown 剪藏、全文检索、读取正文、写回「AI 快读解读」、增删改划词高亮批注、写入/追加侧边笔记、管理收藏夹/标签与知识沉淀文档；写入后实时通知运行中的 ReadBox 界面自动刷新。
  - 在 **偏好设置 (`⌘,`) → MCP 集成** 中可随时一键复制客户端配置 JSON 或刷新访问密钥。

---

## 仓库目录结构

```text
ReadBox/
├── Package.swift                  # Swift Package 配置（macOS 14+，零第三方包依赖）
├── Sources/ReadBox/
│   ├── ReadBoxApp.swift           # 应用入口、菜单栏助手、全局快捷键与 URL Scheme
│   ├── Models/                    # Clip / Folder / Highlight / KnowledgeDoc / AIProvider 模型
│   ├── Services/                  # VaultManager、SQLite FTS5、微信/网页解析器、流式 AI 引擎、Keychain
│   ├── State/                     # AppState 全局状态管理
│   ├── Views/                     # 仿 Cubox 三栏界面、阅读器、全局搜索、AI 侧边栏、知识库与设置
│   └── Resources/                 # 离线 reader.html 与 wysiwyg_editor.html 内核
├── Tests/ReadBoxTests/            # Frontmatter、Vault/FTS5 搜索、解析与全局搜索单元测试
├── scripts/
│   ├── build-app.sh               # 一键打包为原生 ReadBox.app（支持 UNIVERSAL=1 通用二进制）
│   └── package-dmg.sh             # 一键生成可分发的 macOS 压缩 DMG 与 SHA-256 校验文件
└── .github/workflows/             # GitHub Actions CI 测试与 Tag 自动打包发布 DMG Release
```

---

## 快速开始

### 方式一：直接下载 DMG 安装（推荐）

前往项目的 [GitHub Releases](https://github.com/CivilLover/ReadBox/releases) 页面：

1. 下载最新版本的 `ReadBox-v*-macOS-universal.dmg`（同时支持 Apple Silicon 与 Intel Mac，需 macOS 14.0+；在 macOS 26+ 自动启用原生 Liquid Glass 液态玻璃界面）。
2. 双击打开 DMG，将 **ReadBox.app** 拖入 **Applications（应用程序）** 文件夹即可。

> **首次打开说明**
> 本开源项目当前采用本地 Ad-hoc 签名，尚未加入 Apple 付费开发者公证。首次打开若提示“无法验证开发者”或“已损坏”，在终端运行：
> ```bash
> xattr -cr /Applications/ReadBox.app
> ```
> 或在 **系统设置 → 隐私与安全性** 中点击 **“仍要打开”** 即可正常使用。

### 方式二：从源码编译运行

#### 环境要求
- macOS 14.0 (Sonoma) 及以上
- Xcode / Swift 6 工具链（启用 macOS 26 原生 Liquid Glass 需 Xcode 26+）

#### 编译、测试与打包

```bash
# 1. 运行单元测试
swift test

# 2. 打包为原生 macOS 应用（build/ReadBox.app，并默认安装至 /Applications）
./scripts/build-app.sh

# 如不想覆盖 /Applications，可加 NO_INSTALL=1
NO_INSTALL=1 ./scripts/build-app.sh

# 3. 如需本地制作通用二进制（arm64 + x86_64）安装包 DMG（输出至 dist/）
UNIVERSAL=1 NO_INSTALL=1 VERSION=0.1.0 ./scripts/build-app.sh
VERSION=0.1.0 ./scripts/package-dmg.sh

# 4. 启动 ReadBox
open /Applications/ReadBox.app
```

> **开发约定（Agent / 本地开发）**：每次代码开发完成并通过 `swift test` 后，应**自动执行 `./scripts/build-app.sh`** 重新打包并安装更新至 `/Applications/ReadBox.app`，避免手动重复打包。

也可以直接用 Xcode 打开 `Package.swift` 进行调试与运行。

### 自动发布 Release（GitHub Actions）

仓库已配置 `.github/workflows/release.yml`：
- 推送形如 `v0.1.0` 的版本标签（`git tag v0.1.0 && git push origin v0.1.0`），或在 GitHub **Actions → Release macOS DMG** 手动触发；
- 流水线将自动在 `macos-26` Runner 上运行全部单元测试、编译 Apple Silicon + Intel 通用二进制、生成压缩 DMG 与 SHA-256 校验和，并自动发布到 GitHub Releases。

### 首次配置建议
1. 按 `⌘,` 打开设置 → **AI 服务商**，选择 **DeepSeek**（或其他自定义服务商）填入 API Key 并测试连通性。
2. 在 **存储与 iCloud** 中确认知识库路径（默认 iCloud Drive，可随时改为任意本地文件夹）。

---

## Roadmap / TODO

- [ ] **Obsidian 深度集成**（已预留 `VaultSyncAdapter` 协议，当前 `.md` + YAML Frontmatter 目录已天然兼容 Obsidian）
- [ ] **Notion 数据库同步**
- [ ] 极简浏览器剪藏扩展（Chrome / Safari 一键推送页面到本地 ReadBox）

---

## License

[MIT](LICENSE) © 2026 CivilLover
