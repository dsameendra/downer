//
//  YtDlpArguments.swift
//  Downer
//
//  The one place yt-dlp's command line is assembled, for both the quick
//  title look-up and the real download.
//

import Foundation

enum YtDlpArguments {
    enum Purpose: Equatable {
        case probe(only: [Int]?)
        case download(pathFile: String, ffmpegDirectory: String, only: [Int]?)
    }

    /// Order: format args (download only), extra args, cookies, Downer's own flags, the link.
    nonisolated static func build(
        for options: JobOptions, purpose: Purpose, useCookies: Bool, url: String
    ) -> [String] {
        var args: [String] = []
        if case .download = purpose { args += formatArguments(for: options) }
        args += options.extraArguments
        if useCookies, let browser = options.cookiesBrowser {
            args += ["--cookies-from-browser", browser.ytDlpName]
        }
        switch purpose {
        case .probe(let only):
            args += ["--flat-playlist", "--no-warnings", "--print", "%(playlist_title|)s\t%(title)s"]
            args += items(only)
        case .download(let pathFile, let ffmpegDirectory, let only):
            args += ["--print-to-file", "after_move:filepath", pathFile]
            args += ["--newline", "--ffmpeg-location", ffmpegDirectory]
            args += items(only)
        }
        args.append(url)
        return args
    }

    nonisolated private static func items(_ only: [Int]?) -> [String] {
        only.map { ["--playlist-items", $0.map(String.init).joined(separator: ",")] } ?? []
    }

    nonisolated static func formatArguments(for o: JobOptions) -> [String] {
        // step 2: honour o.compatibilityH264
        func abr(_ quality: String) -> Int? { Int(quality.replacingOccurrences(of: "k", with: "")) }
        let audioFilter = abr(o.audioQuality).map { "bestaudio[abr<=\($0)][vcodec=none]" } ?? "bestaudio"

        switch o.type {
        case .audio:
            var args = ["-f", audioFilter]
            if o.audioFormat != "source" {  // transcode only if asked
                args += ["--extract-audio", "--audio-format", o.audioFormat]
                if let rate = abr(o.audioQuality), rate <= 160 {
                    args += ["--audio-quality", o.audioQuality]
                }
            }
            return args
        case .video:
            return ["-f", "bestvideo[height<=\(o.resolution)][acodec=none]", "--remux-video", o.container]
        case .both:
            return [
                "-f", "bestvideo[height<=\(o.resolution)]+\(audioFilter)",
                "--merge-output-format", o.container,
            ]
        }
    }
}
