#!/usr/bin/env bash
# ─── Layca Dev Session ───────────────────────────────────────────────────────
# Usage: ./scripts/dev.sh [session-name]
#   Opens a 3-window tmux session for Layca development.
#   Designed for iTerm2 — each window is a separate tab.
#
# Windows:
#   1. claude   — main Claude Code session
#   2. agents   — 4-pane grid for parallel agent monitoring
#   3. git      — git log, status, diff

set -e
SESSION="${1:-layca}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# ─── If session already exists, attach ───────────────────────────────────────
if tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "Attaching to existing session: $SESSION"
    tmux attach-session -t "$SESSION"
    exit 0
fi

# ─── Create session ──────────────────────────────────────────────────────────
tmux new-session -d -s "$SESSION" -n claude -c "$ROOT"

# Window 1: claude — full-screen Claude Code
tmux send-keys -t "$SESSION:claude" \
    'echo "💡 Claude Code — run: claude"' Enter

# ─── Window 2: agents — 4-pane grid for parallel agent monitoring ─────────────
tmux new-window -t "$SESSION" -n agents -c "$ROOT"

# Split into 4 panes (2×2 grid)
tmux split-window -t "$SESSION:agents" -v -c "$ROOT"   # bottom-left
tmux split-window -t "$SESSION:agents.1" -h -c "$ROOT" # top-right
tmux split-window -t "$SESSION:agents.3" -h -c "$ROOT" # bottom-right

# Label each pane
tmux send-keys -t "$SESSION:agents.1" 'printf "\033]2;Agent 1\007"; echo "[ Agent 1 — Pipeline ]"' Enter
tmux send-keys -t "$SESSION:agents.2" 'printf "\033]2;Agent 2\007"; echo "[ Agent 2 — UI ]"' Enter
tmux send-keys -t "$SESSION:agents.3" 'printf "\033]2;Agent 3\007"; echo "[ Agent 3 — Review ]"' Enter
tmux send-keys -t "$SESSION:agents.4" 'printf "\033]2;Agent 4\007"; echo "[ Agent 4 — Spare ]"' Enter

# Select top-left pane as default focus
tmux select-pane -t "$SESSION:agents.1"

# ─── Window 3: git — git log + live status ───────────────────────────────────
tmux new-window -t "$SESSION" -n git -c "$ROOT"
tmux split-window -t "$SESSION:git" -h -c "$ROOT"

# Left pane: git log
tmux send-keys -t "$SESSION:git.1" \
    'git log --oneline --graph --decorate --all | head -40' Enter

# Right pane: watch git status
tmux send-keys -t "$SESSION:git.2" \
    'watch -n 2 git status --short' Enter

# ─── Select starting window ──────────────────────────────────────────────────
tmux select-window -t "$SESSION:claude"

echo ""
echo "✅  Layca tmux session '$SESSION' started."
echo ""
echo "  Windows:"
echo "    1. claude  — Claude Code (run: claude)"
echo "    2. agents  — 4-pane grid for parallel agents"
echo "    3. git     — git log + live status watcher"
echo ""
echo "  Key bindings (prefix = Ctrl-a):"
echo "    Ctrl-a |   split pane vertical"
echo "    Ctrl-a -   split pane horizontal"
echo "    Ctrl-a h/j/k/l  navigate panes"
echo "    Ctrl-a n/p  next/prev window"
echo "    Ctrl-a Tab  last window"
echo ""
echo "  Attach:  tmux attach -t $SESSION"
echo "  Kill:    tmux kill-session -t $SESSION"
echo ""

tmux attach-session -t "$SESSION"
