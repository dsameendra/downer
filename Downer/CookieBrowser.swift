//
//  CookieBrowser.swift
//  Downer
//
//  Browsers yt-dlp can borrow a login from (--cookies-from-browser).
//

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
}
