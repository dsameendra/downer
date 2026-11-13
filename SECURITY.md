# Security Policy

## Supported versions

Only the latest release of Downer receives fixes.

| Version | Supported |
|---|---|
| 2.1.x | Yes |
| 2.0.x and older | No |

## Reporting a vulnerability

Please do not open a public issue for a security problem.

Use GitHub's private reporting instead: go to the **Security** tab of this repository and choose **Report a vulnerability**. Include what you found, how to reproduce it, and which version of Downer you used.

You can expect a first reply within a week. Downer runs `yt-dlp` and `ffmpeg` on your machine with the links you give it, so reports about how those tools are launched are especially welcome. The same goes for the optional browser sign-in, which lets `yt-dlp` read a browser's cookies, for the allowlist that checks extra `yt-dlp` arguments, and for the update mechanism: Downer 2.1.x updates itself with Sparkle, and every update must carry a valid EdDSA signature from the project's key.
