# Changelog

Downloads and full notes for every version are on the [Releases](https://github.com/dsameendra/Downer/releases) page.

## 2.2.1

- **Playlist folders.** A whole playlist is saved in a folder named after it. Turn it off in
  **Settings → Downloads** (#20).
- **Cancelling cleans up** the unfinished files it leaves behind. Finished videos are kept.
- **Show in Finder** also appears in the menu bar window when a download finishes.
- **The window remembers its position** and size.

Details: [`docs/release-notes/2.2.1.md`](docs/release-notes/2.2.1.md).

## 2.2.0

- **Video or playlist?** A YouTube link to a video playing inside a playlist or Mix (`watch?v=…&list=…`) asks whether
  you want just the video or the whole list, instead of downloading the whole list (#18). Set a default in
  **Settings → Downloads**.
- **Mixes are never downloaded whole without asking**, and **playlists of 200 or more videos** are confirmed first.
- A long playlist whose look-up runs out of time keeps the titles it found.

Details: [`docs/release-notes/2.2.0.md`](docs/release-notes/2.2.0.md).

## 2.1.0

- **Sign in for videos that need it.** Optional and off by default, with a consent screen first. Downer always tries
  without cookies and only uses your browser's sign-in when a site says it is required.
- **Best Compatibility.** One switch for H.264 + AAC MP4s that play everywhere. It fixes files that play sound but
  show no picture in QuickTime.
- **MOV container**, next to MP4, MKV and WebM. WebM falls back to MKV when a site has nothing WebM can hold.
- **Extra yt-dlp arguments** from a list of common options. Anything else is refused, with the reason shown.
- **deno, recommended for YouTube**, installed and updated from Settings.
- **Update buttons** for `yt-dlp`, `ffmpeg` and `deno`. Tools Downer downloads itself are checked against their
  published checksum.
- **Downer updates itself** with Sparkle, and waits for running downloads to finish first.
- Clearer, shorter error messages that say what to do next. Cancelling a link while it is looked up stops the look-up.
  "HTTP Error 503" is retried automatically.

Details: [`docs/release-notes/2.1.0.md`](docs/release-notes/2.1.0.md).

## 2.0.3

- The panel at the bottom grows to fit **Show in Finder** after a download, instead of letting it spill out.
- The resolution, container and quality pickers are back to the original menus.

## 2.0.2

- **Made for the trackpad.** Swipe up with two fingers on the download tray to open it, down to tuck it away.
- **Swipe a row** sideways to remove, cancel, retry or reveal it. A long swipe does the main action.
- **Drag to reorder** waiting links.
- **Drop links in** from your browser onto the window or the menu bar icon.
- **Glass switcher** for the download type, and swipe gestures in the menu bar popover.
- **Haptics** on a trackpad (can be turned off). Reduce Motion is respected, and every gesture has a click, keyboard or
  VoiceOver equivalent.

## 2.0

- **Liquid Glass design** on macOS 26, a refined material look on macOS 14 and 15, and solid surfaces when Reduce
  Transparency is on.
- **A download queue.** Add videos and playlists while something is already downloading.
- **Playlists done properly**, with one row per video and retry for the ones that failed.
- **Real progress**: a progress bar, percentage, speed and time left.
- **Set up from Settings.** Downer finds `yt-dlp`, `ffmpeg` and `ffprobe`, and can install them.
- **A smarter menu bar icon** and a global shortcut that opens the popover with your copied link filled in.
- **A new layered app icon** and appearance options.
