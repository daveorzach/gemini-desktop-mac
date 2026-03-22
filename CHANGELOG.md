# Changelog

All notable changes to this project will be documented in this file.

## [0.4.0] - 2026-03-22

### Added
- **Artifact Capture** — save the last Gemini response as a Markdown file via toolbar button; includes filename input sheet with metadata preview (model, request, URL, timestamp)
- **Prompt Library** — load `.md` prompt files from a folder and insert them into Gemini via toolbar menu; supports Copy and Inject modes, nested folders, and YAML frontmatter metadata
- **Settings: Prompts & Artifacts** — choose separate folders for prompts and saved artifacts
- **Settings: Custom Metadata Selectors** — override bundled JS selectors used for artifact capture; Reset to Defaults button restores bundled version with timestamped backup
- **Settings: Minimize to Prompt** — optional toolbar button (disabled by default) that collapses the main window to the floating chat bar
- **Settings: User Agent** — choose Safari, Chrome, or a custom user agent string
- **Settings: Chat Bar Position** — fixed or floating panel position; Always on Top toggle
- **Debug Mode** — hidden debug menu and capture tools (Settings > Advanced)
- **File Upload & Download** — native macOS file dialogs for attachments; completed downloads open in Finder

### Fixed
- Green window flash on first launch
- File picker unresponsive in popup mode
- IME (Chinese/Japanese/Korean) double-send on Enter
- Toolbar color not reapplying after full-screen transition
