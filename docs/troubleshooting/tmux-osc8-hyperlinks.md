# OSC 8 hyperlinks (Cmd+Click links) inside tmux

## Symptom

In a terminal that supports OSC 8 hyperlinks, link text emitted by inner
CLIs (e.g. Claude Code rendering markdown links like
`[Anthropic](https://www.anthropic.com)`) shows the styled text but
**Cmd+Click does not jump** while the CLI runs inside an orca tmux
session. The same CLI run directly in the terminal (no tmux) jumps fine.

## Reproduction matrix

| Terminal       | tmux | Click modifier      | Result        |
|----------------|------|---------------------|---------------|
| Ghostty 1.3.x  | no   | Cmd+Click           | works         |
| Ghostty 1.3.x  | yes  | Cmd+Click           | **broken**    |
| Ghostty 1.3.x  | yes  | Shift+Cmd+Click     | works         |
| Zed terminal   | yes  | Cmd+Click           | works         |
| iTerm2 / WezTerm | yes | Cmd+Click          | expected to work (not yet measured) |

Tested on tmux 3.6a with this repo's `start.sh` configuration.

## Root cause

Two separate mechanisms stack on top of each other:

1. **OSC 8 transport** — tmux strips the OSC 8 escape sequence from inner
   programs unless `terminal-features` advertises `:hyperlinks`. Without
   it, the outer terminal only receives plain styled text and has no URL
   to jump to. `start.sh` sets this feature for every orca session, so
   transport is in place — verified with
   `tmux show-options -gs terminal-features` listing `*:hyperlinks`.

2. **Mouse capture** — `start.sh` sets `mouse on` so users can drag pane
   borders and scroll the scrollback. With mouse mode active, tmux
   consumes mouse events inside panes and the outer terminal never sees
   the click. Most macOS terminals (iTerm2, WezTerm, Zed) special-case
   the Cmd modifier and forward Cmd+Click to themselves regardless of
   tmux mouse mode. Ghostty does not — by default it requires the
   **Shift** modifier to bypass tmux mouse capture
   (`mouse-shift-capture = true`).

So in Ghostty + tmux + `mouse on`, plain Cmd+Click never reaches Ghostty
to be turned into a hyperlink jump. Shift+Cmd+Click does.

## Workarounds

### Option A — Use Shift+Cmd+Click (recommended for Ghostty users)

No configuration change. Hold Shift while Cmd+Clicking. This is the
standard Ghostty + tmux interaction for any mouse action that needs to
bypass tmux mouse capture (text selection works the same way).

### Option B — Disable Ghostty's mouse-shift-capture

Set in `~/Library/Application Support/com.mitchellh.ghostty/config.ghostty`
(macOS) or `~/.config/ghostty/config` (Linux):

```
mouse-shift-capture = false
```

Lets plain Cmd+Click reach Ghostty. Trade-off: Shift no longer bypasses
tmux mouse for *any* action, so selecting text with the mouse becomes
awkward (you'd have to hold Option for tmux's own copy mode, etc.).

### Option C — Switch terminal

Zed's built-in terminal handles Cmd+Click correctly inside tmux without
any extra config. iTerm2 and WezTerm follow the same convention.

## Why this isn't fixed in orca

Disabling `mouse on` in tmux would fix Cmd+Click for Ghostty but break
pane-border dragging and scrollback scrolling for everyone — a worse
trade than asking Ghostty users to add a Shift.

The `terminal-features ',*:hyperlinks'` line in `start.sh` is still
necessary regardless: it's what makes the URL information reach the
outer terminal in the first place. Without it, even Zed's Cmd+Click
would have nothing to jump to.

## Removal criteria

This page can be retired when Ghostty changes its default to forward
Cmd+Click to itself instead of letting tmux capture it. Track:
[ghostty#11907](https://github.com/ghostty-org/ghostty/issues/11907).
