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
    private static let legacyAutoCheckKey = "autoCheckUpdates"
    private static let legacyLastCheckKey = "lastUpdateCheck"

    /// A newer version was found by a scheduled check and is waiting for the person (pill + dot).
    @Published private(set) var updatePending = false
    @Published private(set) var pendingVersion: String?
    @Published private(set) var canCheck = false
    @Published private(set) var lastChecked: Date?
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

    private override init() {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        isConfigured = !key.isEmpty && key != Self.placeholderKey
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
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

        controller.startUpdater()
        lastChecked = updater.lastUpdateCheckDate
        // Sparkle's own cycle only fires once a day has passed, so ask for a check at every launch.
        if updater.automaticallyChecksForUpdates {
            updater.checkForUpdatesInBackground()
        } else {
            launchCheckPending = false
        }
    }

    /// The old Settings switch moves into Sparkle's own preference once, then the key is removed.
    private func migrateLegacySettings() {
        let defaults = UserDefaults.standard
        if let old = defaults.object(forKey: Self.legacyAutoCheckKey) as? Bool {
            updater.automaticallyChecksForUpdates = old
            defaults.removeObject(forKey: Self.legacyAutoCheckKey)
        }
        defaults.removeObject(forKey: Self.legacyLastCheckKey)
    }

    // MARK: User actions

    /// User-initiated: shows the update window, or "You're up to date".
    func checkForUpdates() {
        guard isConfigured else { return }
        NSApp.activate(ignoringOtherApps: true)
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
            lastChecked = updater.lastUpdateCheckDate
        }
    }
}

extension UpdateChecker: SPUStandardUserDriverDelegate {
    /// Lets Downer decide how a scheduled update is shown (see the file header).
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Scheduled checks only open Sparkle's window at launch; later ones use the pill and the dot.
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        MainActor.assumeIsolated { launchCheckPending }
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
        MainActor.assumeIsolated { clearPending() }
    }
}

/// Small capsule shown when a scheduled check found a newer version. Opens Sparkle's update window.
struct UpdateBadge: View {
    @ObservedObject private var updates = UpdateChecker.shared

    var body: some View {
        if updates.updatePending {
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
