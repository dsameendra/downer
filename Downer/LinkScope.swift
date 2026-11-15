//
//  LinkScope.swift
//  Downer
//
//  Whether a link means one video, a whole playlist, or a video that is playing inside a
//  playlist (`watch?v=…&list=…`). yt-dlp downloads the whole list for that last kind unless it
//  is told `--no-playlist`, so Downer asks which one was meant. Read from the address alone:
//  instant, offline, and the same answer every time.
//

import Foundation

/// What yt-dlp is told about a link that could mean a video or its list.
enum PlaylistScope: String, Equatable {
    /// `--no-playlist`
    case video
    /// `--yes-playlist`
    case playlist

    var flag: String { self == .video ? "--no-playlist" : "--yes-playlist" }
    var other: PlaylistScope { self == .video ? .playlist : .video }
}

/// Settings → Downloads: what to do with a link to a video inside a playlist.
enum PlaylistLinkChoice: String, CaseIterable, Identifiable {
    case ask, video, playlist

    static let storageKey = "playlistLinkChoice"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .ask: return "Ask Each Time"
        case .video: return "Just the Video"
        case .playlist: return "The Whole Playlist"
        }
    }

    static func current(_ defaults: UserDefaults = .standard) -> PlaylistLinkChoice {
        PlaylistLinkChoice(rawValue: defaults.string(forKey: storageKey) ?? "") ?? .ask
    }
}

enum LinkKind: Equatable {
    /// One YouTube video, with no list.
    case video
    /// A YouTube list with no video named (`playlist?list=…`); always the whole list.
    case playlist
    /// A whole Mix with no video named (`playlist?list=RD…`): confirmed before it downloads.
    case mix
    /// A YouTube video playing inside a list. `isMix`: a Mix or radio that YouTube makes up on the fly.
    case videoInList(isMix: Bool)
    /// Any other site, or a link Downer can't read; yt-dlp decides.
    case other

    var isVideoInList: Bool {
        if case .videoInList = self { return true }
        return false
    }

    var isMix: Bool {
        switch self {
        case .videoInList(let isMix): return isMix
        case .mix: return true
        default: return false
        }
    }

    /// "Mix" or "Playlist", for buttons and swipe actions.
    var listName: String { isMix ? "Mix" : "Playlist" }
}

enum LinkScope {
    nonisolated static func classify(_ link: String) -> LinkKind {
        guard let parts = YouTubeLink(link) else { return .other }
        if let list = parts.list {
            if parts.videoID == nil { return isMix(list) ? .mix : .playlist }
            return .videoInList(isMix: isMix(list))
        }
        return parts.videoID == nil ? .other : .video
    }

    /// Mixes and radios (`RD…`, `RDMM`, `RDAMVM…`) are generated per person and can run to hundreds of
    /// videos. `RDCLAK5uy_…` also starts with RD but is an album with a fixed track list.
    nonisolated static func isMix(_ list: String) -> Bool {
        list.hasPrefix("RD") && !list.hasPrefix("RDCLAK5uy_")
    }

    /// The link to hand to yt-dlp. Unchanged, except a Short inside a playlist when only the video is
    /// wanted: yt-dlp turns `/shorts/ID?list=…` into the playlist and ignores `--no-playlist` for it.
    nonisolated static func urlForYtDlp(_ link: String, scope: PlaylistScope?) -> String {
        guard scope == .video, let parts = YouTubeLink(link), parts.isShort, parts.list != nil,
            let id = parts.videoID
        else { return link }
        return "https://www.youtube.com/shorts/\(id)"
    }
}

/// The parts of a YouTube link that matter here.
private struct YouTubeLink {
    var videoID: String?
    var list: String?
    var isShort = false

    private static let hosts: Set<String> = [
        "youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com",
        "youtube-nocookie.com", "www.youtube-nocookie.com", "youtu.be", "www.youtu.be",
    ]
    /// Paths whose next component is a video id.
    private static let videoPaths: Set<String> = ["shorts", "live", "embed", "v", "e"]

    init?(_ link: String) {
        guard let components = URLComponents(string: link.trimmingCharacters(in: .whitespaces)),
            let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
            let host = components.host?.lowercased(), Self.hosts.contains(host)
        else { return nil }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value.flatMap { $0.isEmpty ? nil : $0 }
        }
        list = value("list")
        let path = components.path.split(separator: "/").map(String.init)
        if host.hasSuffix("youtu.be") {
            videoID = path.first
        } else if path.first == "watch" {
            videoID = value("v")
        } else if path.count >= 2, Self.videoPaths.contains(path[0]), path[1] != "videoseries" {
            // (`embed/videoseries?list=…` is a whole playlist; "videoseries" happens to be 11 letters)
            videoID = path[1]
            isShort = path[0] == "shorts"
        }
        if let id = videoID, !Self.isVideoID(id) { videoID = nil }
    }

    /// YouTube ids are 11 characters of [A-Za-z0-9_-].
    private static func isVideoID(_ id: String) -> Bool {
        id.count == 11 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
    }
}
