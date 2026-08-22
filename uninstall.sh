#!/usr/bin/env bash
# Remove p10k-ai-quota. Leaves ai-fuelgauge alone — you may use it directly.
set -euo pipefail

MARKER='# p10k-ai-quota'
BIN_DIR="$HOME/.local/bin"
ZSH_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
ZSHRC="$HOME/.zshrc"
P10K="$HOME/.p10k.zsh"

ok()   { printf '  - %s\n' "$*"; }
skip() { printf '  = %s\n' "$*"; }

printf '\nUnscheduling\n'
if [ "$(uname -s)" = Linux ]; then
  if systemctl --user disable --now ai-quota-refresh.timer 2>/dev/null; then ok "timer disabled"; else skip "timer not registered"; fi
  rm -f "$UNIT_DIR/ai-quota-refresh.timer" "$UNIT_DIR/ai-quota-refresh.service"
  systemctl --user daemon-reload 2>/dev/null || true
else
  if launchctl bootout "gui/$UID/com.github.p10k-ai-quota" 2>/dev/null; then ok "agent unloaded"; else skip "agent not loaded"; fi
  rm -f "$HOME/Library/LaunchAgents/com.github.p10k-ai-quota.plist"
fi

printf '\nRemoving files\n'
for f in "$BIN_DIR/ai-quota-refresh" "$ZSH_DIR/p10k-ai-quota.zsh" \
         "$CACHE_DIR/ai-quota-prompt.zsh" "$CACHE_DIR/ai-quota.state.json" \
         "$CACHE_DIR/ai-quota-refresh.log"; do
  if [ -e "$f" ]; then rm -f "$f"; ok "$f"; fi
done

printf '\nUnwiring config\n'
for f in "$ZSHRC" "$P10K"; do
  [ -f "$f" ] || continue
  if grep -qF "$MARKER" "$f"; then
    cp -p "$f" "$f.bak.$(date +%Y%m%d%H%M%S)"
    # Restore the context segment we commented out before deleting marked lines
    # (its marker contains $MARKER, so order matters here).
    sed -i.tmp$$ -e "s|^\( *\)# context\(.*\)  $MARKER:context\$|\1context\2|" "$f" && rm -f "$f.tmp$$"
    grep -vF "$MARKER" "$f" > "$f.tmp$$" && mv "$f.tmp$$" "$f"
    ok "$f (backup kept)"
  else
    skip "$f: nothing to remove"
  fi
done

cat <<EOF

Done. Run 'exec zsh' to reload your prompt.

Left in place on purpose:
  ai-fuelgauge      you may be using it directly (\`ai-usage\`)
  ~/.local/bin/ai-usage
  *.bak.* backups   delete them yourself once you're happy
EOF
