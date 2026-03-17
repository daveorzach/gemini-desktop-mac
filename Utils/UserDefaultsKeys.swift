//
//  UserDefaultsKeys.swift
//  GeminiDesktop
//
//  Created by alexcding on 2025-12-13.
//

import Foundation
import AppKit
import SwiftUI

enum UserDefaultsKeys: String {
    case panelWidth
    case panelHeight
    case pageZoom
    case hideWindowAtLaunch
    case hideDockIcon
    case appTheme
    case useCustomToolbarColor
    case toolbarColorHex
    case promptsDirectoryBookmark
    case artifactsDirectoryBookmark
    case promptInjectionMode   // "copy" | "inject"
    case showPromptMetadata    // Bool, default false
    case debugModeEnabled
    case userAgentOption
    case customUserAgent
    case panelPosition
    case panelX
    case panelY
    case alwaysOnTop
}

enum AppTheme: String, CaseIterable {
    case system
    case light
    case dark

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    @MainActor
    func apply() {
        switch self {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    static var current: AppTheme {
        let raw = UserDefaults.standard.string(forKey: UserDefaultsKeys.appTheme.rawValue) ?? "system"
        return AppTheme(rawValue: raw) ?? .system
    }
}

// MARK: - Color Extensions
extension Color {
    init?(_ hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        var r: CGFloat = 0.0
        var g: CGFloat = 0.0
        var b: CGFloat = 0.0
        var a: CGFloat = 1.0

        let length = hexSanitized.count

        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        if length == 6 {
            r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
            g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
            b = CGFloat(rgb & 0x0000FF) / 255.0

        } else if length == 8 {
            r = CGFloat((rgb & 0xFF000000) >> 24) / 255.0
            g = CGFloat((rgb & 0x00FF0000) >> 16) / 255.0
            b = CGFloat((rgb & 0x0000FF00) >> 8) / 255.0
            a = CGFloat(rgb & 0x000000FF) / 255.0

        } else {
            return nil
        }

        self.init(.sRGB, red: Double(r), green: Double(g), blue: Double(b), opacity: Double(a))
    }

    func toHex() -> String? {
        guard let components = NSColor(self).usingColorSpace(.sRGB)?.cgColor.components, components.count >= 3 else {
            return nil
        }

        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])
        var a = Float(1.0)

        if components.count >= 4 {
            a = Float(components[3])
        }

        if a != 1.0 {
            return String(format: "#%02lX%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255), lroundf(a * 255))
        } else {
            return String(format: "#%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255))
        }
    }
}

enum UserAgentOption: String, CaseIterable {
    case safari
    case chrome
    case custom

    var displayName: String {
        switch self {
        case .safari: return "Safari"
        case .chrome: return "Chrome"
        case .custom: return "Custom"
        }
    }

    static let safariUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    static let chromeUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

    func userAgentString(custom: String = "") -> String {
        switch self {
        case .safari: return Self.safariUA
        case .chrome: return Self.chromeUA
        case .custom: return custom.isEmpty ? Self.safariUA : custom
        }
    }

    func settingsDescription(custom: String = "") -> String {
        switch self {
        case .safari: return "Identifies as Safari 17.0 on macOS"
        case .chrome: return "Identifies as Chrome 131 on macOS"
        case .custom: return custom.isEmpty ? "No custom user agent set — falls back to Safari" : "Using custom user agent string"
        }
    }

    static var current: UserAgentOption {
        let raw = UserDefaults.standard.string(forKey: UserDefaultsKeys.userAgentOption.rawValue) ?? "safari"
        return UserAgentOption(rawValue: raw) ?? .safari
    }

    static var currentUserAgentString: String {
        let option = current
        let custom = UserDefaults.standard.string(forKey: UserDefaultsKeys.customUserAgent.rawValue) ?? ""
        return option.userAgentString(custom: custom)
    }
}

enum PanelPosition: String, CaseIterable {
    case bottomLeft
    case bottomCenter
    case bottomRight
    case rememberLast

    var displayName: String {
        switch self {
        case .bottomLeft: return "Bottom Left"
        case .bottomCenter: return "Bottom Center"
        case .bottomRight: return "Bottom Right"
        case .rememberLast: return "Remember Last Position"
        }
    }

    static var current: PanelPosition {
        let raw = UserDefaults.standard.string(forKey: UserDefaultsKeys.panelPosition.rawValue) ?? "bottomCenter"
        return PanelPosition(rawValue: raw) ?? .bottomCenter
    }
}
