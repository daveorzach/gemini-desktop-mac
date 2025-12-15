//
//  UserScripts.swift
//  GeminiDesktop
//
//  Created by alexcding on 2025-12-15.
//

import WebKit

/// Collection of user scripts injected into WKWebView
enum UserScripts {

    /// Creates all user scripts to be injected into the WebView
    static func createAllScripts() -> [WKUserScript] {
        [
            createIMEFixScript()
        ]
    }

    /// Creates the IME fix script that resolves the double-enter issue
    /// when using input method editors (e.g., Chinese, Japanese, Korean input)
    private static func createIMEFixScript() -> WKUserScript {
        WKUserScript(
            source: imeFixSource,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
    }

    // MARK: - Script Sources

    /// JavaScript to fix IME double-enter issue on Gemini
    /// When using IME (e.g., Chinese/Japanese input), pressing Enter after completing
    /// composition would require a second Enter to send. This script detects when
    /// IME composition just ended and automatically clicks the send button.
    /// https://update.greasyfork.org/scripts/532717/阻止Gemini两次点击.user.js
    private static let imeFixSource = """
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
