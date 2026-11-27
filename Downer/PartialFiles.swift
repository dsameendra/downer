//
//  PartialFiles.swift
//  Downer
//
//  Clearing away what a cancelled download left in the destination folder.
//

import AppKit

enum PartialFiles {
    /// `finalNames` are the paths yt-dlp was about to write (`before_dl:filename`). Only files next to them
    /// that are yt-dlp's unfinished pieces of those names, and were touched since `since`, are removed:
    /// a finished video, or anything else in the folder, is never touched.
    nonisolated static func leftovers(
        of finalNames: [URL], since: Date, fileManager fm: FileManager = .default
    ) -> [URL] {
        var found: [URL] = []
        var seen = Set<String>()
        for final in finalNames {
            let directory = final.deletingLastPathComponent()
            let stem = final.deletingPathExtension().lastPathComponent
            guard !stem.isEmpty, let names = try? fm.contentsOfDirectory(atPath: directory.path) else { continue }
            for name in names where name.hasPrefix(stem + ".") && isPiece(String(name.dropFirst(stem.count))) {
                let url = directory.appendingPathComponent(name)
                guard !seen.contains(url.path),
                    let modified = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date,
                    modified >= since.addingTimeInterval(-1)
                else { continue }
                seen.insert(url.path)
                found.append(url)
            }
        }
        return found
    }

    /// What follows the video's name: `.mp4.part`, `.mp4.ytdl`, `.mp4.part-Frag3`, a stream before the merge
    /// (`.f137.mp4`, with or without `.part`) or a merge in progress (`.temp.mp4`).
    nonisolated static func isPiece(_ rest: String) -> Bool {
        rest.wholeMatch(of: /(\.f[\w-]+|\.temp)?\.[A-Za-z0-9]+(\.part|\.ytdl|\.part-Frag\d+)+/) != nil
            || rest.wholeMatch(of: /(\.f[\w-]+|\.temp)\.[A-Za-z0-9]+/) != nil
    }

    /// Delete the leftovers, then any playlist folder this left empty (never the destination itself).
    nonisolated static func clean(
        after finalNames: [URL], destination: URL?, since: Date, fileManager fm: FileManager = .default
    ) {
        for url in leftovers(of: finalNames, since: since, fileManager: fm) {
            try? fm.removeItem(at: url)
        }
        let root = destination?.standardizedFileURL.path
        for directory in Set(finalNames.map { $0.deletingLastPathComponent().standardizedFileURL.path }) {
            guard directory != root, let inside = try? fm.contentsOfDirectory(atPath: directory), inside.isEmpty
            else { continue }
            try? fm.removeItem(atPath: directory)
        }
    }
}

/// The main window comes back where it was left, at the size it was left.
@MainActor
enum WindowPlacement {
    static let name = "DownerMainWindow"

    static func restore(_ window: NSWindow) {
        // a saved frame on a screen that is gone would put the window out of reach
        if window.setFrameAutosaveName(name), isReachable(window.frame, screens: NSScreen.screens.map(\.visibleFrame)) {
            return
        }
        window.center()
    }

    /// Enough of the window, including its title bar, is on some screen to grab it.
    nonisolated static func isReachable(_ frame: NSRect, screens: [NSRect]) -> Bool {
        screens.contains { screen in
            let overlap = screen.intersection(frame)
            return !overlap.isNull && overlap.width >= 100 && overlap.height >= 60
        }
    }
}
