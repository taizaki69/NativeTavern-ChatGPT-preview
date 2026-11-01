NativeTavern ChatGPT preview, version 0.1.17 build 47.

This update refreshes the app's look and fixes everyday annoyances. Every screen now follows the selected theme: light themes no longer show light-on-light text or dark navy panels, and each built-in theme builds a full Material 3 color scheme with readable text on its accent colors. **Follow system appearance** (Settings → Theme) switches between a chosen light and dark theme with iOS dark mode.

New: unsent text is kept per chat and shown as **Draft** on the chat list; a **jump to latest** button appears in long chats; swipe a chat left to delete it; optional haptic feedback; characters without an avatar get a stable color and initial. Settings and AI Configuration are grouped into cards, the Play tab uses tinted cards, and chat bubbles have a new shape.

Fixed: Retry and delete on the chat list now refresh it, and last-message previews update after chatting. Timestamps follow calendar days and the 12/24-hour setting. **Confirm before deleting** now actually controls chat and message deletion; the inert auto-save switch was removed. Invalid custom-theme colors can no longer break the app, the active custom theme is editable, and long model or character names no longer overflow.

Tests use synthetic data and local/mock services, without owner API credentials. Locally, **707 Flutter tests passed, 2 skipped**, with zero analysis errors and the repository's format, Live2D and mobile development gates passing. On the macOS runner, analysis, the full Flutter suite, native development gates, device compilation and unsigned packaging all succeeded.

[Successful build](https://github.com/taizaki69/NativeTavern-ChatGPT-preview/actions/runs/41312448322). [Exact compiled source](https://github.com/taizaki69/NativeTavern-ChatGPT-preview/tree/dd24fd393a9ec96b0b8964b402dc314aa62bd578).
IPA: `NativeTavern_ChatGPT_v0.1.17+47_unsigned.ipa`.
SHA-256: `a620107e8c7082cd55398e4c27a5d47a43f6e9a67b68409d82d9e9ea7442a484`.
`build_ios.sh` validated both the built app and the re-extracted IPA: bundle `com.miaomiaoxworld.nativetavern`, version 0.1.17 (47), iOS 15.0+, arm64 device binary, no provisioning profile, native Live2D and Spine markers. Compare the downloaded file with the `.sha256` companion before re-signing.

The official ChatGPT provider, existing response transport and provider caching are unchanged. Completed live Responses inference, account/mobile admission and re-signed device behavior remain unverified. No Codex bridge or API-key fallback was added.

This is an unsigned device app for iOS 15 or later. Back up existing data, then re-sign the whole app with your usual sideload tool. Your theme, connections, models and chats carry over; drafts start empty.
