# powerlevel10k custom segments: codex_quota / claude_quota
#
# Source this from ~/.zshrc AFTER ~/.p10k.zsh: that file does
# `unset -m 'POWERLEVEL9K_*'` at its top, so anything set before it is erased.
#
# The displayed text — including its per-metric colours — is pre-rendered by
# ~/.local/bin/ai-quota-refresh, run by a timer every 5 minutes. These
# functions only source a small file: no fork, no jq, no python, no $( ).
#
# https://github.com/Jinho1011/p10k-ai-quota

typeset -g _AI_QUOTA_FILE=${XDG_CACHE_HOME:-$HOME/.cache}/ai-quota-prompt.zsh
typeset -g _AI_QUOTA_MAX_AGE=900

# Colours are baked into the text. These are only a fallback.
typeset -g POWERLEVEL9K_CODEX_QUOTA_FOREGROUND=244
typeset -g POWERLEVEL9K_CLAUDE_QUOTA_FOREGROUND=244
typeset -g POWERLEVEL9K_GEMINI_QUOTA_FOREGROUND=244

# Shared loader: pick the coloured variant when fresh, the dimmed one when not.
function _ai_quota_render() {   # $1 = codex | claude | gemini
  local _ai_codex_text= _ai_codex_dim= _ai_claude_text= _ai_claude_dim=
  local _ai_gemini_text= _ai_gemini_dim=
  local -i _ai_quota_at=0
  [[ -r $_AI_QUOTA_FILE ]] || return
  source $_AI_QUOTA_FILE 2>/dev/null || return
  local live dim
  case $1 in
    codex)  live=$_ai_codex_text;  dim=$_ai_codex_dim  ;;
    claude) live=$_ai_claude_text; dim=$_ai_claude_dim ;;
    gemini) live=$_ai_gemini_text; dim=$_ai_gemini_dim ;;
  esac
  # The artifact is written once and read by every shell for minutes afterwards,
  # so only the shell can tell that the file itself went stale (timer masked,
  # machine suspended) while its baked-in colours still claim everything is fine.
  (( EPOCHSECONDS - _ai_quota_at <= _AI_QUOTA_MAX_AGE )) || live=$dim
  [[ -n $live ]] || return
  p10k segment -t $live
}

function prompt_codex_quota()  { _ai_quota_render codex  }
function prompt_claude_quota() { _ai_quota_render claude }
function prompt_gemini_quota() { _ai_quota_render gemini }

# No instant_prompt_*: p10k records those `p10k segment` calls once and replays
# them at the next shell start, which would replay a stale number.

(( ! $+functions[p10k] )) || p10k reload
