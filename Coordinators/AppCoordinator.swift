//
//  AppCoordinator.swift
//  GeminiDesktop
//
//  Created by alexcding on 2025-12-13.
//

import SwiftUI
import AppKit
import WebKit
import Combine

extension Notification.Name {
    static let openMainWindow = Notification.Name("openMainWindow")
}

@Observable
class AppCoordinator {
    private var chatBar: ChatBarPanel?
    let webView: WKWebView
    var canGoBack: Bool = false
    var canGoForward: Bool = false
    private var backObserver: NSKeyValueObservation?
    private var forwardObserver: NSKeyValueObservation?
    private var urlObserver: NSKeyValueObservation?
    private var isAtHome: Bool = true

    var openWindowAction: ((String) -> Void)?

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        // Add user scripts
        for script in UserScripts.createAllScripts() {
            configuration.userContentController.addUserScript(script)
        }

        let wv = WKWebView(frame: .zero, configuration: configuration)
        wv.allowsBackForwardNavigationGestures = true
        wv.allowsLinkPreview = true

        // Set custom User-Agent to appear as Safari
        wv.customUserAgent = Constants.userAgent

        // Apply saved page zoom
        let savedZoom = UserDefaults.standard.double(forKey: UserDefaultsKeys.pageZoom.rawValue)
        wv.pageZoom = savedZoom > 0 ? savedZoom : Constants.defaultPageZoom

        wv.load(URLRequest(url: Constants.geminiURL))

        self.webView = wv

        backObserver = wv.observe(\.canGoBack, options: [.new, .initial]) { [weak self] webView, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.canGoBack = !self.isAtHome && webView.canGoBack
            }
        }

        forwardObserver = wv.observe(\.canGoForward, options: [.new, .initial]) { [weak self] webView, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.canGoForward = webView.canGoForward
            }
        }

        urlObserver = wv.observe(\.url, options: .new) { [weak self] webView, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard let currentURL = webView.url else { return }

                // Check if we're at the Gemini home/app page
                let isGeminiApp = currentURL.host == Constants.geminiHost && currentURL.path.hasPrefix(Constants.geminiAppPath)

                if isGeminiApp {
                    self.isAtHome = true
                    self.canGoBack = false
                } else {
                    self.isAtHome = false
                    self.canGoBack = webView.canGoBack
                }
            }
        }

        // Observe notifications for window opening
        NotificationCenter.default.addObserver(forName: .openMainWindow, object: nil, queue: .main) { [weak self] _ in
            self?.openMainWindow()
        }
    }

    func reloadHomePage() {
        isAtHome = true
        canGoBack = false
        webView.load(URLRequest(url: Constants.geminiURL))
    }

    func goBack() {
        isAtHome = false
        webView.goBack()
    }

    func reload() {
        webView.reload()
    }

    func goForward() {
        webView.goForward()
    }

    func goHome() {
        reloadHomePage()
    }

    func zoomIn() {
        let newZoom = min((webView.pageZoom * 100 + 1).rounded() / 100, 1.4)
        webView.pageZoom = newZoom
        UserDefaults.standard.set(newZoom, forKey: UserDefaultsKeys.pageZoom.rawValue)
    }

    func zoomOut() {
        let newZoom = max((webView.pageZoom * 100 - 1).rounded() / 100, 0.6)
        webView.pageZoom = newZoom
        UserDefaults.standard.set(newZoom, forKey: UserDefaultsKeys.pageZoom.rawValue)
    }

    func resetZoom() {
        webView.pageZoom = Constants.defaultPageZoom
        UserDefaults.standard.set(Constants.defaultPageZoom, forKey: UserDefaultsKeys.pageZoom.rawValue)
    }

    func showChatBar() {
        // Hide main window when showing chat bar
        closeMainWindow()

        if let bar = chatBar {
            // Reuse existing chat bar
            bar.orderFront(nil)
            bar.makeKeyAndOrderFront(nil)
            bar.checkAndAdjustSize()
            return
        }

        let contentView = ChatBarView(
            webView: webView,
            onExpandToMain: { [weak self] in
                self?.expandToMainWindow()
            }
        )
        let hostingView = NSHostingView(rootView: contentView)
        let bar = ChatBarPanel(contentView: hostingView)

        // Position at bottom center, above the dock
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let barSize = bar.frame.size
            let x = screenRect.origin.x + (screenRect.width - barSize.width) / 2
            let y = screenRect.origin.y + Constants.dockOffset
            bar.setFrameOrigin(NSPoint(x: x, y: y))
        }

        bar.orderFront(nil)
        bar.makeKeyAndOrderFront(nil)
        chatBar = bar
    }

    func hideChatBar() {
        chatBar?.orderOut(nil)
    }

    func closeMainWindow() {
        // Find and hide the main window
        for window in NSApp.windows {
            if window.identifier?.rawValue == Constants.mainWindowIdentifier || window.title == Constants.mainWindowTitle {
                if !(window is NSPanel) {
                    window.orderOut(nil)
                }
            }
        }
    }

    func toggleChatBar() {
        if let bar = chatBar, bar.isVisible {
            hideChatBar()
        } else {
            showChatBar()
        }
    }

    func expandToMainWindow() {
        hideChatBar()
        openMainWindow()
    }

    func openMainWindow() {
        // Hide chat bar first - WebView can only be in one view hierarchy
        hideChatBar()

        let hideDockIcon = UserDefaults.standard.bool(forKey: UserDefaultsKeys.hideDockIcon.rawValue)
        if !hideDockIcon {
            NSApp.setActivationPolicy(.regular)
        }

        // Find existing main window (may be hidden/suppressed)
        let mainWindow = NSApp.windows.first(where: {
            $0.identifier?.rawValue == Constants.mainWindowIdentifier || $0.title == Constants.mainWindowTitle
        })

        if let window = mainWindow {
            // Window exists - show it (works for suppressed windows too)
            window.makeKeyAndOrderFront(nil)
        } else if let openWindowAction = openWindowAction {
            // Window doesn't exist yet - use SwiftUI openWindow to create it
            openWindowAction("main")
        }

        NSApp.activate(ignoringOtherApps: true)
    }
}


extension AppCoordinator {

    struct Constants {
        static let geminiURL = URL(string: "https://gemini.google.com/app")!
        static let geminiHost = "gemini.google.com"
        static let geminiAppPath = "/app"
        static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        static let defaultPageZoom: Double = 1.0
        static let dockOffset: CGFloat = 50
        static let mainWindowIdentifier = "main"
        static let mainWindowTitle = "Gemini Desktop"
    }

    // JavaScript to fix IME double-enter issue on Gemini
    // When using IME (e.g., Chinese/Japanese input), pressing Enter after completing
    // composition would require a second Enter to send. This script detects when
    // IME composition just ended and automatically clicks the send button.
    static let imeFixScriptSource = """
    (function() {
        'use strict';

        // IME state tracking
        let imeActive = false;
        let imeJustEnded = false;
        let lastImeEndTime = 0;
        const IME_BUFFER_TIME = 300; // Response time after IME ends (milliseconds)

        // Check if IME input just finished
        function justFinishedImeInput() {
            return imeJustEnded || (Date.now() - lastImeEndTime < IME_BUFFER_TIME);
        }

        // Handle IME composition events
        document.addEventListener('compositionstart', function() {
            imeActive = true;
            imeJustEnded = false;
        }, true);

        document.addEventListener('compositionend', function() {
            imeActive = false;
            imeJustEnded = true;
            lastImeEndTime = Date.now();
            setTimeout(() => { imeJustEnded = false; }, IME_BUFFER_TIME);
        }, true);

        // Find and click the send button
        function findAndClickSendButton() {
            const selectors = [
                'button[type="submit"]',
                'button.send-button',
                'button.submit-button',
                '[aria-label="发送"]',
                '[aria-label="Send"]',
                'button:has(svg[data-icon="paper-plane"])',
                '#send-button',
            ];

            for (const selector of selectors) {
                const buttons = document.querySelectorAll(selector);
                for (const button of buttons) {
                    if (button &&
                        !button.disabled &&
                        button.offsetParent !== null &&
                        getComputedStyle(button).display !== 'none') {
                        button.click();
                        return true;
                    }
                }
            }

            // Fallback: try form submission
            const activeElement = document.activeElement;
            if (activeElement && (activeElement.tagName === 'TEXTAREA' || activeElement.tagName === 'INPUT')) {
                const form = activeElement.closest('form');
                if (form) {
                    form.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
                    return true;
                }
            }

            return false;
        }

        // Listen for Enter key
        document.addEventListener('keydown', function(e) {
            if ((e.key === 'Enter' || e.keyCode === 13) &&
                !e.shiftKey && !e.ctrlKey && !e.altKey &&
                !imeActive && justFinishedImeInput()) {
                if (findAndClickSendButton()) {
                    e.stopImmediatePropagation();
                    e.preventDefault();
                    return false;
                }
            }
        }, true);

        // Enhance input elements
        function enhanceInputElement(input) {
            const originalKeyDown = input.onkeydown;

            input.onkeydown = function(e) {
                if ((e.key === 'Enter' || e.keyCode === 13) &&
                    !e.shiftKey && !e.ctrlKey && !e.altKey &&
                    !imeActive && justFinishedImeInput()) {
                    if (findAndClickSendButton()) {
                        e.stopPropagation();
                        e.preventDefault();
                        return false;
                    }
                }
                if (originalKeyDown) return originalKeyDown.call(this, e);
            };
        }

        // Process existing and new input elements
        function processInputElements() {
            document.querySelectorAll('textarea, input[type="text"]').forEach(enhanceInputElement);
        }

        // Initial processing after page load
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', function() {
                setTimeout(processInputElements, 1000);
            });
        } else {
            setTimeout(processInputElements, 1000);
        }

        // Monitor DOM changes for new input elements
        if (window.MutationObserver) {
            const observer = new MutationObserver((mutations) => {
                mutations.forEach((mutation) => {
                    if (mutation.addedNodes && mutation.addedNodes.length > 0) {
                        mutation.addedNodes.forEach((node) => {
                            if (node.nodeType === 1) {
                                if (node.tagName === 'TEXTAREA' ||
                                    (node.tagName === 'INPUT' && node.type === 'text')) {
                                    enhanceInputElement(node);
                                }

                                const inputs = node.querySelectorAll ?
                                    node.querySelectorAll('textarea, input[type="text"]') : [];
                                if (inputs.length > 0) {
                                    inputs.forEach(enhanceInputElement);
                                }
                            }
                        });
                    }
                });
            });

            observer.observe(document.body, {
                childList: true,
                subtree: true
            });
        }
    })();
    """

}
