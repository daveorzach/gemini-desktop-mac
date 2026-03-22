# Contributing to Gemini Desktop

Thanks for your interest in contributing. This is a small personal project — contributions are welcome but please keep the scope focused.

## Building Locally

```bash
git clone https://github.com/daveorzach/gemini-desktop-mac.git
cd gemini-desktop-mac
open GeminiDesktop.xcodeproj
```

Dependencies (KeyboardShortcuts, Yams, SwiftSoup) are resolved automatically by Xcode via Swift Package Manager.

**Requirements:** macOS 15.0+, Xcode 16+

## What's Welcome

- Bug fixes
- Stability and performance improvements
- Settings and UI polish
- Accessibility improvements

## What's Out of Scope

- Features that require scraping or modifying Gemini's web content
- App Store distribution (incompatible with the CC BY-NC 4.0 license)
- Breaking changes to the prompt schema or selector file formats without discussion first

## Process

1. Open an issue first for anything beyond a small bug fix — saves wasted effort if the direction isn't a fit
2. Fork, branch, and open a PR against `main`
3. Keep PRs focused — one feature or fix per PR
4. Test on macOS 15+ before submitting

## License

By contributing, you agree that your contributions will be licensed under the same [CC BY-NC 4.0](LICENSE) license that covers this project.
