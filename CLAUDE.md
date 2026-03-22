# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Gemini Desktop for macOS is an unofficial macOS desktop wrapper for Google Gemini (`https://gemini.google.com/app`). It's a SwiftUI + AppKit app using WKWebView to host the Gemini web interface with native macOS enhancements.

**Requirements:** macOS 15.0 (Sequoia)+, Xcode 16+

## Build & Run

Open `GeminiDesktop.xcodeproj` in Xcode and run with Cmd+R. There is no command-line build script — this is an Xcode-native project.

Dependencies are managed via Swift Package Manager and resolved automatically by Xcode:
- **KeyboardShortcuts** v2.4.0 — global keyboard shortcut recording in Settings
- **Yams** — YAML parsing for prompt frontmatter metadata
- **SwiftSoup** — HTML-to-Markdown conversion for artifact capture

## Architecture

**Pattern: MVVM + Coordinator**

- **`AppCoordinator`** — Central hub using `@Observable`. Manages both the main window and floating chat bar, controls WebView lifecycle, and coordinates multi-screen window positioning.
- **`WebViewModel`** — Observable wrapper around `WKWebView`. Tracks nav state, zoom level (persisted to UserDefaults), and home-page detection.
- **`ChatBarPanel`** — Custom `NSPanel` subclass for the floating chat overlay. Handles click-outside dismissal via `NSEvent.addGlobalMonitorForEvents`, JavaScript evaluation to focus input/trigger new chats, auto-expansion when a conversation starts (via polling), and size persistence.

**Key constraint:** A WKWebView can only exist in one view hierarchy at a time. `AppCoordinator` manages moving the single shared WebView between the main window and the chat bar panel.

**Prompt Library** (`Prompts/`): `PromptScanner` walks a user-chosen directory and parses `.md` files (with optional YAML frontmatter via Yams) into `PromptFile` models. `PromptLibrary` holds the scanned results as an `@Observable` singleton. `PromptDirectoryWatcher` uses `DispatchSource` to watch for file changes and triggers rescans. `PromptsMenuButton` renders the toolbar menu. Injection mode (copy vs. inject) is user-configurable in Settings.

**Artifact Capture** (`Artifacts/`, `Utils/`): `GeminiSelectors` loads JS selector expressions from a bundled JSON file (or a user override at `~/Library/Application Support/GeminiDesktop/gemini-selectors.json`) to extract model, request, and conversation URL from the Gemini page. `UserScripts` injects these selectors and a DOM capture script. `HTMLToMarkdown` (SwiftSoup) converts the captured HTML response to Markdown. `ArtifactLogger` writes a persistent log of capture operations. `ArtifactCaptureButton` drives the capture flow from the toolbar.

**JavaScript injection** (`WebKit/UserScripts.swift`) handles three cases:
1. IME fix — resolves double-Enter issue for Chinese/Japanese/Korean input by tracking composition state and auto-clicking send after composition ends.
2. Metadata extraction — uses `GeminiSelectors` JS expressions to read model name, request text, and conversation URL from the DOM at capture time.
3. Console log bridge (DEBUG builds only) — routes `console.log` to Swift.

## Code Organization

```
App/            # @main app + AppDelegate
ChatBar/        # Floating panel (NSPanel subclass + SwiftUI view)
Coordinators/   # AppCoordinator (central state & navigation)
WebKit/         # GeminiWebView (NSViewRepresentable), WebViewModel, UserScripts, GeminiSelectors
Views/          # MainWindowView, SettingsView, MenuBarView, ArtifactCaptureButton, PromptsMenuButton
Prompts/        # PromptFile, PromptMetadata, PromptScanner, PromptLibrary, PromptDirectoryWatcher
Artifacts/      # ArtifactMetadata
Utils/          # UserDefaultsKeys, ArtifactLogger, HTMLToMarkdown, BookmarkStore, NSScreen+Extensions
Resources/      # Assets, entitlements, Info.plist, gemini-selectors.json
```

## Settings & State Persistence

All user preferences are stored in `UserDefaults` via keys defined in `Utils/UserDefaultsKeys.swift`. This includes panel dimensions, zoom level, theme, custom toolbar colors, window visibility options, prompt/artifact directory bookmarks, injection mode, user agent, chat bar position, always-on-top, and the minimize-to-prompt toggle.

Directory access for the Prompts and Artifacts folders uses security-scoped bookmarks (`BookmarkStore`) to survive app restarts without requiring the user to re-grant access.

## Toolbar Theming

The app uses Google's official Gemini colors for the toolbar: `#34A853` (light) and `#81C995` (dark), applied via `NSAppearance` observation in `GeminiDesktopApp.swift`. Custom colors are also user-configurable in Settings.

## GeminiSelectors

`GeminiSelectors` is a `@MainActor` singleton that loads JS selector expressions from JSON. It supports a user override file at `~/Library/Application Support/GeminiDesktop/gemini-selectors.json` (takes priority over the bundled default). Call `GeminiSelectors.reload()` after the user edits or resets the selector file — SettingsView does this automatically in `.onDisappear`.
