#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Claude Usage
# @raycast.mode inline
# @raycast.refreshTime 5m

# Optional parameters:
# @raycast.icon ✳️
# @raycast.packageName Claude
# @raycast.description Claude plan usage (5h session · weekly)

CREDS=$(/usr/bin/security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null) || {
  echo "No Claude Code login found — run \`claude\` and log in"; exit 1; }

TOKEN=$(printf '%s' "$CREDS" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["claudeAiOauth"]["accessToken"])')

RESP=$(printf 'Authorization: Bearer %s\n' "$TOKEN" | /usr/bin/curl -s --proto '=https' -w '\n%{http_code}' --max-time 15 https://api.anthropic.com/api/oauth/usage \
  -H @- -H "anthropic-beta: oauth-2025-04-20" -H "User-Agent: headroom/1.0")
CODE=$(printf '%s' "$RESP" | tail -n1)
BODY=$(printf '%s' "$RESP" | sed '$d')

[ "$CODE" = "401" ] && { echo "Token expired — open Claude Code once to refresh"; exit 1; }
[ "$CODE" != "200" ] && { echo "Error: HTTP $CODE"; exit 1; }

printf '%s' "$BODY" | /usr/bin/python3 -c '
import json, sys
from datetime import datetime, timezone
d = json.load(sys.stdin)
lim = {l["kind"]: l for l in d.get("limits") or []}
def until(iso):
    if not iso: return ""
    secs = (datetime.fromisoformat(iso) - datetime.now(timezone.utc)).total_seconds()
    if secs <= 0: return "resetting"
    if secs < 86400:
        h, m = int(secs // 3600), int(secs % 3600 // 60)
        return f"resets {h}h {m}m" if h else f"resets {m}m"
    return "resets " + datetime.fromisoformat(iso).astimezone().strftime("%a %-I:%M %p")
def dot(p): return "🔴" if p >= 90 else "🟠" if p >= 70 else "🟢"
parts = []
for kind, label in (("session", "Session"), ("weekly_all", "Week")):
    l = lim.get(kind)
    if l:
        p = l["percent"]
        r = until(l.get("resets_at"))
        parts.append(f"{dot(p)} {label} {int(p)}% ({r})")
print("   ".join(parts) or "No limit data")
'
