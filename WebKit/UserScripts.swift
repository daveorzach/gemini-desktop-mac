//
//  UserScripts.swift
//  GeminiDesktop
//
//  Created by alexcding on 2025-12-15.
//

import WebKit

/// Collection of user scripts injected into WKWebView
enum UserScripts {

    /// Message handler name for console log bridging
    static let consoleLogHandler = "consoleLog"

    /// Message handler name for conversation started notification
    static let conversationStartedHandler = "conversationStarted"

    /// Message handler name for file input clicked notification
    static let fileInputClickedHandler = "fileInputClicked"

    /// Message handler name for debug network payload capture
    static let debugNetworkCaptureHandler = "debugNetworkCapture"

    /// Creates all user scripts to be injected into the WebView
    nonisolated static func createAllScripts() -> [WKUserScript] {
        var scripts: [WKUserScript] = [
            createConversationObserverScript(),
            createIMEFixScript(),
            createFilePickerScript()
        ]

        #if DEBUG
        scripts.insert(createConsoleLogBridgeScript(), at: 0)
        #endif

        // Note: createMetadataScript() is intentionally excluded — it requires @MainActor
        // and is called lazily at capture time by AppCoordinator.fetchMetadataPreview().

        return scripts
    }

    /// Creates a script that bridges console.log to native Swift
    nonisolated private static func createConsoleLogBridgeScript() -> WKUserScript {
        WKUserScript(
            source: consoleLogBridgeSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
    }

    /// Creates a script that observes for conversation start and notifies Swift
    nonisolated private static func createConversationObserverScript() -> WKUserScript {
        WKUserScript(
            source: conversationObserverSource,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
    }

    /// Creates the IME fix script that resolves the double-enter issue
    /// when using input method editors (e.g., Chinese, Japanese, Korean input)
    nonisolated private static func createIMEFixScript() -> WKUserScript {
        WKUserScript(
            source: imeFixSource,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
    }

    /// Creates a script that intercepts file input clicks and routes them through
    /// the native file picker bridge.
    nonisolated private static func createFilePickerScript() -> WKUserScript {
        WKUserScript(
            source: filePickerSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
    }

    /// Creates a script that extracts conversation metadata from the Gemini DOM.
    /// Returns a JSON string. Each field is individually wrapped in try/catch.
    /// All extraction expressions are sourced from GeminiSelectors.shared.metadata
    /// (user-patchable via gemini-selectors.json — no recompile needed for selector updates).
    /// Requires @MainActor context to access GeminiSelectors.shared.
    @MainActor static func createMetadataScript() -> String {
        let entries = GeminiSelectors.shared.metadata
        var blocks: [String] = []

        for (key, expr) in entries {
            let exprs = expr.expressions
            let isArrayField = key == "attachments"  // only array-valued field in current schema
            if exprs.count == 1 {
                blocks.append(singleExprBlock(key: key, expr: exprs[0], isArrayField: isArrayField))
            } else {
                blocks.append(multiExprBlock(key: key, exprs: exprs))
            }
        }

        return """
        (function() {
            var result = {};
            \(blocks.joined(separator: "\n    "))
            return JSON.stringify(result);
        })();
        """
    }

    /// Generates a JS try/catch block that evaluates one expression and assigns to result[key].
    /// isArrayField: if true, skips the empty-string check (arrays are never empty strings).
    /// On catch, sets result[key] to null (scalar) or [] (array).
    nonisolated private static func singleExprBlock(key: String, expr: String, isArrayField: Bool) -> String {
        if isArrayField {
            return """
            try { result["\(key)"] = (\(expr)); } catch(e) { result["\(key)"] = []; }
            """
        } else {
            return """
            try { var _v = (\(expr)); result["\(key)"] = (_v !== null && _v !== undefined && _v !== '') ? _v : null; } catch(e) { result["\(key)"] = null; }
            """
        }
    }

    /// Generates an IIFE that tries each expression in order, assigning the first
    /// non-null non-empty result to result[key]. Falls through to null if all fail.
    nonisolated private static func multiExprBlock(key: String, exprs: [String]) -> String {
        var lines: [String] = ["(function() {"]
        for expr in exprs {
            lines.append("""
                try { var _v = (\(expr)); if (_v !== null && _v !== undefined && _v !== '') { result["\(key)"] = _v; return; } } catch(e) {}
            """)
        }
        lines.append("""
            result["\(key)"] = null;
        })();
        """)
        return lines.joined(separator: "\n")
    }

    /// Generates the metadataProbe JS — one IIFE per metadata field.
    /// Uses eval (safe: evaluateJavaScript bypasses page CSP; expressions come from GeminiSelectors, not page).
    /// Array-valued fields (attachments) use JSON.stringify for the value.
    @MainActor private static func metadataProbeBlocks() -> String {
        let entries = GeminiSelectors.shared.metadata
        var blocks: [String] = []

        for (key, expr) in entries {
            let exprs = expr.expressions
            let isArrayField = key == "attachments"
            // Build JS array literal of expression strings, escaping backslashes and double quotes
            let jsExprs = exprs.map { e -> String in
                let escaped = e
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                return "\"\(escaped)\""
            }.joined(separator: ", ")

            let valueExpr = isArrayField
                ? "JSON.stringify(_v).slice(0, 120)"
                : "String(_v).slice(0, 120)"
            let nullCheck = isArrayField
                ? "_v !== null && _v !== undefined"
                : "_v !== null && _v !== undefined && _v !== ''"

            blocks.append("""
            (function() {
                var field = "\(key)";
                var exprs = [\(jsExprs)];
                for (var i = 0; i < exprs.length; i++) {
                    try {
                        var _v = eval(exprs[i]);
                        if (\(nullCheck)) {
                            metadataProbe.push({ field: field, matchedIndex: i, value: \(valueExpr) });
                            return;
                        }
                    } catch(e) {}
                }
                metadataProbe.push({ field: field, matchedIndex: null, value: null });
            })();
            """)
        }

        return blocks.joined(separator: "\n")
    }

    // MARK: - Script Sources

    /// JavaScript to bridge console.log to native Swift via WKScriptMessageHandler
    private static let consoleLogBridgeSource = """
    (function() {
        const originalLog = console.log;
        console.log = function(...args) {
            originalLog.apply(console, args);
            try {
                const message = args.map(arg => {
                    if (typeof arg === 'object') {
                        return JSON.stringify(arg, null, 2);
                    }
                    return String(arg);
                }).join(' ');
                window.webkit.messageHandlers.\(consoleLogHandler).postMessage(message);
            } catch (e) {}
        };
    })();
    """

    /// JavaScript to fix IME Enter issue on Gemini
    /// When using IME (e.g., Chinese/Japanese input), pressing Enter to confirm
    /// the IME composition should NOT send the message. This script intercepts
    /// Enter keydown events during and immediately after IME composition,
    /// preventing them from reaching Gemini's send handler.
    private static let imeFixSource = """
    (function() {
        'use strict';

        let imeActive = false;
        let imeEverUsed = false;
        let compositionEndTime = 0;
        const BUFFER_TIME = 300;

        function isInIMEWindow() {
            return imeActive || (Date.now() - compositionEndTime < BUFFER_TIME);
        }

        document.addEventListener('compositionstart', function() {
            imeActive = true;
            imeEverUsed = true;
        }, true);

        document.addEventListener('compositionend', function() {
            imeActive = false;
            compositionEndTime = Date.now();
        }, true);

        document.addEventListener('keydown', function(e) {
            if (!imeEverUsed) return;
            if (e.key !== 'Enter' || e.shiftKey || e.ctrlKey || e.altKey) return;

            if (isInIMEWindow() || e.isComposing || e.keyCode === 229) {
                e.stopImmediatePropagation();
                e.preventDefault();
            }
        }, true);

        document.addEventListener('beforeinput', function(e) {
            if (!imeEverUsed) return;
            if (e.inputType !== 'insertParagraph' && e.inputType !== 'insertLineBreak') return;

            if (isInIMEWindow()) {
                e.stopImmediatePropagation();
                e.preventDefault();
            }
        }, true);
    })();
    """

    /// JavaScript that intercepts hidden file input clicks and routes them to
    /// the native NSOpenPanel via WKScriptMessageHandler.
    ///
    /// Flow: input.click() intercept → postMessage → Swift NSOpenPanel
    ///   → evaluateJavaScript callback → fetch(gemini-file://) → DataTransfer → input.files
    private static let filePickerSource = """
    (function() {
        window.__GeminiDesktop = window.__GeminiDesktop || {};

        var pendingFileInput = null;
        var pendingNonce = null;

        // Intercept programmatic clicks on hidden file inputs.
        // WKWebView drops these silently (gesture token expired by the time
        // Gemini's async code calls click()). We route them native instead.
        var origClick = HTMLInputElement.prototype.click;
        HTMLInputElement.prototype.click = function() {
            if (this.type === 'file') {
                pendingFileInput = this;
                pendingNonce = Math.random().toString(36).slice(2);
                window.webkit.messageHandlers.\(fileInputClickedHandler).postMessage({
                    multiple: this.multiple,
                    accept: this.accept || '',
                    nonce: pendingNonce
                });
            } else {
                origClick.call(this);
            }
        };

        // Called by Swift after NSOpenPanel completes.
        // fileDataArray: array of {name, type, data} objects with base64-encoded data,
        // or empty on cancel. Data is passed via callAsyncJavaScript (not fetch) to
        // bypass Gemini's Content-Security-Policy connect-src restrictions.
        window.__GeminiDesktop.filesSelectedWithData = function(nonce, fileDataArray) {
            if (nonce !== pendingNonce) { return; } // stale response from a previous picker
            var input = pendingFileInput;
            pendingFileInput = null;
            pendingNonce = null;
            if (!input || !fileDataArray || !fileDataArray.length) { return; }

            try {
                var dt = new DataTransfer();
                fileDataArray.forEach(function(fd) {
                    var binary = atob(fd.data);
                    var bytes = new Uint8Array(binary.length);
                    for (var i = 0; i < binary.length; i++) { bytes[i] = binary.charCodeAt(i); }
                    dt.items.add(new File([bytes.buffer], fd.name, { type: fd.type }));
                });
                input.files = dt.files; // supported in WebKit via DataTransfer
                input.dispatchEvent(new Event('change', { bubbles: true }));
                input.dispatchEvent(new Event('input', { bubbles: true }));
            } catch (err) {
                console.error('[GeminiDesktop] File data error:', err);
            }
        };
    })();
    """

    /// JavaScript to observe when a conversation starts and notify Swift
    private static let conversationObserverSource = """
    (function() {
        const handler = '\(conversationStartedHandler)';
        const targetSelector = 'infinite-scroller[data-test-id="chat-history-container"]';
        let notified = false;

        function checkAndNotify() {
            if (notified) return;
            const scroller = document.querySelector(targetSelector);
            if (!scroller) return;
            const hasContent = scroller.querySelector('response-container') !== null
                            || scroller.querySelector('[aria-label="Good response"]') !== null
                            || scroller.querySelector('[aria-label="Bad response"]') !== null;
            if (hasContent) {
                notified = true;
                window.webkit.messageHandlers[handler].postMessage(true);
            }
        }

        const observer = new MutationObserver(checkAndNotify);
        observer.observe(document.body, { childList: true, subtree: true });
        checkAndNotify();
    })();
    """

    // MARK: - Prompt Injection

    nonisolated static func createInjectionScript(escapedText: String, richTextareaSelector: String) -> String {
        """
        (function() {
            const textarea = document.querySelector('\(richTextareaSelector)');
            if (!textarea) return false;

            try {
                const text = '\(escapedText)';
                if (document.execCommand('insertText', false, text)) {
                    return true;
                }

                // Fallback: use InputEvent
                const dt = new DataTransfer();
                dt.items.add(new File([text], 'paste', { type: 'text/plain' }));
                const pasteEvent = new ClipboardEvent('paste', { clipboardData: dt, bubbles: true });
                textarea.dispatchEvent(pasteEvent);

                const inputEvent = new InputEvent('input', { data: text, bubbles: true, inputType: 'insertText' });
                textarea.dispatchEvent(inputEvent);
                return true;
            } catch (e) {
                return false;
            }
        })();
        """
    }

    // MARK: - Artifact Capture

    nonisolated static func createCaptureScript(lastResponseSelector: String) -> String {
        """
        (function() {
            // Check if still streaming — look for structural CSS class (language-agnostic)
            const isStreaming = document.querySelector('button.send-button.stop') !== null;

            if (isStreaming) {
                return '__streaming__';
            }

            const responseEl = document.querySelector('\(lastResponseSelector)');
            return responseEl ? responseEl.innerHTML : '';
        })();
        """
    }

    // MARK: - Debug Capture Scripts

    /// DOM capture: selector probe + all data-test-id elements + structural data-ved/jsaction nodes.
    /// selectorJSON: JSON string of { fieldName: cssSelector } pairs built by AppCoordinator.
    /// Requires @MainActor context to access GeminiSelectors.shared via metadataProbeBlocks().
    @MainActor static func createDOMCaptureScript(selectorJSON: String) -> String {
        """
        (function() {
            try {
                var selectors = \(selectorJSON);

                // 1. Selector probe — hit/miss + element details for each field
                var selectorProbe = Object.keys(selectors).map(function(field) {
                    var sel = selectors[field];
                    var el = document.querySelector(sel);
                    return {
                        field: field,
                        selector: sel,
                        found: el !== null,
                        tag: el ? el.tagName : null,
                        classes: el ? (el.className || '').toString().slice(0, 100) : null,
                        dataTestId: el ? el.getAttribute('data-test-id') : null,
                        ariaLabel: el ? el.getAttribute('aria-label') : null,
                        textSnippet: el ? el.textContent.trim().slice(0, 80) : null
                    };
                });

                // 2. All visible data-test-id elements (primary lookup table for replacements)
                var dataTestIds = Array.from(document.querySelectorAll('[data-test-id]'))
                    .filter(function(el) { return el.offsetParent !== null; })
                    .map(function(el) {
                        return {
                            tag: el.tagName,
                            dataTestId: el.getAttribute('data-test-id'),
                            ariaLabel: el.getAttribute('aria-label'),
                            text: el.textContent.trim().slice(0, 60)
                        };
                    });

                // 3. Structural Wiz elements, capped at 200
                var structural = Array.from(document.querySelectorAll('[data-ved], [jsaction]'))
                    .slice(0, 200)
                    .map(function(el) {
                        return {
                            tag: el.tagName,
                            classes: (el.className || '').toString().slice(0, 80),
                            dataVed: el.getAttribute('data-ved'),
                            jsaction: (el.getAttribute('jsaction') || '').slice(0, 100),
                            jscontroller: el.getAttribute('jscontroller')
                        };
                    });

                // 4. Metadata expression probe
                var metadataProbe = [];
                \(metadataProbeBlocks())

                return JSON.stringify({
                    selectorProbe: selectorProbe,
                    dataTestIds: dataTestIds,
                    structural: structural,
                    metadataProbe: metadataProbe
                });
            } catch(e) {
                return JSON.stringify({ error: e.message });
            }
        })();
        """
    }

    /// WIZ state capture: serializes window.WIZ_global_data.
    nonisolated static func createWIZCaptureScript() -> String {
        """
        (function() {
            try {
                return JSON.stringify(window.WIZ_global_data || {});
            } catch(e) {
                return JSON.stringify({ error: e.message });
            }
        })();
        """
    }

    /// Fetch interceptor — injected at document start when debug mode is on.
    /// Passively buffers batchexecute payloads and posts them to the
    /// 'debugNetworkCapture' WKScriptMessageHandler.
    nonisolated static func createFetchInterceptorScript() -> String {
        """
        (function() {
            if (window.__GeminiDesktopDebugIntercepted) return;
            window.__GeminiDesktopDebugIntercepted = true;
            var originalFetch = window.fetch;
            window.fetch = function() {
                var url = arguments[0];
                var options = arguments[1];
                if (url && url.toString().includes('/batchexecute') && options && options.body) {
                    try {
                        window.webkit.messageHandlers.\(debugNetworkCaptureHandler).postMessage({
                            url: url.toString(),
                            payload: options.body.toString().slice(0, 8000)
                        });
                    } catch(e) {}
                }
                return originalFetch.apply(this, arguments);
            };
        })();
        """
    }
}
