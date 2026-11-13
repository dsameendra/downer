//
//  CookieConsentSheet.swift
//  Downer
//
//  What the person sees before browser sign-in is turned on. Only "Turn on" here
//  enables it; "Cancel" leaves it off. Opened again read-only from Settings.
//

import AppKit
import SwiftUI

/// A menu of browsers; ones that are not installed are shown but cannot be picked.
/// A nil selection shows "Choose a browser" (nothing is used until one is picked).
struct CookieBrowserMenu: View {
    @Binding var selection: CookieBrowser?

    var body: some View {
        Menu {
            ForEach(CookieBrowser.allCases) { browser in
                Button {
                    selection = browser
                } label: {
                    if browser == selection {
                        Label(browser.displayName, systemImage: "checkmark")
                    } else {
                        Text(browser.isInstalled ? browser.displayName : "\(browser.displayName) (not installed)")
                    }
                }
                .disabled(!browser.isInstalled)
            }
        } label: {
            Text(selection?.displayName ?? "Choose a browser")
        }
        .menuStyle(.button)
        .fixedSize()
    }
}

/// The Safari permission, explained without looking: a button to the right Settings pane and the
/// relaunch note. Nothing is probed here, so Safari's folder is not touched before Sign-in is on.
struct FullDiskAccessHelp: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Open Full Disk Access Settings") { FullDiskAccess.openSettings() }
                .buttonStyle(PillButtonStyle())
            Text(FullDiskAccess.relaunchNote)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "Full Disk Access: granted / not granted" for Safari. Only shown in Settings once Sign-in is on.
/// Checked when it appears and whenever the app becomes active (for example after System Settings).
struct FullDiskAccessRow: View {
    @State private var status: FullDiskAccess.Status?

    private var granted: Bool { status == .granted }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let status {
                HStack(spacing: 6) {
                    Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(granted ? Color.green : Color.orange)
                    Text(label(status))
                        .font(.system(size: 12, weight: .medium))
                }
                if !granted { FullDiskAccessHelp() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private func refresh() {
        Task { status = await Task.detached { FullDiskAccess.check() }.value }
    }

    private func label(_ status: FullDiskAccess.Status) -> String {
        switch status {
        case .granted: "Full Disk Access: granted ✓"
        case .denied: "Full Disk Access: not granted"
        case .noCookieFile: "Safari's cookie file wasn't found. Open Safari once."
        }
    }
}

struct CookieConsentSheet: View {
    @State var browser: CookieBrowser
    /// Read-only: just the explanation, with a Done button.
    var readOnly = false
    var onTurnOn: (CookieBrowser) -> Void = { _ in }
    var onClose: () -> Void

    private var canTurnOn: Bool { browser.isInstalled }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Sign in with your browser")
                        .font(.system(size: 16, weight: .semibold))

                    point(
                        "What it does",
                        "Some videos need you to be signed in — for example YouTube's bot check and age check. With this on, yt-dlp can use the cookies from a browser you choose, so it downloads as your signed-in session.")
                    point(
                        "When",
                        "Downer always tries without cookies first. Your browser's cookies are only used when a site says sign-in is required.")
                    point(
                        "What is read",
                        "yt-dlp reads that browser's cookie store on this Mac. Cookies are only sent to the site you're downloading from.")
                    point(
                        "What Downer doesn't do",
                        "Downer never saves, copies, uploads or logs your cookies, and never sees your password.")

                    HStack {
                        Text("Browser")
                            .font(.system(size: 13))
                        Spacer(minLength: 0)
                        if readOnly {
                            Text(browser.displayName).foregroundStyle(.secondary)
                        } else {
                            CookieBrowserMenu(
                                selection: Binding(
                                    get: { browser }, set: { if let chosen = $0 { browser = chosen } }))
                        }
                    }
                    point("macOS prompts", browser.permissionNote)
                    if browser == .safari { FullDiskAccessHelp() }

                    point(
                        "Account risk",
                        "Using your account with a downloader can lead YouTube to rate-limit or flag it. A secondary account is safer.")

                    Text("You can turn this off any time here; it applies from the next download.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
            }
            .scrollIndicators(.automatic)

            Divider().opacity(0.6)
            HStack(spacing: 10) {
                if !readOnly && CookieBrowser.firstInstalled == nil {
                    Text("No supported browser found.")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                }
                Spacer()
                if readOnly {
                    Button("Done", action: onClose)
                        .buttonStyle(PrimaryPillButtonStyle())
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel", action: onClose)
                        .buttonStyle(PillButtonStyle())
                        .keyboardShortcut(.cancelAction)
                    Button("Turn on") { onTurnOn(browser) }
                        .buttonStyle(PrimaryPillButtonStyle())
                        .disabled(!canTurnOn)
                }
            }
            .padding(14)
        }
        .frame(width: 400, height: 520)
    }

    private func point(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
