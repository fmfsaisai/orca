# Shift+Enter doesn't work in Codex inside Ghostty + tmux

## Symptom

Pressing **Shift+Enter** in the Codex pane while running orca (or any tmux
session) under Ghostty submits the line instead of inserting a newline.
Claude Code in the same pane setup works fine.

## Reproduction matrix

| Terminal | tmux | CLI    | Shift+Enter |
|----------|------|--------|-------------|
| Ghostty  | —    | Codex  | works       |
| Ghostty  | —    | CC     | works       |
| Ghostty  | yes  | Codex  | **broken**  |
| Ghostty  | yes  | CC     | works (with `extended-keys on`) |
| Zed term | yes  | Codex  | works       |
| Zed term | yes  | CC     | works       |

orca is incidental — the bug reproduces with plain `tmux new-session` then
`codex`. Only the Ghostty + tmux + Codex combination fails.

Tested on:
- Ghostty 1.3.1
- tmux 3.6a
- codex-cli 0.121.0
- Claude Code 2.1.112

## Root cause

Ghostty 1.3+ encodes Shift+Enter using the
[Kitty keyboard protocol](https://sw.kovidgoyal.net/kitty/keyboard-protocol/)
(`CSI 13 ; 2 u`) instead of the legacy `Esc + CR` sequence (`\e\r`).

For tmux to forward that to inner programs, two conditions must hold:

1. tmux has `extended-keys on` and `terminal-features ',*:extkeys'` — this
   repo's `start.sh` sets both per session.
2. The inner program negotiates Kitty keyboard mode by emitting
   `CSI > 1 u` after start.

Claude Code negotiates step 2; Codex 0.121 does not when `$TERM` is
`tmux-256color` (it does negotiate when `$TERM` is `xterm-ghostty` running
directly under Ghostty, which is why direct `codex` works).

Without the negotiation, tmux falls back to legacy encoding, but Ghostty
never sent the legacy form to begin with — so the inner program receives
plain `\r` and treats it as submit.

Zed's terminal emulator sends Shift+Enter as legacy `\e\r` regardless,
which tmux passes through verbatim and Codex understands. Hence Zed works.

## Workarounds

### Option A — Use Option+Enter

Option+Enter sends `\e\r` (the legacy Alt+Enter sequence). Ghostty passes
it through, tmux passes it through, Codex understands it as newline.
Nothing to configure.

### Option B — Remap Shift+Enter in Ghostty

Add to `~/Library/Application Support/com.mitchellh.ghostty/config.ghostty`
(macOS) or `~/.config/ghostty/config` (Linux):

```
keybind = shift+enter=text:\x1b\r
```

This makes Ghostty send `\e\r` for Shift+Enter, matching what Zed's
terminal does. Restart Ghostty to apply.

Both Claude Code and Codex accept this encoding, so the change is safe
across CLIs. Removes the dependency on tmux `extended-keys` for CC's
Shift+Enter as well — the protocol path becomes uniform.

## Removal criteria

This workaround can be removed when **either** of these lands upstream:

- **Codex** opts into the Kitty keyboard protocol when running inside tmux
  (track via [openai/codex](https://github.com/openai/codex) issues).
- **tmux** supports forwarding Kitty keyboard protocol progressive
  enhancement (`CSI > 9 u` and friends) — current tmux 3.x only forwards
  the basic level (`CSI > 1 u`).

Until then, the README known-limitations entry stays.
