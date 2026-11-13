//
//  FullDiskAccess.swift
//  Downer
//
//  Safari keeps its cookies in a folder macOS protects. Reading it needs Full Disk Access
//  for Downer (yt-dlp runs as Downer's child, so macOS attributes its reads to Downer).
//  This file only finds out whether that access exists, and opens the right Settings pane.
//

import AppKit
import Darwin
import Foundation

enum FullDiskAccess {
    enum Status: Equatable {
        case granted
        case denied
        /// Safari's cookie file does not exist at either location (Safari never used, or moved).
        case noCookieFile
    }

    /// Where Safari's cookie file may be, in the order yt-dlp tries them (legacy first, then the container).
    nonisolated static func candidatePaths(home: String) -> [String] {
        [
            home + "/Library/Cookies/Cookies.binarycookies",
            home + "/Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies",
        ]
    }

    /// Pure decision from the result of trying each candidate (`nil` = opened, else the errno).
    /// Any success means granted; a permission error anywhere means denied; all "no such file" means none.
    nonisolated static func status(fromAttempts errors: [Int32?]) -> Status {
        if errors.contains(where: { $0 == nil }) { return .granted }
        if errors.contains(where: { $0 == EPERM || $0 == EACCES }) { return .denied }
        return .noCookieFile
    }

    /// Whether Downer can currently open Safari's cookie file.
    /// The file is opened ONLY to test the permission and closed straight away: no byte is ever read.
    nonisolated static func check(home: String = realHome()) -> Status {
        let attempts: [Int32?] = candidatePaths(home: home).map { path in
            let fd = open(path, O_RDONLY)
            if fd >= 0 {
                close(fd)
                return nil
            }
            return errno
        }
        return status(fromAttempts: attempts)
    }

    /// The account's home folder from the user database, not from $HOME (which a launching tool can change).
    nonisolated static func realHome() -> String {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir { return String(cString: dir) }
        return NSHomeDirectory()
    }

    /// Settings → Privacy & Security → Full Disk Access. The first form is the one macOS 13+ documents;
    /// the older form is kept as a fallback (it is still routed on current releases).
    static let settingsURLs: [URL] = [
        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
        "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
    ].compactMap(URL.init(string:))

    @MainActor static func openSettings() {
        for url in settingsURLs where NSWorkspace.shared.open(url) { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    /// Shown wherever Full Disk Access is offered.
    static let relaunchNote = "After allowing it, quit and reopen Downer."
}

/// The environment yt-dlp is started with.
enum YtDlpEnvironment {
    /// Starts from the app's own environment and makes it safe for locating browser data:
    /// HOME is the real home folder (yt-dlp builds every browser path from `~`), and XDG_* variables
    /// that a launching terminal may carry are dropped. PATH gets ffmpeg's folder in front.
    nonisolated static func make(base: [String: String], ffmpegDirectory: String?, home: String) -> [String: String] {
        var env = base.filter { !$0.key.hasPrefix("XDG_") }
        env["HOME"] = home
        if let ffmpegDirectory, !ffmpegDirectory.isEmpty {
            env["PATH"] = ffmpegDirectory + ":" + (env["PATH"] ?? "")
        }
        return env
    }
}
