# Headroom

A tiny macOS menu bar app (~390 KB) that shows how much of your Claude plan you've used: your 5-hour session and weekly limits, with reset times.

```
✳︎ 54% · 8%
```

## Install

Requires macOS 13+ and [Claude Code](https://claude.com/claude-code) logged in with your Claude subscription.

1. Download the latest `Headroom-x.y.dmg` from [Releases](https://github.com/CaptainDiego/headroom/releases/latest).
2. Open it and drag **Headroom** into **Applications**.
3. Launch Headroom. The app isn't notarized by Apple, so the first launch is blocked: open **System Settings → Privacy & Security**, scroll down and click **Open Anyway**. (Or run `xattr -dr com.apple.quarantine /Applications/Headroom.app`.)

**Build from source** (needs the Xcode Command Line Tools):

```sh
git clone https://github.com/CaptainDiego/headroom && cd headroom
./build.sh install
```

**Raycast (optional):** add the `raycast/` folder under Settings → Extensions → Script Commands to see usage inline in Raycast.

## Privacy

- Reads the OAuth token Claude Code already stores in your Keychain (via `/usr/bin/security`, read-only).
- Sends it only to `api.anthropic.com` over HTTPS. No other network calls, no analytics, no disk cache.
- Stores only two local preferences (menu bar icon on/off, first-run login setup).

## Notes

Uses the same undocumented usage endpoint as Claude Code's `/usage`, so it may break without notice. Not affiliated with Anthropic.

MIT License.
