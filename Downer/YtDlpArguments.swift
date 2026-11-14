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
        case download(pathFile: String, ffmpegDirectory: String, outputFolder: String, only: [Int]?)
    }

    /// Order: format args (download only), extra args, cookie flags, Downer's own flags (downloads also
    /// cancel info-json writing), the link. The look-up only gets the extra args that change how a site
    /// is reached (see `ExtraArguments.forLookup`); filters, waits and format choices are for the download.
    ///
    /// yt-dlp also reads config files (~/.config/yt-dlp/config, ~/yt-dlp.conf, ...) that could turn
    /// cookies on whatever Sign-in says. Downer's flags come last, so they win: with Sign-in off,
    /// `--no-cookies --no-cookies-from-browser` cancel any cookie setting from a config; with it on,
    /// `--no-cookies` first stops a config's `--cookies FILE` (which yt-dlp would also write back to).
    nonisolated static func build(
        for options: JobOptions, purpose: Purpose, useCookies: Bool, url: String
    ) -> [String] {
        var args: [String] = []
        if case .download = purpose {
            args += formatArguments(for: options)
            args += options.extraArguments
        } else {
            args += ExtraArguments.forLookup(options.extraArguments)
        }
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
        case .download(let pathFile, let ffmpegDirectory, let outputFolder, let only):
            // A config file's --write-info-json / --embed-info-json would write the `cookies` field of the
            // info dict to disk when Sign-in is on, so cancel them for every download.
            args += ["--no-write-info-json", "--no-embed-info-json"]
            // yt-dlp runs in a private empty folder (see RunDirectory), so every output template is an
            // absolute path in the destination: a relative one would land in the folder that is deleted.
            // Thumbnails, subtitles and playlist files follow the default template; only chapters
            // (--split-chapters) have a template of their own. The names are yt-dlp's own defaults.
            // (Not `-P`: yt-dlp trims spaces from it, which would change a folder like "Videos ".)
            args += ["-o", outputTemplate(folder: outputFolder)]
            args += ["-o", "chapter:" + outputTemplate(folder: outputFolder, file: chapterFileTemplate)]
            args += ["--print-to-file", "after_move:filepath", pathFile]
            args += ["--newline", "--ffmpeg-location", ffmpegDirectory]
            args += items(only)
        }
        args.append(url)
        return args
    }

    /// `file` (an output template) inside the destination folder. A `%` in the folder's path would start
    /// a template field, so it is doubled.
    nonisolated static func outputTemplate(folder: String, file: String = defaultFileTemplate) -> String {
        let base = folder.hasSuffix("/") ? String(folder.dropLast()) : folder
        return base.replacingOccurrences(of: "%", with: "%%") + "/" + file
    }

    /// yt-dlp's default names (`DEFAULT_OUTTMPL` in yt-dlp's utils).
    nonisolated static let defaultFileTemplate = "%(title)s [%(id)s].%(ext)s"
    nonisolated static let chapterFileTemplate = "%(title)s - %(section_number)03d %(section_title)s [%(id)s].%(ext)s"

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

/// yt-dlp reads `yt-dlp.conf` from its working directory as its "Home" config, which would let a stray
/// file in the download folder run commands (`--exec`) behind the extra-arguments allowlist. So every
/// yt-dlp process runs in a private, empty folder that only Downer can write to, and is removed afterwards.
enum RunDirectory {
    nonisolated static func make() -> URL? {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("Downer-run-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            return url
        } catch { return nil }
    }

    nonisolated static func remove(_ url: URL?) {
        if let url { try? FileManager.default.removeItem(at: url) }
    }
}
