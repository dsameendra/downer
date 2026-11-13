<div align="center">

<img src="docs/screenshots/app-icon.png" alt="Downer app icon" width="128"/>

# Downer

**A native macOS app for downloading video and audio. Paste a link, add as many more as you like, and let Downer work through them in order.**

Built for macOS 26 with Liquid Glass. Works on macOS 14 and later.

<img src="docs/screenshots/main-dark.png" alt="Downer main window in dark mode" width="300"/>&nbsp;&nbsp;<img src="docs/screenshots/queue-dark.png" alt="Downer download queue with a playlist in progress" width="300"/>

</div>

## What's new in 2.1.0

- **Sign in for videos that need it.** Optional browser sign-in for age-restricted and bot-checked videos. Off by default. See [Signing in](#signing-in-for-age-restricted-or-bot-checked-videos).
- **Best compatibility (H.264).** One switch for files that play in QuickTime and everywhere else. See [Best compatibility](#best-compatibility-h264).
- **Extra yt-dlp arguments.** Add your own options to every download, with unsafe ones refused.
- **deno, recommended for YouTube.** Installed and updated from Settings, and passed to `yt-dlp` when your `yt-dlp` is new enough to use it.
- **Update buttons** for `yt-dlp`, `ffmpeg` and `deno`, and a once-a-day check for new Downer releases.
- **Clearer errors** that say what to do next.

## What's new in 2.0.3

- The panel at the bottom now grows to fit **Show in Finder** after a download, instead of letting it spill out.
- The resolution, container and quality pickers are back to the original menus.

## What's new in 2.0.2

- **Made for the trackpad.** Swipe up with two fingers on the download tray to open it, down to tuck it away; it follows your fingers, glides to rest with the speed of your swipe, and hands over to the list when you reach the top.
- **Swipe a row** sideways with two fingers to remove, cancel, retry or reveal it. A long swipe does the main action.
- **Drag to reorder.** Press and hold a waiting link, then drag it to change when it downloads.
- **Drop links in.** Drag a link from your browser onto the window or the menu bar icon.
- **Glass switcher.** The download type is a glass control you can swipe.
- **Menu bar popover:** swipe up to open the full window, down to dismiss.
- **Haptics.** Subtle feedback on a trackpad (turn it off in Settings). Reduce Motion is respected everywhere. Every gesture also has a click, keyboard or VoiceOver equivalent.

## What's new in 2.0

- **Liquid Glass design.** Real glass on macOS 26 and later, a refined material look on macOS 14 and 15, and solid surfaces when Reduce Transparency is on.
- **A download queue.** Add a video, a playlist, or several of each while something is already downloading. Everything is looked up first, then downloaded one after another.
- **Playlists done properly.** A playlist shows up as a group with one row per video, each with its own progress. Failed videos can be retried on their own.
- **Real progress.** A true progress bar and percentage, speed and time left, instead of raw tool output.
- **Set up from Settings.** Downer finds `yt-dlp`, `ffmpeg` and `ffprobe`, and can install them for you.
- **A smarter menu bar.** A new icon that fills with progress and shows the queue count, plus a global shortcut that opens the popover with your copied link already filled in.
- **A new app icon** built in layers for Liquid Glass, with dark, clear and tinted looks.
- **Appearance options.** Follow the device, or choose light or dark, and turn the background glow on or off.

## Features

### Downloading

- Download **video + audio**, **audio only**, or **video only**.
- Choose the **resolution** (from 240p up to 8K, capped at what the video offers), the **container** (MP4, MKV or WebM), the **audio quality** (best available, or capped at 128, 70 or 50 kbps), and the **audio format** (keep the source, or convert to MP3, AAC or Opus).
- Pick where files are saved. Every choice is remembered, and shared between the window and the menu bar.
- Each queued link keeps the settings it was added with, so changing a setting later never affects links that are already waiting.

### The queue

- **Add at any time.** Paste a link and press Return, or press **Add to Queue**. The field clears so you can paste the next one. Pasting several links at once adds them all.
- **Mix freely.** Single videos, playlists, or any combination. Links that are not valid, or are already in the queue, are ignored politely.
- **One at a time, in order.** Downloads run strictly one after another, so your connection and your disk are never hammered.
- **A tray that comes up from the bottom.** With more than one link, or a playlist, the download area becomes a tray. Drag the handle up to see every link and every video, drag it back down to tuck it away. Tap the header to toggle.
- **Control each item.** Remove a waiting link, cancel the one running, cancel everything, retry what failed, or clear what finished.
- **Automatic retry.** A network hiccup (for example an HTTP error) is retried once on its own. Links that are genuinely unavailable are not.
- **Show in Finder** reveals every file the queue produced.

### Menu bar and shortcut

- Downer lives in the menu bar. Click the icon for a compact popover with a link field and a Download button.
- Set a **global shortcut** in Settings. Copy a link anywhere, press the shortcut, and the popover opens with the link already filled in. Press Return to start.

<div align="center">
<img src="docs/screenshots/popover-dark.png" alt="The menu bar popover with a copied link filled in" width="320"/>
</div>

| Menu bar icon | Meaning |
|---|---|
| Double chevron | Idle |
| Ring with a percentage | Downloading one video |
| Ring with `3/12` | Downloading from a queue or a playlist (video 3 of 12) |
| Check mark | Finished (shown for a couple of seconds) |
| Orange dot | Something needs attention: a tool is missing, or a download failed |

<div align="center">
<img src="docs/screenshots/menubar-icons.png" alt="Menu bar icon states on a dark and a light menu bar" width="560"/>
</div>

### Settings

<div align="center">
<img src="docs/screenshots/settings-dark.png" alt="Downer settings" width="300"/>
</div>

- **Appearance:** Device, Light or Dark, and an optional background glow.
- **Global shortcut:** record any key combination.
- **Sign-in (browser cookies):** optional browser sign-in, described [above](#signing-in-for-age-restricted-or-bot-checked-videos).
- **Advanced:** extra `yt-dlp` arguments.
- **Updates:** **Check for updates automatically** checks GitHub for a new Downer release at most once a day, and can be turned off. **Check now** does it on demand. Downer only contacts GitHub, and never downloads or installs anything by itself: **View release** opens the page.
- **Requirements:** shows whether `yt-dlp`, `ffmpeg`, `ffprobe` and `deno` are installed, and their versions. Missing tools have an **Install** button, and installed ones an **Update** button (tools installed another way show "Manual").
  - `deno` is a JavaScript runtime, **recommended for YouTube**. Without it some YouTube videos may fail or offer fewer formats. Downer passes it to `yt-dlp` automatically, but only when your `yt-dlp` is 2025.11.12 or newer, so press **Update** on `yt-dlp` if needed.
  - With Homebrew installed, Downer runs `brew install` for you.
  - Without Homebrew, `yt-dlp` and `deno` are downloaded from their official releases into Downer's own folder. `ffmpeg` needs Homebrew, and Downer will tell you so.
  - Already installed somewhere else? Use **Browse…** to point Downer at it.

### Signing in for age-restricted or bot-checked videos

Some videos need a signed-in session, for example YouTube's age check and bot check. Downer can let `yt-dlp` use your browser's sign-in for those.

- It is **off by default**. Turn it on in **Settings → Sign-in (browser cookies)** (**Sign in with a browser**), pick a browser, and read the consent screen (also behind **What does this do?**).
- Downer **always tries without cookies first**. The chosen browser's cookies are only used when a site says sign-in is required.
- `yt-dlp` reads the browser's cookie store on your Mac, and the cookies are only sent to the site you are downloading from.
- Downer never saves, copies, uploads or logs your cookies, and never sees your password.
- macOS may ask for permission, depending on the browser:
  - **Chrome, Brave, Edge, Chromium, Vivaldi, Opera:** macOS asks once to let Downer use the browser's "Safe Storage" item from your Keychain, which is how the cookies are decrypted.
  - **Safari:** its cookies are protected, so you must grant Downer Full Disk Access yourself in System Settings → Privacy & Security. Downer won't ask for it.
  - **Firefox:** nothing extra.
- Using your account with a downloader can lead YouTube to rate-limit or flag it. A secondary account is safer.
- Turn it off any time in the same place. It takes effect straight away, including for links already in the queue.

### Best compatibility (H.264)

Turn on **Best compatibility (H.264)** under the pickers to prefer H.264 video (and AAC audio) in an MP4. These files play in QuickTime, on iPhones and almost anywhere else. It fixes the "audio but no picture" problem in QuickTime, which happens when a YouTube MP4 holds AV1 video or Opus audio that QuickTime cannot show.

- The container is fixed to MP4 while it is on.
- On YouTube, H.264 stops at 1080p, so higher resolutions are capped (Downer says so).
- Files are usually larger than the AV1 or VP9 alternatives.

### Extra yt-dlp arguments

**Settings → Advanced → Extra yt-dlp arguments** takes any options `yt-dlp` accepts, for example `--limit-rate 2M`, and adds them to every download.

- They come **after** Downer's own format options, so they can override them.
- Quotes and backslashes work as in a shell.
- Arguments that would break Downer or put you at risk are refused, with the reason shown: ones Downer manages (output names and folders, progress, quiet mode, the ffmpeg location), ones that stop anything downloading (`--simulate`, `--skip-download`, the JSON dumps), ones that run commands (`--exec`), ones that touch cookies (use the Sign-in setting instead, and `--verbose` or `--print-traffic`, which can print them), and `--config-locations`. Abbreviated forms (such as `--verb`) and bundled short flags (such as `-qv`) are refused too.

## Screenshots

<table align="center">
  <tr>
    <td align="center"><img src="docs/screenshots/main-light.png" width="280" alt="Main window, light"/><br/>Light mode</td>
    <td align="center"><img src="docs/screenshots/queue-peek.png" width="280" alt="Queue tray peeking"/><br/>The tray, tucked away</td>
    <td align="center"><img src="docs/screenshots/queue-light.png" width="280" alt="Queue tray open, light"/><br/>The tray, open, in light mode</td>
  </tr>
</table>

## Using Downer

1. Open **Downer**, or click its menu bar icon.
2. Paste a video or playlist link and press **Return**.
3. Choose **Video + Audio**, **Audio Only** or **Video Only**, and the quality and format you want.
4. While it downloads, paste more links. They join the queue.
5. Drag the tray handle up whenever you want to see what is happening to each video.
6. When the queue finishes, press **Show in Finder**.

Closing the window hides it (and the Dock icon). Click the menu bar icon to bring it back, or right-click it for **Open Downer** and **Quit Downer**.

## Installation

### 1. Download and install

Head to the [GitHub Releases](https://github.com/dsameendra/Downer/releases) page and download the latest `.dmg`.

- Open the `.dmg`. A window appears with Downer and your Applications folder: drag **Downer** onto **Applications**.
- Open **Settings → Requirements** and press **Install** next to anything that is missing. (`ffmpeg` needs [Homebrew](https://brew.sh). You can also run `brew install yt-dlp ffmpeg` yourself.)

### 2. Allow the app to run

macOS may block the app, saying:

> "Downer.app can't be opened."

This happens because the app is not signed with a paid Apple Developer account. You can allow it with Terminal:

1. Sign the app locally with an ad-hoc signature:
   ```bash
   codesign --force --deep --sign - /Applications/Downer.app
   ```
2. Remove the quarantine flag so macOS treats it as safe:
   ```bash
   xattr -dr com.apple.quarantine /Applications/Downer.app
   ```

### 3. Folder access

The first time Downer saves into a protected folder such as Downloads, macOS asks whether to allow it. Choose **Allow**. You can change this later in **System Settings → Privacy & Security → Files & Folders**.

## Troubleshooting

| Problem | What to try |
|---|---|
| A "Setup needed" banner appears | Open Settings → Requirements and press Install next to what is missing. |
| **Install** is greyed out for ffmpeg | Install [Homebrew](https://brew.sh) first, then try again. |
| A video failed with an HTTP error | Downer retries these once automatically. If it still fails, press **Retry** on the row. |
| A video says "unavailable" | The video is private, removed or restricted in your region. Retrying will not help. |
| Nothing is saved | Check the **Save to** folder exists, and that Downer has permission to write to it. |
| Downloads suddenly stop working for a site | Press **Update** next to `yt-dlp` in Settings → Requirements (sites change often). |
| YouTube says to sign in or confirm you are not a bot | Turn on **Sign-in (browser cookies)** in Settings, or try again later. |
| A MP4 plays sound but shows no picture in QuickTime | Turn on **Best compatibility (H.264)**. |

## Building from source

### Requirements

- macOS 14 or later to run. Xcode 26 or later to build, so the Liquid Glass APIs are available.
- `yt-dlp`, `ffmpeg` and `ffprobe` installed anywhere on disk, or installed from Downer's Settings. `deno` is recommended for YouTube.

### Steps

1. Clone the repository:
   ```bash
   git clone https://github.com/dsameendra/Downer.git
   cd Downer
   ```
2. Open `Downer.xcodeproj` in Xcode. The [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) package is fetched automatically.
3. Choose your own signing team: select the **Downer** target, open **Signing & Capabilities**, and pick your team. Automatic signing is enough for local builds.
4. Build and run.

### Installing a local build

1. In Xcode choose **Product → Archive**.
2. In the Organizer choose **Distribute App → Custom → Copy App**.
3. Copy the exported `Downer.app` into `/Applications`.

### Making a release build

```bash
./scripts/make-dmg.sh
```

This builds a universal Release app, signs it ad hoc, draws the installer window and writes `dist/Downer-<version>.dmg` with a checksum next to it. It needs Xcode and Python 3; the DMG tool is installed into `dist/.venv` the first time.

Updates are delivered by [Sparkle](https://sparkle-project.org). Setting it up once:

1. Run `generate_keys` from the Sparkle package (after one Xcode build it is at `<DerivedData>/Downer-*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys`). It stores the private key in your login Keychain and prints the public key.
2. Paste the public key into `DOWNER_SU_PUBLIC_ED_KEY` in `Downer.xcodeproj` (the app target's build settings). `make-dmg.sh` refuses to build while it is still the placeholder.
3. Back up the private key (`generate_keys -x key-file`) somewhere safe. Without it, installed copies can never be updated.

For every release the script also signs the DMG with that key and writes `dist/appcast.xml`. Upload the DMG, its `.sha256` and `appcast.xml` to the GitHub release `v<version>`; installed copies read `releases/latest/download/appcast.xml`. Raise `CURRENT_PROJECT_VERSION` for every release: Sparkle compares that number, not the version name. Set `SPARKLE_ED_KEY_FILE` to sign with an exported key file instead of the Keychain.

### How it is put together

| File | Role |
|---|---|
| `DownloadManager.swift` | The queue: looks links up, runs `yt-dlp` one at a time, turns its output into progress |
| `DownloadJob.swift` | One queued link and the settings it was added with |
| `PlaylistModel.swift` | Follows a playlist run line by line (current video, progress, failures) |
| `QueueTray.swift` | The draggable tray with every link and video |
| `YtDlpArguments.swift` | Builds every `yt-dlp` command line, for look-ups and downloads |
| `ExtraArguments.swift` | Splits and checks your extra `yt-dlp` arguments |
| `CookieBrowser.swift`, `CookieConsentSheet.swift` | The opt-in browser sign-in and its consent screen |
| `ErrorHints.swift` | Turns `yt-dlp` errors into a next step |
| `UpdateChecker.swift` | The daily check for a new Downer release |
| `DependencyManager.swift` | Finds, installs and updates `yt-dlp`, `ffmpeg`, `ffprobe` and `deno` |
| `DesignSystem.swift` | Liquid Glass, materials, motion, buttons and window chrome |
| `MenuBarIcon.swift` | The menu bar icon and its states, drawn in code |
| `Downer.icon` | The layered app icon |
| `scripts/make-dmg.sh` | Builds the signed, universal installer DMG (`scripts/dmg` holds its window design) |

See [`PRODUCT.md`](PRODUCT.md) for who Downer is for and [`DESIGN.md`](DESIGN.md) for the design decisions behind it.

## Disclaimer

This tool is intended solely for personal use and educational or research purposes.

Downloading videos from YouTube may violate their [Terms of Service](https://www.youtube.com/t/terms) unless the video has an explicit download button or the content is licensed in a way that permits downloading.

By using this app, **you assume full responsibility** for any content you download and how you use it. The developer does not condone or support any misuse of this tool to infringe upon copyrights or violate platform rules.

---

Built with ❤️ using [yt-dlp](https://github.com/yt-dlp/yt-dlp) and [ffmpeg](https://www.ffmpeg.org). Huge credit to the amazing developers behind these tools.
