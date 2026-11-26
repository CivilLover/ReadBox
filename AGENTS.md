# AGENTS.md — ReadBox

ReadBox is a **Local-First AI web clipper, reader, and knowledge workbench for macOS**, built with pure native Swift + SwiftUI + AppKit + WebKit + SQLite3.

Use this file as the primary architecture map before scanning source files.

---

## 1. Tech Stack & Constraints

- **Build system**: Swift Package Manager (`Package.swift`, `swift-tools-version: 6.0`, `.swiftLanguageMode(.v5)`).
- **Platform**: macOS 14.0+ baseline (`platforms: [.macOS(.v14)]`), with native macOS 26+ **Liquid Glass** UI guarded by `#available(macOS 26.0, *)`.
- **Dependencies**: **Zero third-party Swift packages**. Only system frameworks/libraries: `SwiftUI`, `AppKit`, `WebKit`, `Security`, and `sqlite3` (with FTS5).
- **Localization**: Default localization is `zh-Hans`; all user-facing UI strings, prompts, and toasts are in Simplified Chinese.
- **Bundle ID / URL Scheme**: `com.readbox.macos` / `readbox://save?url=...`

---

## 2. Build, Test & Packaging Commands

```bash
# Run unit tests (Frontmatter, Vault + SQLite FTS5, HTML->MD, AI JSON, Zhihu parser, Cookie domain matching)
swift test

# Build release binary + package build/ReadBox.app AND install to /Applications/ReadBox.app
./scripts/build-app.sh

# Package build/ReadBox.app without overwriting /Applications/ReadBox.app
NO_INSTALL=1 ./scripts/build-app.sh

# Build universal (arm64 + x86_64) app bundle and package compressed macOS DMG into dist/
UNIVERSAL=1 NO_INSTALL=1 VERSION=0.1.0 ./scripts/build-app.sh
VERSION=0.1.0 ./scripts/package-dmg.sh

# Launch packaged app
open build/ReadBox.app
```

**Packaging & CI/CD notes (`scripts/build-app.sh`, `scripts/package-dmg.sh`, `.github/workflows/`)**:
- Copies `ReadBox_ReadBox.bundle` into `Contents/Resources/` so `Bundle.module` resolves `reader.html` and `wysiwyg_editor.html`.
- Uses `vtool -set-build-version macos 14.0 "$SDK_VER"` to stamp the host SDK version into Mach-O `LC_BUILD_VERSION` (required for native macOS 26+ Liquid Glass chrome).
- Ad-hoc signs (`codesign --force --deep --sign -`, or `SIGN_IDENTITY` if supplied) so Gatekeeper and macOS Keychain access work cleanly on Apple Silicon.
- `.github/workflows/ci.yml` runs `swift test` and verifies release bundling on `macos-26` for pushes/PRs to `main`.
- `.github/workflows/release.yml` runs on `v*` tags or manual dispatch, builds a universal (`arm64` + `x86_64`) `.app`, packages `dist/ReadBox-v<ver>-macOS-universal.dmg` + `.sha256`, and publishes a GitHub Release automatically.

---

## 3. Repository Layout & Module Map

```text
Sources/ReadBox/
├── ReadBoxApp.swift                   # @main entry, WindowGroup, MenuBarExtra, Settings scene, shortcuts (⌘N/⌘⇧N/⌘K/⌘F/⌘L/⌘⇧G/⌘R), onOpenURL
├── State/
│   └── AppState.swift                 # Single @MainActor ObservableObject store: navigation, CRUD (clips/folders/tags/highlights/docs), clipping, AI streaming, toasts
├── Models/
│   ├── Models.swift                   # ClipItem, ClipSourceType, HighlightItem, HighlightColor, AIInsight, FolderItem, TagItem, KnowledgeDoc
│   └── AIAndSettingsModels.swift      # AIProviderProfile (presets: DeepSeek/OpenAI/Anthropic/Ollama), AIAPIFormat, ChatMessage, ReaderPreferences, SynthesisPromptTemplate, AppSettings
├── Services/
│   ├── VaultManager.swift             # Local-First disk I/O (iCloud Drive / local folder), settings persistence, export, welcome seeding, FTS5 indexing triggers
│   ├── SearchDatabase.swift           # Thread-safe SQLite3 + FTS5 (`fts_docs`, `unicode61`) rebuildable full-text search index
│   ├── FrontmatterParser.swift        # YAML Frontmatter serializer/parser for `article.md` & `knowledge/*.md` (Obsidian-compatible)
│   ├── WebClipperService.swift        # WeChat (`mp.weixin.qq.com`), Zhihu (`zhihu.com`), & generic HTML clipper, image localization, OffscreenWebViewFetcher, HTMLToMarkdown
│   ├── SiteCookieManager.swift        # @MainActor unified cookie manager backed by `WKWebsiteDataStore.default()` (shared across login sheet, Reader WebView, clipper)
│   ├── AIService.swift                # Native URLSession SSE streaming client (OpenAI-compatible + DeepSeek `reasoning_content` + Anthropic native) & prompt builders
│   ├── KeychainService.swift          # Stores AI provider API keys in macOS Keychain (`com.readbox.macos.apikeys`)
│   ├── ClipboardMonitor.swift         # Polls NSPasteboard for URLs when enabled
│   ├── GlobalHotKeyManager.swift      # Carbon HIToolbox system-wide global hotkey listener (no Accessibility prompt required) & shortcut formatter
│   └── SyncAdapter.swift              # Reserved `VaultSyncAdapter` protocol stubs for future Obsidian / Notion integration
├── Views/
│   ├── MainWorkspaceView.swift        # Root NavigationSplitView (Sidebar + Detail/Reader + Global AI Drawer + QuickSearch/Toast overlays) & MenuBarQuickSaveView
│   ├── FloatingQuickClipPanel.swift   # Non-activating Liquid Glass floating NSPanel capsule for instant URL paste/drop-to-Inbox clipping & pin-on-desktop mode
│   ├── SidebarView.swift              # Cubox-style left sidebar (Inbox, All, Unread, Starred, KnowledgeBase, Annotations, Archived, Untagged, nested Folders, Tags)
│   ├── LibraryContentView.swift       # Clip list/card grid (`ClipCardView`, `ClipListRowView`), multi-select batch bar, clipboard banner, sort/filter toolbar
│   ├── ReaderWorkspaceView.swift      # Reader view: 「文章 / 原网页 / 快照」 tabs, live WebView re-extract, right inspector (AI / Note / Highlights), typography popover
│   ├── AISidebarView.swift            # Streaming AI chat UI (article-scoped or global), DeepSeek thinking collapse, one-click insight & save-to-knowledge
│   ├── KnowledgeBaseView.swift        # KnowledgeBaseView (doc list + WYSIWYG editor + export) & AnnotationsView (cross-article highlights view)
│   ├── GlobalSearchOverlay.swift      # Cubox-style Global Search & inline AI RAG Search overlay (⌘K / ⌘F)
│   ├── ModalsAndOverlays.swift        # QuickAddSheet (⌘N), KnowledgeSynthesisSheet (⌘⇧G multi-clip AI distillation)
│   ├── SettingsView.swift             # Preferences (⌘,): AI providers/keys, Vault/iCloud path, Reader prefs, Site login/cookies, Synthesis templates
│   ├── SiteLoginView.swift            # Built-in WKWebView login browser sheet + manual Cookie header import (`SiteLoginBrowserSheet`)
│   └── Components/
│       ├── LiquidGlassStyle.swift     # `readBoxGlassSurface`, `readBoxGlassButton`, `readBoxSeamlessToolbar`, `ReadBoxGlassGroup`, `LiquidGlassCanvasBackground`
│       ├── ReaderWebView.swift        # `ReaderWebView` (hosts `reader.html`) & `SimpleWebView` (live webpage / snapshot + DOM outerHTML extraction trigger)
│       └── WYSIWYGEditorView.swift    # `WYSIWYGEditorView` (hosts `wysiwyg_editor.html`)
└── Resources/
    ├── reader.html                    # Self-contained offline reader canvas (themes, 5-color highlight toolbar, quote-to-note, ask-AI)
    └── wysiwyg_editor.html            # Self-contained Typora-style single-pane WYSIWYG Markdown editor (slash menu, live inline formatting, checklists)
```

---

## 4. Storage & Data Architecture (Local-First)

- **Default Vault path**: `~/Library/Mobile Documents/com~apple~CloudDocs/ReadBox` (iCloud Drive if available), otherwise `~/Documents/ReadBox`. User-switchable at runtime via `AppState.switchVaultDirectory(to:)`.
- **Vault directory layout**:
  ```text
  <Vault>/
  ├── clips/<yyyy-MM>/<slug>-<shortId>/
  │   ├── meta.json        # ClipItem (including highlights & aiInsight)
  │   ├── article.html     # Cleaned offline reader HTML (references relative `assets/...`)
  │   ├── article.md       # YAML Frontmatter + Markdown body
  │   ├── snapshot.html    # Full offline HTML snapshot
  │   ├── note.md          # Per-clip personal Markdown note
  │   └── assets/          # Localized images (defeats WeChat/web hotlink protection)
  ├── knowledge/
  │   └── <slug>.md        # KnowledgeDoc files (YAML Frontmatter + Markdown)
  ├── folders.json         # Hierarchical FolderItem list (`parentId`)
  ├── tags.json            # Standalone TagItem list (synced with clip tags)
  └── .readbox/
      └── index.sqlite     # Rebuildable SQLite3 FTS5 cache (keys: `clip:<id>`, `highlight:<id>`, `knowledge:<id>`)
  ```
- **App settings**: `~/Library/Application Support/ReadBox/settings.json` (not inside the vault, so vault path & local preferences stay machine-safe).
- **Secrets**: AI API keys are stored **only** in macOS Keychain via `KeychainService.shared` (service: `com.readbox.macos.apikeys`, account: `provider.id`). Never write API keys to `settings.json` or the vault.

---

## 5. Key Cross-Layer Contracts & Workflows

### State Management
- `AppState` (`@MainActor`) is injected via `.environmentObject(appState)` across the main window, `MenuBarExtra`, and `Settings`.
- All mutations update `@Published` arrays in memory, persist immediately via `VaultManager`, and update `SearchDatabase`.
- Cross-component actions use one-shot bridge properties on `AppState`: `pendingScrollToHighlightId`, `pendingNoteAppendMarkdown`, `pendingAIQuoteQuestion`.

### Web Clipping & Anti-Bot Fallback
1. `WebClipperService.clipURL(_:assetsDirectory:)` tries a fast `URLSession` fetch (with Safari UA and cookies from `SiteCookieManager.shared.cookieHeader(for:)`).
2. On HTTP 401/403/429/503 or JS-rendered pages (e.g., Zhihu / SPA), it falls back to `OffscreenWebViewFetcher` (uses `WKWebsiteDataStore.default()`).
3. Specialized parsers run for `mp.weixin.qq.com` and `zhihu.com`; others use generic readability extraction. Images are downloaded into `<clipDir>/assets/`.
4. If the site still returns a login/verification gate, `ClippedPageResult.needsManualWebExtract = true` saves a placeholder bookmark. The user can switch to **「原网页」** (`SimpleWebView` sharing `WKWebsiteDataStore.default()`), log in if needed, and click **「提取当前页正文」** → `AppState.reextractClip(_:fromRenderedHTML:)`.

### Swift ↔ WebKit JS Bridges
- **`ReaderWebView` ↔ `Resources/reader.html`**:
  - Loaded with `baseURL = clipDirectoryURL` so relative `assets/...` images resolve offline.
  - Swift → JS: `window.applyPreferences(json)`, `window.loadArticle(json)`, `window.renderHighlights(json)`, `window.scrollToHighlight(id)`.
  - JS → Swift (`window.webkit.messageHandlers.reader.postMessage`): `{ type: "addHighlight" | "removeHighlight" | "quoteToNote" | "copyText" | "askAI", ... }`.
- **`WYSIWYGEditorView` ↔ `Resources/wysiwyg_editor.html`**:
  - Swift → JS: `window.setMarkdown(str)`, `window.appendMarkdown(str)`.
  - JS → Swift (`window.webkit.messageHandlers.editor.postMessage`): `{ type: "change", markdown: "..." }`.

### AI Streaming (`AIService`)
- `streamChat(...) -> AsyncThrowingStream<AIStreamChunk, Error>` emits both `contentDelta` and `reasoningDelta` (for `deepseek-reasoner` / thinking models).
- Omits `temperature` automatically for reasoning models (`reasoner`, `o1*`, `o3*`).
- Global AI chat uses `sessionKey = "global"` and performs local retrieval from `SearchDatabase` / clips to build context; article chat uses `sessionKey = clip.id`.

---

## 6. Development Conventions & Guardrails

- **Backward-compatible `Codable`**: When adding persisted fields to `AppSettings`, `FolderItem`, `ClipItem`, etc., provide defaults in custom `init(from decoder:)` using `decodeIfPresent` so existing user JSON files never fail to decode.
- **Liquid Glass styling**: Use the wrappers in `LiquidGlassStyle.swift` (`readBoxGlassSurface`, `readBoxGlassButton`, `ReadBoxGlassGroup`, `readBoxSeamlessToolbar`) instead of calling macOS 26 APIs directly, preserving macOS 14–15 fallbacks.
- **Rebuildable search cache**: Treat `.readbox/index.sqlite` strictly as a derived cache; never store authoritative user data only in SQLite.
- **No external SPM deps**: Keep `Package.swift` dependency-free unless explicitly requested by the user.
- **Verification**: Always run `swift test` after code changes; run `NO_INSTALL=1 ./scripts/build-app.sh` (or `./scripts/build-app.sh` when asked to install) when verifying app packaging, resources, or UI builds.
- **Keep this doc fresh**: If you add/remove top-level files, change vault storage formats, or alter JS bridge contracts, update `AGENTS.md` in the same task.
