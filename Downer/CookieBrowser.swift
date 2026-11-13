//
//  CookieBrowser.swift
//  Downer
//
//  Browsers yt-dlp can borrow a login from (--cookies-from-browser).
//

import AppKit
import Foundation

enum CookieBrowser: String, CaseIterable, Identifiable, Codable {
    case safari, chrome, firefox, brave, edge, chromium, vivaldi, opera

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .safari: "Safari"
        case .chrome: "Chrome"
        case .firefox: "Firefox"
        case .brave: "Brave"
        case .edge: "Edge"
        case .chromium: "Chromium"
        case .vivaldi: "Vivaldi"
        case .opera: "Opera"
        }
    }

    /// The name yt-dlp accepts.
    var ytDlpName: String { rawValue }

    /// The app's bundle identifier, used only to see whether it is installed.
    var bundleIdentifier: String {
        switch self {
        case .safari: "com.apple.Safari"
        case .chrome: "com.google.Chrome"
        case .firefox: "org.mozilla.firefox"
        case .brave: "com.brave.Browser"
        case .edge: "com.microsoft.edgemac"
        case .chromium: "org.chromium.Chromium"
        case .vivaldi: "com.vivaldi.Vivaldi"
        case .opera: "com.operasoftware.Opera"
        }
    }

    var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    /// The first installed browser, in the order most people use them.
    static var firstInstalled: CookieBrowser? { allCases.first { $0.isInstalled } }

    /// What macOS will ask for (or not) the first time this browser's cookies are read.
    var permissionNote: String {
        switch self {
        case .safari:
            "Safari's cookies are protected. Downer needs Full Disk Access (System Settings → Privacy & Security → Full Disk Access). Downer won't ask for it — add it yourself, or pick another browser."
        case .firefox:
            "No extra permission needed."
        case .chrome, .brave, .edge, .chromium, .vivaldi, .opera:
            "macOS will ask once to let Downer use “\(displayName) Safe Storage” from your Keychain — this is how the cookies are decrypted."
        }
    }
}
