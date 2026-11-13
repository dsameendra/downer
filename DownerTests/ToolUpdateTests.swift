//
//  ToolUpdateTests.swift
//  DownerTests
//
//  Which way each tool is updated, and how deno reaches yt-dlp.
//

import Foundation
import Testing
@testable import Downer

struct ToolUpdateTests {
    let managed = "/Users/x/Library/Application Support/Downer/bin"

    func method(_ tool: Tool, _ path: String) -> UpdateMethod {
        DependencyManager.updateMethod(for: tool, resolvedPath: path, managedDir: managed)
    }

    @Test func homebrewPathsUpgradeThroughBrew() {
        // judged after symlinks are resolved: bin/ and opt/ entries lead into the Cellar
        #expect(method(.ytDlp, "/opt/homebrew/Cellar/yt-dlp/2026.8.19_1/libexec/bin/yt-dlp") == .brew(formula: "yt-dlp"))
        #expect(method(.ytDlp, "/usr/local/Cellar/yt-dlp/2025.1.1/bin/yt-dlp") == .brew(formula: "yt-dlp"))
        #expect(method(.deno, "/opt/homebrew/Cellar/deno/2.1.4/bin/deno") == .brew(formula: "deno"))
    }

    @Test func installSavesLocatedPathsBeforeQueueResumes() throws {
        let suite = "downer-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("/opt/homebrew/bin/yt-dlp", forKey: Tool.ytDlp.defaultsKey)  // stale
        defaults.set("/old/deno", forKey: Tool.deno.defaultsKey)
        let located: [Tool: String] = [
            .ytDlp: "/Users/x/Library/Application Support/Downer/bin/yt-dlp",
            .deno: "/new/deno", .ffmpeg: "/b/ffmpeg", .ffprobe: "/b/ffprobe",
        ]
        DependencyManager.persistLocatedPaths(for: .ytDlp, defaults: defaults) { located[$0] }
        #expect(defaults.string(forKey: Tool.ytDlp.defaultsKey) == located[.ytDlp])
        #expect(defaults.string(forKey: Tool.deno.defaultsKey) == "/old/deno")  // other groups untouched
        // ffprobe installs with ffmpeg
        DependencyManager.persistLocatedPaths(for: .ffmpeg, defaults: defaults) { located[$0] }
        #expect(defaults.string(forKey: Tool.ffmpeg.defaultsKey) == "/b/ffmpeg")
        #expect(defaults.string(forKey: Tool.ffprobe.defaultsKey) == "/b/ffprobe")
        // nothing found: keep what was there
        DependencyManager.persistLocatedPaths(for: .deno, defaults: defaults) { _ in nil }
        #expect(defaults.string(forKey: Tool.deno.defaultsKey) == "/old/deno")
    }

    @Test func ffmpegAndFfprobeShareAFormula() {
        #expect(method(.ffmpeg, "/opt/homebrew/Cellar/ffmpeg/7.1/bin/ffmpeg") == .brew(formula: "ffmpeg"))
        #expect(method(.ffprobe, "/opt/homebrew/Cellar/ffmpeg/7.1/bin/ffprobe") == .brew(formula: "ffmpeg"))
    }

    @Test func nonBrewThingsUnderHomebrewAreManual() {
        // an unresolved path, or a pip / npm / hand-copied binary, is not brew's to upgrade
        #expect(method(.ytDlp, "/opt/homebrew/bin/yt-dlp") == .manual)
        #expect(method(.ytDlp, "/opt/homebrew/lib/python3.14/site-packages/bin/yt-dlp") == .manual)
        #expect(method(.deno, "/opt/homebrew/lib/node_modules/deno/bin/deno") == .manual)
        #expect(method(.ytDlp, "/opt/homebrew/Cellar") == .manual)
        #expect(method(.ytDlp, "/opt/homebrew/Cellar/yt-dlp") == .manual)
        #expect(method(.ytDlp, "/opt/homebrew/Cellar/../bin/yt-dlp") == .manual)
        #expect(method(.ytDlp, "/opt/homebrew/Cellar/-evil/1/bin/yt-dlp") == .manual)
    }

    @Test func brewFormulaComesFromTheCellarFolder() {
        #expect(DependencyManager.brewFormula(inResolvedPath: "/opt/homebrew/Cellar/ffmpeg@7/7.1/bin/ffmpeg") == "ffmpeg@7")
        #expect(DependencyManager.brewFormula(inResolvedPath: "/home/linuxbrew/.linuxbrew/Cellar/deno/2/bin/deno") == "deno")
        #expect(DependencyManager.brewFormula(inResolvedPath: "/Users/x/Cellar/deno/2/bin/deno") == nil)
    }

    @Test func managedBinariesUpdateThemselves() {
        #expect(method(.ytDlp, managed + "/yt-dlp") == .selfUpdate(args: ["-U"]))
        #expect(method(.deno, managed + "/deno") == .selfUpdate(args: ["upgrade"]))
        #expect(method(.ffmpeg, managed + "/ffmpeg") == .manual)
    }

    @Test func otherPathsAreManual() {
        #expect(method(.ytDlp, "/Users/x/bin/yt-dlp") == .manual)
        #expect(method(.deno, "/Users/x/.deno/bin/deno") == .manual)
        #expect(method(.ytDlp, "/usr/local/bin/yt-dlp") == .manual)  // unresolved: not known to be brew
        #expect(method(.ytDlp, managed + "-other/yt-dlp") == .manual)
    }

    @Test func denoIsRecommendedNotRequired() {
        #expect(!Tool.deno.isRequired)
        #expect(Tool.ytDlp.isRequired && Tool.ffmpeg.isRequired && Tool.ffprobe.isRequired)
        #expect(Tool.deno.installGroup == .deno)
        #expect(Tool.ffprobe.installGroup == .ffmpeg)
    }

    func options(js: String?) -> JobOptions {
        JobOptions(
            type: .both, resolution: "1080", container: "mp4", audioQuality: "source",
            audioFormat: "opus", folder: URL(fileURLWithPath: "/tmp"), jsRuntimePath: js)
    }

    @Test func jsRuntimeIsPassedToProbeAndDownload() {
        let o = options(js: "/opt/homebrew/bin/deno")
        let probe = YtDlpArguments.build(for: o, purpose: .probe(only: nil), useCookies: false, url: "u")
        let dl = YtDlpArguments.build(
            for: o, purpose: .download(pathFile: "/p", ffmpegDirectory: "/f", outputFolder: "/o", only: nil),
            useCookies: false, url: "u")
        for args in [probe, dl] {
            let i = args.firstIndex(of: "--js-runtimes")
            #expect(i != nil)
            #expect(args[i! + 1] == "deno:/opt/homebrew/bin/deno")
            #expect(args.last == "u")
        }
    }

    @Test func noRuntimeMeansNoFlag() {
        let args = YtDlpArguments.build(
            for: options(js: nil), purpose: .probe(only: nil), useCookies: false, url: "u")
        #expect(!args.contains("--js-runtimes"))
    }

    // MARK: Update runs

    @Test func denoFromTheInstallScriptUpgradesItself() {
        let m = DependencyManager.updateMethod(
            for: .deno, resolvedPath: "/Users/x/.deno/bin/deno", managedDir: managed, home: "/Users/x")
        #expect(m == .selfUpdate(args: ["upgrade"]))
        let other = DependencyManager.updateMethod(
            for: .ytDlp, resolvedPath: "/Users/x/.deno/bin/yt-dlp", managedDir: managed, home: "/Users/x")
        #expect(other == .manual)
    }

    @Test func updateWaitsForDownloads() {
        #expect(DependencyManager.canUpdate(downloadsActive: false, installing: [], tool: .ytDlp))
        #expect(!DependencyManager.canUpdate(downloadsActive: true, installing: [], tool: .ytDlp))
        #expect(!DependencyManager.canUpdate(downloadsActive: true, installing: [], tool: .deno))
        #expect(!DependencyManager.canUpdate(downloadsActive: false, installing: [.ffmpeg], tool: .ffprobe))
        #expect(DependencyManager.canUpdate(downloadsActive: false, installing: [.ffmpeg], tool: .ytDlp))
    }

    // real output captured from yt-dlp 2025.10.22 -U and deno 2.4.0 upgrade
    let ytDlpUpdated = """
        Current version: stable@2025.10.22 from yt-dlp/yt-dlp
        Latest version: stable@2026.10.26 from yt-dlp/yt-dlp
        Updating to stable@2026.10.26 from yt-dlp/yt-dlp ...
        Updated yt-dlp to stable@2026.10.26 from yt-dlp/yt-dlp
        """
    let denoUpgraded =
        "Current Deno version: v2.4.0\n\u{1B}[0m\u{1B}[38;5;245mLooking up stable version\u{1B}[0m\n\n"
        + "Upgraded successfully to Deno \u{1B}[0m\u{1B}[32mv2.9.8\u{1B}[0m \u{1B}[0m\u{1B}[38;5;245m(stable)\u{1B}[0m\n"

    @Test func successfulRunsAreNotFailures() {
        #expect(DependencyManager.selfUpdateFailure(code: 0, output: ytDlpUpdated) == nil)
        #expect(DependencyManager.selfUpdateFailure(code: 0, output: denoUpgraded) == nil)
        #expect(DependencyManager.selfUpdateFailure(code: 0, output: "") == nil)
    }

    @Test func failedRunsExplainThemselves() {
        let offline = "Current version: stable@2025.10.22\nERROR: Unable to obtain version info (offline)\n"
        #expect(DependencyManager.selfUpdateFailure(code: 1, output: offline) == "ERROR: Unable to obtain version info (offline)")
        // exit 0 with an ERROR line is still a failure
        #expect(DependencyManager.selfUpdateFailure(code: 0, output: offline) == "Unable to obtain version info (offline)")
        #expect(DependencyManager.selfUpdateFailure(code: 2, output: "") == "(exit 2)")
    }

    @Test func colourCodesAreStripped() {
        #expect(DependencyManager.lastMessage(in: denoUpgraded) == "Upgraded successfully to Deno v2.9.8 (stable)")
        #expect(DependencyManager.lastMessage(in: "  \n\n") == nil)
    }

    @Test func noticeComparesVersionsBeforeAndAfter() {
        #expect(DependencyManager.updateNotice(title: "yt-dlp", before: "2025.10.22", after: "2026.10.26") == "yt-dlp updated to 2026.10.26")
        #expect(DependencyManager.updateNotice(title: "deno", before: "2.9.8", after: "2.9.8") == "deno is already up to date")
        #expect(DependencyManager.updateNotice(title: "ffmpeg", before: nil, after: "9.0") == "ffmpeg updated to 9.0")
    }

    @Test func brewGetsAUsableEnvironmentFromABareGuiLaunch() {
        let bare = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        let up = DependencyManager.processEnvironment(base: bare, brewEnvironment: false)
        #expect(up["HOMEBREW_NO_AUTO_UPDATE"] == nil)  // an upgrade must see new releases
        #expect(up["NO_COLOR"] == "1")
        #expect(up["PATH"]!.hasPrefix("/usr/bin:/bin:/usr/sbin:/sbin"))
        #expect(up["PATH"]!.contains("/opt/homebrew/bin"))
        #expect(up["HOME"] != nil)
        let install = DependencyManager.processEnvironment(base: [:], brewEnvironment: true)
        #expect(install["HOMEBREW_NO_AUTO_UPDATE"] == "1")
        #expect(install["PATH"]!.contains("/usr/bin"))
    }
}

/// The Requirements pill must fit next to Update and Browse…, so an installed tool shows just its version.
struct RequirementStatusTextTests {
    func text(installed: Bool = true, version: String? = nil, busy: Bool = false, checked: Bool = true, required: Bool = true) -> String {
        SettingsView.statusText(installed: installed, version: version, busy: busy, checkedOnce: checked, required: required)
    }

    @Test func installedShowsOnlyTheVersion() {
        #expect(text(version: "2026.10.26") == "2026.10.26")
        #expect(text(version: "9.0.2") == "9.0.2")
        #expect(text(version: nil) == "Installed")
    }

    @Test func otherStates() {
        #expect(text(installed: false, checked: false) == "Checking…")
        #expect(text(installed: false, required: true) == "Not found")
        #expect(text(installed: false, required: false) == "Recommended")
        #expect(text(version: "1.0", busy: true) == "Working…")
    }
}
