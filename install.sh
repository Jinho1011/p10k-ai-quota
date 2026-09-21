#!/usr/bin/env bash
# Install p10k-ai-quota: Codex + Claude + Gemini remaining quota in your zsh prompt.
# https://github.com/Jinho1011/p10k-ai-quota
set -euo pipefail

MARKER='# p10k-ai-quota'
FUELGAUGE_REPO='https://github.com/k7631159/ai-fuelgauge.git'
SRC="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

INTERVAL=5
REMOVE_CONTEXT=0
DRY_RUN=0
NO_SCHEDULE=0

BIN_DIR="$HOME/.local/bin"
ZSH_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"
FUELGAUGE_DIR="${AI_FUELGAUGE_DIR:-$HOME/.local/share/ai-fuelgauge}"
ZSHRC="$HOME/.zshrc"
P10K="$HOME/.p10k.zsh"

usage() {
  cat <<'EOF'
Usage: ./install.sh [options]

  --interval <minutes>   Refresh interval (default: 5). Do not go below 5 —
                         see the rate-limit note in the README.
  --remove-context       Also comment out p10k's `context` (user@host) segment
                         to make room. Off by default: it's your prompt.
  --dry-run              Print what would change, touch nothing.
  --no-schedule          Skip timer/agent registration (used by the test suite).
  -h, --help             This message.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --interval) INTERVAL="${2:?--interval needs a value}"; shift 2 ;;
    --remove-context) REMOVE_CONTEXT=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --no-schedule) NO_SCHEDULE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$INTERVAL" in
  ''|*[!0-9]*) echo "--interval must be a whole number of minutes" >&2; exit 2 ;;
esac
if [ "$INTERVAL" -lt 5 ]; then
  echo "refusing --interval $INTERVAL: sending probes more often than every" >&2
  echo "5 minutes risks a ~30 minute IP lock. See README > Caveats." >&2
  exit 2
fi

say()  { printf '%s\n' "$*"; }
step() { printf '\n[%s/6] %s\n' "$1" "$2"; }
warn() { printf '  ! %s\n' "$*" >&2; }
ok()   { printf '  + %s\n' "$*"; }
skip() { printf '  = %s\n' "$*"; }
run()  { if [ "$DRY_RUN" = 1 ]; then printf '  DRY %s\n' "$*"; else "$@"; fi; }

backup() {
  local f="$1"
  [ -f "$f" ] || return 0
  if [ "$DRY_RUN" = 1 ]; then printf '  DRY backup %s\n' "$f"; return 0; fi
  local b
  b="$f.bak.$(date +%Y%m%d%H%M%S)"
  cp -p "$f" "$b"
  ok "backup: $b"
}

# ---------------------------------------------------------------- [0/6] checks
step 0 "Checking prerequisites"
for c in zsh python3 git; do
  command -v "$c" >/dev/null 2>&1 || { echo "  missing required command: $c" >&2; exit 1; }
done
ok "zsh, python3, git"

case "$(uname -s)" in
  Linux)  PLATFORM=linux ;;
  Darwin) PLATFORM=macos ;;
  *) echo "  unsupported platform: $(uname -s)" >&2; exit 1 ;;
esac
ok "platform: $PLATFORM"
if [ "$PLATFORM" = macos ]; then warn "the macOS path is untested — please report what breaks"; fi

if [ ! -f "$P10K" ]; then
  warn "no ~/.p10k.zsh found. Run \`p10k configure\` first, then re-run this."
  warn "Continuing: everything but the prompt wiring will still be installed."
fi

for c in codex claude; do
  command -v "$c" >/dev/null 2>&1 || warn "$c not on PATH — its quota will show as '--'"
done
command -v agy >/dev/null 2>&1 || warn "agy not on PATH — the Gemini segment stays hidden"

# ------------------------------------------------------------ [1/6] fuelgauge
step 1 "ai-fuelgauge (the thing that actually reads the quotas)"
if command -v ai-usage >/dev/null 2>&1; then
  skip "ai-usage already on PATH: $(command -v ai-usage)"
elif [ -f "$FUELGAUGE_DIR/ai_fuelgauge.py" ]; then
  skip "already present: $FUELGAUGE_DIR"
else
  ok "cloning $FUELGAUGE_REPO"
  run git clone --depth 1 "$FUELGAUGE_REPO" "$FUELGAUGE_DIR"
fi
if ! command -v ai-usage >/dev/null 2>&1 && [ ! -e "$BIN_DIR/ai-usage" ]; then
  run mkdir -p "$BIN_DIR"
  if [ "$DRY_RUN" = 1 ]; then
    printf '  DRY write %s\n' "$BIN_DIR/ai-usage"
  else
    printf '#!/bin/sh\nexec %s "%s/ai_fuelgauge.py" "$@"\n' \
      "$(command -v python3)" "$FUELGAUGE_DIR" > "$BIN_DIR/ai-usage"
    chmod 755 "$BIN_DIR/ai-usage"
    ok "wrapper: $BIN_DIR/ai-usage"
  fi
fi

# --------------------------------------------------------------- [2/6] script
step 2 "Refresh script"
run mkdir -p "$BIN_DIR"
run install -m 755 "$SRC/bin/ai-quota-refresh" "$BIN_DIR/ai-quota-refresh"
ok "$BIN_DIR/ai-quota-refresh"

# -------------------------------------------------------------- [3/6] segment
step 3 "Prompt segment"
run mkdir -p "$ZSH_DIR"
run install -m 644 "$SRC/zsh/p10k-ai-quota.zsh" "$ZSH_DIR/p10k-ai-quota.zsh"
ok "$ZSH_DIR/p10k-ai-quota.zsh"

# ---------------------------------------------------------------- [4/6] zshrc
step 4 "Wiring into ~/.zshrc"
# shellcheck disable=SC2016  # intentionally unexpanded: keeps .zshrc portable
ZSH_DIR_LIT='${XDG_CONFIG_HOME:-$HOME/.config}/zsh'
SOURCE_LINE="[[ ! -f $ZSH_DIR_LIT/p10k-ai-quota.zsh ]] || source $ZSH_DIR_LIT/p10k-ai-quota.zsh  $MARKER"
if [ -f "$ZSHRC" ] && grep -qF "$MARKER" "$ZSHRC"; then
  skip "already wired"
else
  backup "$ZSHRC"
  # Must land AFTER ~/.p10k.zsh is sourced: that file starts with
  # `unset -m 'POWERLEVEL9K_*'`, which would erase our settings.
  if [ -f "$ZSHRC" ] && grep -qE '^\[\[ ! -f ~/\.p10k\.zsh \]\] \|\| source ~/\.p10k\.zsh' "$ZSHRC"; then
    if [ "$DRY_RUN" = 1 ]; then
      printf '  DRY insert after the .p10k.zsh source line\n'
    else
      awk -v line="$SOURCE_LINE" '
        { print }
        !done && /^\[\[ ! -f ~\/\.p10k\.zsh \]\] \|\| source ~\/\.p10k\.zsh/ { print line; done=1 }
      ' "$ZSHRC" > "$ZSHRC.tmp$$" && mv "$ZSHRC.tmp$$" "$ZSHRC"
      ok "inserted after the ~/.p10k.zsh source line"
    fi
  else
    warn "couldn't find the ~/.p10k.zsh source line; appending to the end of .zshrc"
    warn "if the segment doesn't appear, move that line below wherever p10k loads"
    if [ "$DRY_RUN" = 1 ]; then
      printf '  DRY append to %s\n' "$ZSHRC"
    else
      printf '\n%s\n' "$SOURCE_LINE" >> "$ZSHRC"
    fi
  fi
fi

# ----------------------------------------------------------------- [5/6] p10k
step 5 "Adding the segments to your right prompt"
patch_p10k() {
  [ -f "$P10K" ] || { warn "no ~/.p10k.zsh — skipping (see README for manual steps)"; return 0; }
  if grep -qF 'gemini_quota' "$P10K"; then skip "already present"; return 0; fi
  # Installs from before Gemini support: add just the new segment after Claude.
  if grep -qF 'codex_quota' "$P10K"; then
    if ! grep -qE "^[[:space:]]*claude_quota[[:space:]]+$MARKER\$" "$P10K"; then
      warn "claude_quota was moved or edited; add 'gemini_quota' by hand — see README"
      return 0
    fi
    backup "$P10K"
    if [ "$DRY_RUN" = 1 ]; then printf '  DRY add gemini_quota after claude_quota\n'; return 0; fi
    awk -v marker="$MARKER" '
      { print }
      !added && $1 == "claude_quota" && index($0, marker) {
        print "    gemini_quota            " marker; added=1
      }
    ' "$P10K" > "$P10K.tmp$$" && mv "$P10K.tmp$$" "$P10K"
    ok "gemini_quota added"
    return 0
  fi
  if ! grep -qE '^\s*typeset -g POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=\(' "$P10K"; then
    warn "POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS not found in ~/.p10k.zsh"
    warn "add 'codex_quota', 'claude_quota' and 'gemini_quota' to it by hand — see README"
    return 0
  fi
  backup "$P10K"
  if [ "$DRY_RUN" = 1 ]; then
    printf '  DRY add codex_quota + claude_quota + gemini_quota to RIGHT_PROMPT_ELEMENTS\n'
    if [ "$REMOVE_CONTEXT" = 1 ]; then printf '  DRY comment out the context segment\n'; fi
    return 0
  fi
  # Insert before the `newline` entry (end of prompt line #1, i.e. the far right
  # of the top line). Configs without a newline get it before the closing paren.
  awk -v marker="$MARKER" -v rmctx="$REMOVE_CONTEXT" '
    /^[[:space:]]*typeset -g POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=\(/ { inblk=1; print; next }
    inblk && !added && /^[[:space:]]*#+[[:space:]]*=+\[ Line #2 \]=+/ {
      print "    codex_quota             " marker
      print "    claude_quota            " marker
      print "    gemini_quota            " marker
      added=1; print; next
    }
    inblk && !added && /^[[:space:]]*newline([[:space:]]|$)/ {
      print "    codex_quota             " marker
      print "    claude_quota            " marker
      print "    gemini_quota            " marker
      added=1; print; next
    }
    inblk && /^[[:space:]]*\)[[:space:]]*$/ {
      if (!added) {
        print "    codex_quota             " marker
        print "    claude_quota            " marker
        print "    gemini_quota            " marker
        added=1
      }
      inblk=0; print; next
    }
    inblk && rmctx == 1 && /^[[:space:]]*context([[:space:]]|$)/ {
      sub(/context/, "# context"); print $0 "  " marker ":context"; next
    }
    { print }
  ' "$P10K" > "$P10K.tmp$$" && mv "$P10K.tmp$$" "$P10K"
  ok "codex_quota + claude_quota + gemini_quota added"
  if [ "$REMOVE_CONTEXT" = 1 ]; then ok "context segment commented out"; fi
  return 0
}
patch_p10k

# ------------------------------------------------------------ [6/6] scheduler
step 6 "Scheduling the refresh (every ${INTERVAL}m)"
if [ "$NO_SCHEDULE" = 1 ]; then
  skip "--no-schedule given"
elif [ "$PLATFORM" = linux ]; then
  UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
  run mkdir -p "$UNIT_DIR"
  if [ "$DRY_RUN" = 1 ]; then
    printf '  DRY install systemd units into %s\n' "$UNIT_DIR"
  else
    install -m 644 "$SRC/systemd/ai-quota-refresh.service" "$UNIT_DIR/"
    sed "s/__INTERVAL__/$INTERVAL/" "$SRC/systemd/ai-quota-refresh.timer" \
      > "$UNIT_DIR/ai-quota-refresh.timer"
    systemctl --user daemon-reload
    systemctl --user enable --now ai-quota-refresh.timer
    ok "systemd timer enabled"
    if [ "$(loginctl show-user "$(id -un)" -p Linger --value 2>/dev/null || echo no)" != "yes" ]; then
      warn "linger is off: the timer stops when you log out."
      warn "turn it on with: sudo loginctl enable-linger $(id -un)"
    fi
  fi
else
  PLIST="$HOME/Library/LaunchAgents/com.github.p10k-ai-quota.plist"
  if [ "$DRY_RUN" = 1 ]; then
    printf '  DRY install launch agent %s\n' "$PLIST"
  else
    mkdir -p "$HOME/Library/LaunchAgents"
    sed -e "s|__HOME__|$HOME|g" -e "s|__INTERVAL__|$((INTERVAL * 60))|" \
      "$SRC/launchd/com.github.p10k-ai-quota.plist" > "$PLIST"
    launchctl bootout "gui/$UID/com.github.p10k-ai-quota" 2>/dev/null || true
    launchctl bootstrap "gui/$UID" "$PLIST"
    ok "launch agent loaded"
  fi
fi

if [ "$DRY_RUN" = 1 ]; then
  say ""
  say "Dry run complete. Nothing was changed."
  exit 0
fi

say ""
say "Running the first probe..."
if "$BIN_DIR/ai-quota-refresh"; then
  say ""
  say "Done. Run 'exec zsh' to reload your prompt."
else
  say ""
  warn "the first probe failed — check that 'codex', 'claude' and 'agy' are logged in."
  warn "run '$BIN_DIR/ai-quota-refresh' by hand to see the error."
fi
