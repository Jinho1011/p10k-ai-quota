<h1 align="center">p10k-ai-quota ⛽</h1>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/Jinho1011/p10k-ai-quota/main/docs/assets/banner-light.png">
    <img src="https://raw.githubusercontent.com/Jinho1011/p10k-ai-quota/main/docs/assets/banner-dark.png" alt="p10k-ai-quota — Codex + Claude quota, in your zsh prompt" width="100%">
  </picture>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="License: MIT"></a>
  <img src="https://img.shields.io/badge/shell-zsh-89e051?style=flat-square&logo=zsh&logoColor=white" alt="zsh">
  <a href="https://github.com/romkatv/powerlevel10k"><img src="https://img.shields.io/badge/powerlevel10k-segment-1f6feb?style=flat-square" alt="powerlevel10k segment"></a>
  <img src="https://img.shields.io/badge/prompt%20cost-0.047%20ms-brightgreen?style=flat-square" alt="0.047 ms prompt cost">
  <img src="https://img.shields.io/badge/platform-Linux%20(systemd)-informational?style=flat-square&logo=linux&logoColor=white" alt="Linux systemd">
  <img src="https://img.shields.io/badge/macOS-untested-lightgrey?style=flat-square&logo=apple&logoColor=white" alt="macOS untested">
  <a href="https://github.com/Jinho1011/p10k-ai-quota/stargazers"><img src="https://img.shields.io/github/stars/Jinho1011/p10k-ai-quota?style=flat-square&color=f5c518" alt="Stars"></a>
</p>

<p align="center">
  <a href="#-quick-start">Install</a> ·
  <a href="#-how-it-works">How it works</a> ·
  <a href="#%EF%B8%8F-caveats">Caveats</a> ·
  <a href="#-is-this-the-right-tool-for-you">Alternatives</a> ·
  <a href="#-credits">Credits</a>
</p>

---

**Codex and Claude remaining quota, right in your zsh prompt.** So you know
what's left *before* you start something big — without running `/usage`, opening
a menu bar app, or leaving the terminal.

```
 ~/work  ............................  Codex 7d 94%  │  Claude 5h 93% 7d 99%
>
```

## 🚀 Quick start

```bash
git clone https://github.com/Jinho1011/p10k-ai-quota
cd p10k-ai-quota
./install.sh
```

Then `exec zsh`. That's it.

The installer also clones [ai-fuelgauge](https://github.com/k7631159/ai-fuelgauge)
(which does the actual quota reading) if you don't already have it. It backs up
every file it edits, marks the lines it adds, and is safe to run twice. Try
`./install.sh --dry-run` first if you'd rather see what it will touch.

| Flag | Effect |
|---|---|
| `--dry-run` | Print every change, modify nothing |
| `--remove-context` | Also comment out p10k's `context` (`user@host`) segment to free up room. Off by default — it's your prompt. Reversed by `./uninstall.sh`. |
| `--interval <min>` | Refresh interval, default `5`. Values below 5 are refused; see [Caveats](#%EF%B8%8F-caveats). |

## ⚡ Why it's fast

|  | |
|---|---|
| **0.047 ms per prompt** | The prompt functions `source` a three-line file. No fork, no `jq`, no Python, no `$(...)`. |
| **Zero network in the shell** | A background timer does the talking and leaves a pre-rendered string on disk. |
| **Never goes blank** | Per-metric last-known-good: if one provider is down, the other keeps updating and the stale number grows a `?`. |

Labels are dim; only the numbers carry colour, and each one is coloured on its
own so you can see *which* limit is the problem:

| Remaining | Colour | Meaning |
|---|---|---|
| 25%+ | 🟢 green | fine |
| 10–24% | 🟡 yellow | pace yourself |
| under 10% | 🔴 red | about to hit the wall |
| `94%?` | ⚪ grey + `?` | last known value, gone stale — probe is failing |
| `--` | ⚪ grey | never seen a value (not logged in, or that CLI is missing) |

## 🧭 Is this the right tool for you?

This niche is crowded, and something else may fit you better:

| You want | Go here |
|---|---|
| Claude only, in iTerm2 / tmux / WezTerm / kitty / starship | [Tatendaz/claude-usage](https://github.com/Tatendaz/claude-usage) |
| A macOS menu bar app | [steipete/CodexBar](https://github.com/steipete/CodexBar) |
| It shown inside the Claude Code window | [jarrodwatts/claude-hud](https://github.com/jarrodwatts/claude-hud) |
| Token counts and dollar costs | [ccusage](https://github.com/ccusage/ccusage) |
| **Codex + Claude, in the zsh prompt itself** | **you're in the right place** |

## 📦 Requirements

- **Linux** with a systemd user session — this is the tested path
- zsh + [powerlevel10k](https://github.com/romkatv/powerlevel10k) (run `p10k configure` first if you haven't)
- Python 3.7+, git
- [Codex CLI](https://github.com/openai/codex) and/or [Claude Code](https://claude.com/claude-code), installed and logged in. Either one alone works; the missing one shows `--`.

For the timer to keep running when you're logged out:
`sudo loginctl enable-linger $USER`. The installer checks and tells you.

> **macOS** ships a launchd agent and the installer handles it, but **it is
> untested** — I don't have a Mac. Reports and PRs welcome.

## 🔧 How it works

Reading the quota is slow: **1.8 seconds** on a cold probe, because it
cold-starts `codex app-server` and makes an OAuth call. Putting that in your
prompt would make every command feel broken. Even a warm cache costs 76 ms —
still far too much to pay on every prompt.

So the work is moved off the prompt entirely:

```
 systemd timer (every 5 min)
        │
        ▼
 ai-quota-refresh ── ai-fuelgauge ──▶ codex app-server + Claude OAuth
        │
        ├──▶ ~/.cache/ai-quota.state.json    last known good, per metric
        └──▶ ~/.cache/ai-quota-prompt.zsh    pre-rendered, colours baked in
                     ▲
                     │  source (0.047 ms)
        prompt_codex_quota / prompt_claude_quota
```

A few details that matter more than they look:

- **Per-metric last-known-good.** A metric is only overwritten when that run
  actually resolved it. If Codex is down but Claude is fine, the Codex number
  freezes rather than blanking, and grows a `?` once it passes 15 minutes old.
- **Colours are baked in by the refresher**, not chosen by the shell. That's
  what makes per-number colouring possible — `p10k segment -s STATE` can only
  colour a whole segment at once.
- **Staleness is checked twice**, once when writing and once in the shell. The
  file is written once and read by every shell for minutes afterwards, so only
  the shell can notice that the file *itself* went stale (timer masked, laptop
  suspended).
- **Windows are matched by `window_minutes`, not slot position.** Codex Plus
  reports only a weekly limit; higher tiers also report a 5-hour one, and it
  shows up automatically when present.

<details>
<summary><b>🎨 Customizing</b> — colours, thresholds, icons, segment position, env vars</summary>

<br>

Colours and thresholds — `~/.local/bin/ai-quota-refresh`:

```python
LABEL_FG = 244
FG_OK, FG_WARN, FG_CRIT = 76, 178, 196
WARN_BELOW, CRIT_BELOW = 25, 10
```

Staleness cutoff and an optional icon — `~/.config/zsh/p10k-ai-quota.zsh`:

```zsh
typeset -g _AI_QUOTA_MAX_AGE=900
# typeset -g POWERLEVEL9K_CODEX_QUOTA_VISUAL_IDENTIFIER_EXPANSION='⛽'
```

Rerun `~/.local/bin/ai-quota-refresh` after changing colours, then `exec zsh`.

**Moving the segments:** they're plain p10k segments named `codex_quota` and
`claude_quota` — reorder them in `POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS` (or move
them to `POWERLEVEL9K_LEFT_PROMPT_ELEMENTS`) like any other.

If the installer couldn't patch your `~/.p10k.zsh`, add them by hand:

```zsh
typeset -g POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(
    ...
    codex_quota
    claude_quota
    newline
    ...
)
```

**Environment variables**

| Variable | Effect |
|---|---|
| `AI_QUOTA_CMD` | Override the probe command entirely. Must print ai-fuelgauge `--json` output. |
| `AI_FUELGAUGE_DIR` | Where ai-fuelgauge lives. Default `~/.local/share/ai-fuelgauge`; honoured by the installer too. |
| `AI_QUOTA_JITTER` | Seconds of random sleep before probing. Set to `20` in the launchd plist, since launchd has no `RandomizedDelaySec`. |
| `_AI_QUOTA_FILE` | Path to the pre-rendered prompt file. Default `~/.cache/ai-quota-prompt.zsh`. |
| `_AI_QUOTA_MAX_AGE` | Shell-side staleness cutoff in seconds. Default `900`. |

`XDG_CACHE_HOME` and `XDG_CONFIG_HOME` are respected everywhere.

</details>

<details>
<summary><b>🩺 Troubleshooting</b> — the numbers are stale, missing, or never appeared</summary>

<br>

Every refresh prints a one-line status: `ok`, `partial`, or `probe-failed`.

```bash
# Run the refresher by hand and watch what it says
~/.local/bin/ai-quota-refresh

# Linux: read the last runs
journalctl --user -u ai-quota-refresh.service -n 20

# macOS: same thing, from the log file
tail -n 20 ~/.cache/ai-quota-refresh.log

# Is the timer actually scheduled?
systemctl --user list-timers ai-quota-refresh.timer
```

- `--` everywhere → that CLI isn't installed, or you're not logged into it.
- Numbers frozen with a `?` → the probe is failing; check the status line above.
- Everything stops while you're logged out → `sudo loginctl enable-linger $USER`.
- Segments don't appear at all → confirm `codex_quota` / `claude_quota` are in
  `POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS`, and that the `source` line in `~/.zshrc`
  comes *after* `source ~/.p10k.zsh`.

</details>

## ⚠️ Caveats

Please read these before installing.

- **Both upstream endpoints are unofficial.** `codex app-server` is marked
  experimental by OpenAI, and Claude's `/api/oauth/usage` is undocumented and
  meant for Anthropic's own apps. Either can break without warning. When they
  do, the segment degrades to `94%?` rather than breaking your prompt — but it
  will be wrong until it's fixed.
- **Don't shorten the interval below 5 minutes.** ai-fuelgauge warns that
  sending an expired token to `api.anthropic.com` can get your IP locked for
  ~30 minutes. The installer refuses values under 5 for this reason.
- **Each refresh cold-starts `codex app-server`**, a ~258 MB static binary —
  288 times a day. The systemd unit runs it at `Nice=10` with idle I/O
  priority. If you notice it, `--interval 10` halves the cost and still stays
  well inside the 15-minute staleness window.
- **The macOS path is untested.**
- This reads your local Codex/Claude credentials only to ask those services how
  much quota you have left. Nothing is sent anywhere else, and no quota numbers
  leave your machine.

## 🧹 Uninstall

```bash
./uninstall.sh
```

Removes the timer, the scripts, and the lines it added to `~/.zshrc` and
`~/.p10k.zsh` (restoring your `context` segment if you had it removed). It
leaves ai-fuelgauge alone, since you may be using `ai-usage` directly.

## 💙 Credits

All the hard part — talking to Codex and Claude, refreshing tokens, normalizing
the responses — is [**k7631159/ai-fuelgauge**](https://github.com/k7631159/ai-fuelgauge)
(MIT). This repo is just the powerlevel10k integration on top of it.

Prompted by [powerlevel10k#2940](https://github.com/romkatv/powerlevel10k/issues/2940),
which asked for exactly this and had no implementation.

## 📄 License

MIT — see [LICENSE](LICENSE).

<p align="center">
  <sub>If this saved you a <code>/usage</code>, a ⭐ is appreciated.</sub>
</p>
