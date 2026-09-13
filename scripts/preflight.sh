#!/usr/bin/env bash
# Run ON THE DOCKER HOST to check everything is in place before deploying.
# Reports PASS/WARN/FAIL per check; exits non-zero if anything hard-fails.
set -uo pipefail

fail=0
pass() { printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
warn() { printf '  \033[33mWARN\033[0m  %s\n' "$1"; }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; fail=1; }

echo "== Software =="
command -v docker >/dev/null && pass "docker installed ($(docker --version))" || bad "docker not installed"
docker compose version >/dev/null 2>&1 && pass "compose v2 plugin present" || bad "'docker compose' (v2) missing"
command -v git >/dev/null && pass "git installed" || bad "git not installed"
docker info >/dev/null 2>&1 && pass "docker daemon reachable as this user" \
  || bad "can't talk to docker daemon (in 'docker' group? daemon running? LXC nesting=1?)"

echo "== Repo access =="
if git ls-remote origin >/dev/null 2>&1; then pass "git can reach origin (deploy key works)"
else warn "git can't reach origin — run inside the repo; check the SSH deploy key"; fi

echo "== iGPU (Jellyfin) =="
if [ -e /dev/dri/renderD128 ]; then
  pass "/dev/dri/renderD128 present"
  gid=$(getent group render | cut -d: -f3)
  [ -n "${gid:-}" ] && pass "render group GID = $gid  (put this in jellyfin/compose.yml group_add)" \
    || warn "no 'render' group — check the GID that owns /dev/dri/renderD128"
else
  warn "/dev/dri/renderD128 missing — LXC passthrough not done (see README). HW transcode won't work."
fi

echo "== Storage =="
MEDIA_ROOT="${MEDIA_ROOT:-/mnt/media}"
[ -d "$MEDIA_ROOT" ] && pass "media root exists: $MEDIA_ROOT" \
  || warn "media root '$MEDIA_ROOT' not found — set MEDIA_ROOT or mount it (jellyfin/.env)"

echo "== Networking =="
for p in 80 443; do
  if (command -v ss >/dev/null && ss -ltn 2>/dev/null | grep -q ":$p ") \
     || (command -v netstat >/dev/null && netstat -ltn 2>/dev/null | grep -q ":$p "); then
    warn "port $p already in use — Caddy needs it free"
  else
    pass "port $p free"
  fi
done

echo
[ "$fail" -eq 0 ] && echo "Preflight OK (review any WARNs above)." \
  || { echo "Preflight found blocking issues (FAIL) — fix before deploying."; exit 1; }
