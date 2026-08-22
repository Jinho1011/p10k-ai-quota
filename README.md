# p10k-ai-quota

**Codex and Claude remaining quota, in your zsh prompt.** A
[powerlevel10k](https://github.com/romkatv/powerlevel10k) segment for Linux
(systemd) — so you know what's left *before* you start something big, without
running `/usage` or leaving the terminal.

```
 ~/work  ............................  Codex 7d 94%  │  Claude 5h 93% 7d 99%
>
```

Labels are dim; only the numbers carry colour, and each one is coloured on its
own so you can see *which* limit is the problem:

| Remaining | Colour | Meaning |
|---|---|---|
| 25%+ | green | fine |
| 10–24% | yellow | pace yourself |
| under 10% | red | about to hit the wall |
| `94%?` | grey + `?` | last known value, gone stale — probe is failing |
| `--` | grey | never seen a value (not logged in, or that CLI is missing) |

The prompt costs **0.047 ms** to render. It never talks to the network — a
background timer does that and leaves a pre-rendered string on disk.

## Is this the right tool for you?

This niche is crowded, and something else may fit you better:

| You want | Go here |
|---|---|
| Claude only, in iTerm2 / tmux / WezTerm / kitty / starship | [Tatendaz/claude-usage](https://github.com/Tatendaz/claude-usage) |
| A macOS menu bar app | [steipete/CodexBar](https://github.com/steipete/CodexBar) |
| It shown inside the Claude Code window | [jarrodwatts/claude-hud](https://github.com/jarrodwatts/claude-hud) |
| Token counts and dollar costs | [ccusage](https://github.com/ccusage/ccusage) |
| **Codex + Claude, in the zsh prompt itself** | **you're in the right place** |

## Install

```bash
git clone https://github.com/Jinho1011/p10k-ai-quota
cd p10k-ai-quota
./install.sh
```

Then `exec zsh`.

That's it — the installer also clones [ai-fuelgauge](https://github.com/k7631159/ai-fuelgauge)
(which does the actual quota reading) if you don't already have it. It backs up
every file it edits, marks the lines it adds, and is safe to run twice.

Try `./install.sh --dry-run` first if you'd rather see what it will touch.

**Options**

| Flag | Effect |
|---|---|
| `--dry-run` | Print every change, modify nothing |
| `--remove-context` | Also comment out p10k's `context` (`user@host`) segment to free up room. Off by default — it's your prompt. Reversed by `./uninstall.sh`. |
| `--interval <min>` | Refresh interval, default `5`. Values below 5 are refused; see Caveats. |

## Requirements

- **Linux** with a systemd user session — this is the tested path
- zsh + powerlevel10k (run `p10k configure` first if you haven't)
- Python 3.7+, git
- [Codex CLI](https://github.com/openai/codex) and/or
  [Claude Code](https://claude.com/claude-code), installed and logged in.
  Either one alone works; the missing one shows `--`.

For the timer to keep running when you're logged out:
`sudo loginctl enable-linger $USER`. The installer checks and tells you.

**macOS** ships a launchd agent and the installer handles it, but **it is
untested** — I don't have a Mac. Reports and PRs welcome.

## How it works

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

The prompt functions do exactly one thing: `source` a three-line file. No fork,
no `jq`, no Python, no `$(...)`.

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

## Customizing

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

Moving the segments: they're plain p10k segments named `codex_quota` and
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

## Caveats

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

## Uninstall

```bash
./uninstall.sh
```

Removes the timer, the scripts, and the lines it added to `~/.zshrc` and
`~/.p10k.zsh` (restoring your `context` segment if you had it removed). It
leaves ai-fuelgauge alone, since you may be using `ai-usage` directly.

## Credits

All the hard part — talking to Codex and Claude, refreshing tokens, normalizing
the responses — is [**k7631159/ai-fuelgauge**](https://github.com/k7631159/ai-fuelgauge)
(MIT). This repo is just the powerlevel10k integration on top of it.

Prompted by [powerlevel10k#2940](https://github.com/romkatv/powerlevel10k/issues/2940),
which asked for exactly this and had no implementation.

## License

MIT — see [LICENSE](LICENSE).
