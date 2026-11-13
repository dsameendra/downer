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

    /// Order: format args (download only), extra args, cookie flags, Downer's own flags, the link.
    ///
    /// yt-dlp also reads config files (~/.config/yt-dlp/config, ~/yt-dlp.conf, ...) that could turn
    /// cookies on whatever Sign-in says. Downer's flags come last, so they win: with Sign-in off,
    /// `--no-cookies --no-cookies-from-browser` cancel any cookie setting from a config; with it on,
    /// `--no-cookies` first stops a config's `--cookies FILE` (which yt-dlp would also write back to).
    nonisolated static func build(
        for options: JobOptions, purpose: Purpose, useCookies: Bool, url: String
    ) -> [String] {
        var args: [String] = []
        if case .download = purpose { args += formatArguments(for: options) }
        args += options.extraArguments
        args.append("--no-cookies")
        if useCookies, let browser = options.cookiesBrowser {
            args += ["--cookies-from-browser", browser.ytDlpName]
        } else {
            args.append("--no-cookies-from-browser")
        }
        if let runtime = options.jsRuntimePath { args += ["--js-runtimes", "deno:" + runtime] }
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
        case .video, .both:
            // Best Compatibility forces MP4. MOV can't hold the AV1/VP9 + Opus that yt-dlp's
            // default sort picks on YouTube (merge or remux fails), so it needs H.264 + AAC too.
            let container = o.compatibilityH264 ? "mp4" : o.container
            let wantsH264 = o.compatibilityH264 || container == "mov"
            let height = "height<=\(o.resolution)"
            if o.type == .video {
                var args = ["-f", "bestvideo[\(height)][acodec=none]", "--remux-video", container]
                if wantsH264 { args += ["-S", "vcodec:h264,lang,quality,res,fps,hdr:12"] }
                return args
            }
            // WebM only holds VP8/VP9/AV1 + Opus/Vorbis; "webm/mkv" lets yt-dlp fall back to
            // MKV instead of failing when a site only offers H.264/AAC.
            var args = [
                "-f", "bestvideo[\(height)]+\(audioFilter)",
                "--merge-output-format", container == "webm" ? "webm/mkv" : container,
            ]
            // yt-dlp's `-t mp4` sort, but keeping our height cap.
            if wantsH264 { args += ["-S", "vcodec:h264,lang,quality,res,fps,hdr:12,acodec:aac"] }
            return args
        }
    }
}
