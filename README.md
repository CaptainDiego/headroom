# Headroom

A tiny macOS menu bar app (~270 KB) that shows how much of your Claude plan you've used: your 5-hour session and weekly limits, with reset times.

```
✳︎ 54% · 8%
```

## Install

Requires macOS 13+, the Xcode Command Line Tools, and [Claude Code](https://claude.com/claude-code) logged in with your Claude subscription.

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
