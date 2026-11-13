//
//  UpdateChecker.swift
//  Downer
//
//  Sparkle 2 does the work: it fetches the appcast, downloads the update, verifies its EdDSA
//  signature, replaces the app and relaunches it. This class is the thin layer between Sparkle and
//  Downer's UI: the Settings group, the "Update available" pill, the menu bar dot and the menu item.
//
//  Behaviour:
//  - On launch (and every 24 h while running) Sparkle checks in the background when the setting is on.
//  - The check made at launch shows Sparkle's update window straight away, but only if a newer version
//    exists. Nothing is shown when Downer is up to date.
//  - A later scheduled check never opens a window on its own (Downer usually sits in the menu bar).
//    It shows the pill and the menu bar dot instead; clicking either brings up Sparkle's window.
//  - "Check now" and "Check for Updates…" are user-initiated and say so when Downer is up to date.
//

import AppKit
import Combine
import Sparkle
import SwiftUI

@MainActor
final class UpdateChecker: NSObject, ObservableObject {
    static let shared = UpdateChecker()

    /// The value in the project before the owner's real key is pasted in. See scripts/make-dmg.sh.
    nonisolated static let placeholderKey = "REPLACE_WITH_SPARKLE_PUBLIC_ED_KEY"
    /// Settings written by the home-made checker that Sparkle replaced.
    nonisolated private static let legacyAutoCheckKey = "autoCheckUpdates"
    nonisolated private static let legacyLastCheckKey = "lastUpdateCheck"

    /// A newer version was found by a scheduled check and is waiting for the person (pill + dot).
    @Published private(set) var updatePending = false
    @Published private(set) var pendingVersion: String?
    @Published private(set) var canCheck = false
    @Published private(set) var lastChecked: Date?
    /// An update has been downloaded and is waiting for the running downloads to finish before Downer relaunches.
    @Published private(set) var installWaitingForDownloads = false
    /// False in builds that still carry the placeholder public key: updates are off so Sparkle
    /// doesn't open an error window on every launch of a development build.
    let isConfigured: Bool

    var automaticChecks: Bool {
        get { updater.automaticallyChecksForUpdates }
        set {
            objectWillChange.send()
            updater.automaticallyChecksForUpdates = newValue
        }
    }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    private var controller: SPUStandardUpdaterController!
    private var updater: SPUUpdater { controller.updater }
    private var cancellables = Set<AnyCancellable>()
    /// True until the first check after launch has finished, whoever started it.
    private var launchCheckPending = true
    /// Sparkle's "continue the relaunch" block while downloads are running. Called at most once.
    private var relaunchBlock: (() -> Void)?

    private override init() {
        isConfigured = Self.isConfigured(key: Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
    }

    /// True when the public key looks like a real one (not empty, whitespace or the project placeholder).
    nonisolated static func isConfigured(key: String?) -> Bool {
        guard let key = key?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return !key.isEmpty && key != placeholderKey
    }

    /// Reads the old Settings switch and removes the legacy keys. Returns the old switch value, or nil
    /// when the person never had one (then Sparkle's own default applies).
    nonisolated static func migrate(defaults: UserDefaults) -> Bool? {
        let old = defaults.object(forKey: legacyAutoCheckKey) as? Bool
        defaults.removeObject(forKey: legacyAutoCheckKey)
        defaults.removeObject(forKey: legacyLastCheckKey)
        return old
    }

    // MARK: Launch

    /// Called once from `applicationDidFinishLaunching`.
    func start() {
        migrateLegacySettings()
        guard isConfigured else { return }

        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.canCheck = $0 }
            .store(in: &cancellables)

        // KVO: the date changes as soon as a check starts, so Settings stays current while it is open.
        updater.publisher(for: \.lastUpdateCheckDate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.lastChecked = $0 }
            .store(in: &cancellables)

        // Continue a postponed relaunch as soon as the last download has finished.
        DownloadManager.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.releaseRelaunchIfIdle() }
            .store(in: &cancellables)

        controller.startUpdater()
        // Sparkle's own cycle only fires once a day has passed, so ask for a check at every launch.
        if updater.automaticallyChecksForUpdates {
            updater.checkForUpdatesInBackground()
        } else {
            launchCheckPending = false
        }
    }

    /// The old Settings switch moves into Sparkle's own preference once, then the key is removed.
    private func migrateLegacySettings() {
        if let old = Self.migrate(defaults: .standard) {
            updater.automaticallyChecksForUpdates = old
        }
    }

    private func releaseRelaunchIfIdle() {
        guard let block = relaunchBlock, !DownloadManager.shared.isActive else { return }
        relaunchBlock = nil
        installWaitingForDownloads = false
        block()
    }

    // MARK: User actions

    /// User-initiated: shows the update window, or "You're up to date".
    func checkForUpdates() {
        guard isConfigured else { return }
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        updater.checkForUpdates()
    }

    /// Brings Sparkle's window for a pending update in front.
    func showPendingUpdate() { checkForUpdates() }

    private func clearPending() {
        updatePending = false
        pendingVersion = nil
    }
}

// MARK: - Sparkle

extension UpdateChecker: SPUUpdaterDelegate {
    nonisolated func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        MainActor.assumeIsolated {
            launchCheckPending = false
        }
    }

    /// Installing relaunches Downer, which would kill running downloads: wait until the queue is idle.
    nonisolated func updater(
        _ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void
    ) -> Bool {
        MainActor.assumeIsolated {
            guard DownloadManager.shared.isActive else { return false }
            relaunchBlock = installHandler
            installWaitingForDownloads = true
            return true
        }
    }
}

extension UpdateChecker: SPUStandardUserDriverDelegate {
    /// Lets Downer decide how a scheduled update is shown (see the file header).
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Scheduled checks only open Sparkle's window at launch; later ones use the pill and the dot.
    ///
    /// Sparkle shows a scheduled alert in a regular app only while it is active, otherwise it waits until
    /// the next activation, which would be silent. `immediateFocus` is true when the check ran just after
    /// launch with the app active (or the Mac was idle), so only then is Sparkle's window left to Sparkle.
    /// Otherwise the pill and the menu bar dot carry it.
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        MainActor.assumeIsolated { launchCheckPending && immediateFocus }
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        MainActor.assumeIsolated {
            if handleShowingUpdate {
                clearPending()
            } else {
                updatePending = true
                pendingVersion = update.displayVersionString
            }
        }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated { clearPending() }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated {
            clearPending()
            // A cancelled session must not keep a stale relaunch block around.
            if !installWaitingForDownloads { relaunchBlock = nil }
        }
    }
}

/// Small capsule shown when a scheduled check found a newer version. Opens Sparkle's update window.
struct UpdateBadge: View {
    @ObservedObject private var updates = UpdateChecker.shared

    var body: some View {
        if updates.installWaitingForDownloads {
            Text("Update will install when downloads finish")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .transition(.opacity)
        } else if updates.updatePending {
            Button("Update available") { updates.showPendingUpdate() }
                .buttonStyle(PillButtonStyle())
                .help(
                    updates.pendingVersion.map { "Downer \($0) is available. Click to review and install." }
                        ?? "A new version of Downer is available."
                )
                .transition(.opacity)
        }
    }
}
